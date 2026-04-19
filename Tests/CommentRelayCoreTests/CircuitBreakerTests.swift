// Tests/CommentRelayCoreTests/CircuitBreakerTests.swift
import XCTest
@testable import CommentRelayCore

final class CircuitBreakerTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
    }
    override func tearDown() { MockURLProtocol.reset(); session = nil; super.tearDown() }

    func test_403OnSubmit_disablesClientUntilReset() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (response, Data(#"{"error":{"code":"FORBIDDEN","message":"revoked"}}"#.utf8))
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("crl-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let config = CommentRelayConfiguration(baseURL: URL(string: "http://x")!, apiKey: "k", userIdentifier: "u")
        let client = CommentRelayClient(configuration: config, session: session, cacheDirectory: dir, keychainService: "crl.test.\(UUID().uuidString)")

        let submission = CommentRelaySubmission(categoryId: "c", userIdentifier: "u", platform: .ios, fields: [])
        do { _ = try await client.submit(submission); XCTFail() } catch {}
        let enabledAfter403 = await client.isEnabled
        XCTAssertFalse(enabledAfter403)

        // Second call short-circuits and throws .forbidden without hitting network.
        MockURLProtocol.reset()
        do { _ = try await client.ping(); XCTFail() } catch let e as CommentRelayError {
            guard case .forbidden = e else { return XCTFail("wrong case") }
            XCTAssertEqual(MockURLProtocol.requests.count, 0)
        }

        await client.reset()
        let enabledAfterReset = await client.isEnabled
        XCTAssertTrue(enabledAfterReset)
    }
}
