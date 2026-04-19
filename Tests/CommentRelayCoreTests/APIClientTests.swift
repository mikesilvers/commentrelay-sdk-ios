import XCTest
@testable import CommentRelayCore

final class APIClientTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
    }
    override func tearDown() { MockURLProtocol.reset(); session = nil; super.tearDown() }

    func test_getHealth_injectsApiKeyHeader() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (response, Data())
        }
        let client = APIClient(baseURL: URL(string: "http://x")!, apiKey: "crk_test_abc", session: session)
        _ = try await client.getHealth()
        let req = try XCTUnwrap(MockURLProtocol.requests.first)
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-api-key"), "crk_test_abc")
    }

    func test_error403_mapsViaErrorMapper() async throws {
        MockURLProtocol.handler = { request in
            let resp = HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data(#"{"error":{"code":"FORBIDDEN","message":"revoked"}}"#.utf8))
        }
        let client = APIClient(baseURL: URL(string: "http://x")!, apiKey: "k", session: session)
        do {
            _ = try await client.getHealth()
            XCTFail("expected throw")
        } catch let err as CommentRelayError {
            guard case .forbidden(let m) = err else { return XCTFail("wrong case") }
            XCTAssertEqual(m, "revoked")
        }
    }
}
