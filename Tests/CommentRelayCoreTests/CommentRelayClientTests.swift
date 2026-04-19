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

        let client = CommentRelayClient(
            baseURL: URL(string: "http://localhost:3000")!,
            session: session)
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

        let client = CommentRelayClient(
            baseURL: URL(string: "http://localhost:3000")!,
            session: session)
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

        let client = CommentRelayClient(
            baseURL: URL(string: "http://localhost:3000")!,
            session: session)
        let ok = try await client.ping()

        XCTAssertFalse(ok)
    }

    func test_ping_throws_onTransportError() async {
        struct BoomError: Error, Equatable {}
        MockURLProtocol.handler = { _ in throw BoomError() }

        let client = CommentRelayClient(
            baseURL: URL(string: "http://localhost:3000")!,
            session: session)

        do {
            _ = try await client.ping()
            XCTFail("expected ping() to throw")
        } catch {
            // URLSession wraps the underlying error; assert it surfaced.
            XCTAssertNotNil(error)
        }
    }
}
