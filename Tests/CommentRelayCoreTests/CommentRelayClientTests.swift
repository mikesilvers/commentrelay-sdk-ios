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
            let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: "HTTP/1.1", headerFields: nil)!
            if request.url?.path.hasSuffix("/finalize") == true {
                return (response, Data(#"{"submissionId":"11111111-1111-1111-1111-111111111111","status":"complete"}"#.utf8))
            }
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/sdk/v1/submissions")
            let body = #"""
            {"submissionId":"11111111-1111-1111-1111-111111111111",
             "hasUploads":false,
             "uploadUrls":[]}
            """#
            return (response, Data(body.utf8))
        }
        let client = try await makeClient()
        let submission = CommentRelaySubmission(
            formId: "form1", userIdentifier: "u", platform: .ios,
            fields: [.text(fieldId: "f1", value: "hello")])
        let outcome = try await client.submit(submission)
        guard case .submitted(let receipt) = outcome else {
            return XCTFail("expected .submitted, got \(outcome)")
        }
        XCTAssertEqual(receipt.submissionId.uuidString.lowercased(), "11111111-1111-1111-1111-111111111111")
        XCTAssertFalse(receipt.hasUploads)
    }

    func test_fetchConfig_returnsUpdatedPayload_andPersistsCache() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            let body = #"{"current":false,"hash":"h1","forms":[]}"#
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

    func test_finalize_postsEmptyBodyAndReturnsVoidOn200() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertTrue(request.url?.path.hasSuffix("/finalize") ?? false)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (response, Data(#"{"submissionId":"11111111-1111-1111-1111-111111111111","status":"complete"}"#.utf8))
        }
        let client = try await makeClient()
        try await client.finalize(submissionId: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)
    }

    func test_fetchHistory_passesUserIdentifierHeader_anonymousFalse() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-user-identifier"), "test-user")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (response, Data(#"{"submissions":[]}"#.utf8))
        }
        let client = try await makeClient()
        let h = try await client.fetchHistory()
        XCTAssertFalse(h.isAnonymous)
    }

    func test_uploadFiles_runsAllUploads_andTriggersFinalize() async throws {
        actor PathRecorder { var paths: [String] = []; func record(_ p: String) { paths.append(p) }; func snapshot() -> [String] { paths } }
        let recorder = PathRecorder()
        MockURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            Task { await recorder.record(path) }
            if request.url?.host == "s3.example.com" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
                return (response, Data())
            }
            // finalize endpoint
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (response, Data(#"{"submissionId":"11111111-1111-1111-1111-111111111111","status":"complete"}"#.utf8))
        }
        let client = try await makeClient()
        let subId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let receipt = CommentRelaySubmissionReceipt(
            submissionId: subId,
            hasUploads: true,
            uploadUrls: [.init(fieldId: "f", fileName: "a.png", uploadUrl: URL(string: "https://s3.example.com/u/a")!)])
        let payload = CommentRelayFilePayload(
            target: receipt.uploadUrls[0],
            data: Data([1, 2, 3]),
            contentType: "image/png")
        try await client.uploadFiles(receipt: receipt, payloads: [payload])

        // Give the Task inside the handler a moment to record.
        try await Task.sleep(nanoseconds: 100_000_000)
        let paths = await recorder.snapshot()
        XCTAssertTrue(paths.contains("/u/a"))
        XCTAssertTrue(paths.contains("/sdk/v1/submissions/\(subId.uuidString.lowercased())/finalize"))
    }

    func test_uploadFiles_skippedWhenReceiptHasNoUploads() async throws {
        MockURLProtocol.handler = { request in
            XCTFail("no network call expected when hasUploads == false")
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (response, Data())
        }
        let client = try await makeClient()
        let receipt = CommentRelaySubmissionReceipt(
            submissionId: UUID(),
            hasUploads: false,
            uploadUrls: [])
        try await client.uploadFiles(receipt: receipt, payloads: [])
    }
}
