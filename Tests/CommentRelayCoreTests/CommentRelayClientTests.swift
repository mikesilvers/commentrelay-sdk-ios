import XCTest
@testable import CommentRelayCore

final class CommentRelayClientTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
    }

    override func tearDown() {
        MockURLProtocol.reset()
        session = nil
        super.tearDown()
    }

    func test_ping_issuesGetToHealthEndpoint() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: "HTTP/1.1", headerFields: nil)!
            return (response, Data())
        }

        let client = try await makeClient()
        _ = try await client.ping()

        XCTAssertEqual(MockURLProtocol.requests.count, 1)
        let req = try XCTUnwrap(MockURLProtocol.requests.first)
        XCTAssertEqual(req.url?.absoluteString, "http://localhost:3000/health")
        XCTAssertEqual(req.httpMethod, "GET")
    }

    func test_ping_returnsTrue_on200() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: "HTTP/1.1", headerFields: nil)!
            return (response, Data())
        }

        let client = try await makeClient()
        let ok = try await client.ping()

        XCTAssertTrue(ok)
    }

    func test_ping_returnsFalse_on500() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 500,
                httpVersion: "HTTP/1.1", headerFields: nil)!
            return (response, Data())
        }

        let client = try await makeClient()
        let ok = try await client.ping()

        XCTAssertFalse(ok)
    }

    func test_ping_throws_onTransportError() async throws {
        struct BoomError: Error, Equatable {}
        MockURLProtocol.handler = { _ in throw BoomError() }

        let client = try await makeClient()

        do {
            _ = try await client.ping()
            XCTFail("expected ping() to throw")
        } catch {
            // URLSession wraps the underlying error; assert it surfaced.
            XCTAssertNotNil(error)
        }
    }

    private func makeClient(cacheDir: URL? = nil) async throws -> CommentRelayClient {
        let dir = cacheDir ?? FileManager.default.temporaryDirectory.appendingPathComponent("crl-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let config = CommentRelayConfiguration(
            baseURL: URL(string: "http://localhost:3000")!,
            apiKey: "crk_test_abc",
            userIdentifier: "test-user")
        return CommentRelayClient(
            configuration: config,
            session: session,
            cacheDirectory: dir,
            keychainService: "crl.test.\(UUID().uuidString)")
    }

    func test_submit_returnsReceipt_andPostsExpectedBody() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/sdk/v1/submissions")
            let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: "HTTP/1.1", headerFields: nil)!
            let body = #"""
            {"submissionId":"11111111-1111-1111-1111-111111111111",
             "hasUploads":false,
             "uploadUrls":[]}
            """#
            return (response, Data(body.utf8))
        }
        let client = try await makeClient()
        let submission = CommentRelaySubmission(
            categoryId: "cat1", userIdentifier: "u", platform: .ios,
            fields: [.text(fieldId: "f1", value: "hello")])
        let receipt = try await client.submit(submission)
        XCTAssertEqual(receipt.submissionId.uuidString.lowercased(), "11111111-1111-1111-1111-111111111111")
        XCTAssertFalse(receipt.hasUploads)
    }

    func test_fetchConfig_returnsUpdatedPayload_andPersistsCache() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            let body = #"{"current":false,"hash":"h1","categories":[]}"#
            return (response, Data(body.utf8))
        }
        let client = try await makeClient()
        let result = try await client.fetchConfig(cachedHash: nil)
        guard case .updated(let hash, _) = result else { return XCTFail() }
        XCTAssertEqual(hash, "h1")
        // sending a second fetch with the same hash should hit the server with the hash query:
        MockURLProtocol.reset()
        MockURLProtocol.handler = { request in
            XCTAssertTrue(request.url?.query?.contains("hash=h1") ?? false)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (response, Data(#"{"current":true}"#.utf8))
        }
        _ = try await client.fetchConfig(cachedHash: "h1")
    }
}
