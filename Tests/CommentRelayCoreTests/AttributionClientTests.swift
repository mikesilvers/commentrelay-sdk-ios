import XCTest
@testable import CommentRelayCore

final class AttributionClientTests: XCTestCase {
    private var session: URLSession!
    private var tmp: URL!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: cfg)
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("crl-attr-\(UUID().uuidString)")
    }

    override func tearDown() {
        MockURLProtocol.reset()
        try? FileManager.default.removeItem(at: tmp)
        session = nil; tmp = nil
        super.tearDown()
    }

    private func makeClient() -> CommentRelayClient {
        let config = CommentRelayConfiguration(apiKey: "crk_test_abc",
                                               baseURL: URL(string: "https://api.example.com")!)
        return CommentRelayClient(configuration: config, session: session,
                                  cacheDirectory: tmp,
                                  keychainService: "test.attr.\(UUID().uuidString)")
    }

    func test_fetchConfig_surfacesAttribution_whenPresent() async throws {
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = Data(#"""
            {"current":false,"hash":"h","forms":[],
             "show_attribution":true,
             "attribution_url":"https://api.example.com/r/powered-by?p=proj_1"}
            """#.utf8)
            return (resp, body)
        }
        let client = makeClient()
        _ = try await client.fetchConfig(cachedHash: nil)
        let attr = await client.attribution()
        XCTAssertTrue(attr.showAttribution)
        XCTAssertEqual(attr.resolvedLink,
                       URL(string: "https://api.example.com/r/powered-by?p=proj_1"))
    }

    func test_attribution_defaultsHidden_whenFieldsAbsent() async throws {
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data(#"{"current":false,"hash":"h","forms":[]}"#.utf8))
        }
        let client = makeClient()
        _ = try await client.fetchConfig(cachedHash: nil)
        let attr = await client.attribution()
        XCTAssertEqual(attr, .hidden)
    }

    func test_attribution_updatesOnCurrentResponse() async throws {
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data(#"{"current":true,"show_attribution":true,"attribution_url":"https://api.example.com/r/powered-by?p=c"}"#.utf8))
        }
        let client = makeClient()
        _ = try await client.fetchConfig(cachedHash: nil)
        let attr = await client.attribution()
        XCTAssertEqual(attr.resolvedLink,
                       URL(string: "https://api.example.com/r/powered-by?p=c"))
    }

    func test_attribution_retainedAcrossTransportFailure() async throws {
        // First fetch succeeds with attribution and writes a config cache.
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data(#"{"current":false,"hash":"h","forms":[],"show_attribution":true,"attribution_url":"https://api.example.com/r/powered-by?p=p"}"#.utf8))
        }
        let client = makeClient()
        _ = try await client.fetchConfig(cachedHash: nil)
        XCTAssertTrue(await client.attribution().showAttribution)

        // Second fetch fails at the transport layer: fetchConfig falls back to the
        // cached snapshot and must NOT blank the retained attribution.
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        _ = try await client.fetchConfig(cachedHash: nil)
        let after = await client.attribution()
        XCTAssertEqual(after.resolvedLink,
                       URL(string: "https://api.example.com/r/powered-by?p=p"))
    }
}
