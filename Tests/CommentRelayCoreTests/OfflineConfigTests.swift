import XCTest
@testable import CommentRelayCore

final class OfflineConfigTests: XCTestCase {
    private func tmp() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("ocfg-\(UUID())")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true); return u
    }
    private func client(_ s: URLSession, _ d: URL) -> CommentRelayClient {
        CommentRelayClient(configuration: CommentRelayConfiguration(
            apiKey: "k", baseURL: URL(string: "https://example.test")!),
            session: s, cacheDirectory: d, keychainService: "svc-\(UUID())")
    }
    private func form() -> CommentRelayForm {
        CommentRelayForm(id: "a", title: "T", clientFormId: nil, showInPicker: true, responseLimitCount: nil,
            responseLimitType: nil, responseLimitWindowMinutes: nil, moreFeedbackPrompt: nil,
            isActive: true, sortOrder: 1, fields: [])
    }

    func testFetchConfigFallsBackToCacheOnTransportFailure() async throws {
        let dir = tmp()
        URLProtocolStub.error = nil
        URLProtocolStub.responder = { _ in
            (Data("{\"current\":false,\"hash\":\"h1\",\"forms\":[{\"id\":\"a\",\"title\":\"T\",\"show_in_picker\":true,\"response_limit_count\":null,\"response_limit_type\":null,\"response_limit_window_minutes\":null,\"more_feedback_prompt\":null,\"is_active\":true,\"sort_order\":1,\"fields\":[]}]}".utf8), 200)
        }
        let c = client(URLProtocolStub.makeSession(), dir)
        _ = try await c.fetchConfig(cachedHash: nil)
        URLProtocolStub.error = URLError(.notConnectedToInternet)
        let resp = try await c.fetchConfig(cachedHash: nil)
        guard case .updated(let hash, let forms) = resp else { return XCTFail("expected cached .updated") }
        XCTAssertEqual(hash, "h1")
        XCTAssertEqual(forms.map(\.id), ["a"])
    }

    func testFetchConfigThrowsWhenOfflineAndNoCache() async {
        URLProtocolStub.error = URLError(.notConnectedToInternet)
        let c = client(URLProtocolStub.makeSession(), tmp())
        do { _ = try await c.fetchConfig(cachedHash: nil); XCTFail("should throw") }
        catch let e as CommentRelayError { guard case .transport = e else { return XCTFail("wrong: \(e)") } }
        catch { XCTFail("wrong type") }
    }

    func testEffectiveConfigReturnsCachedWhenOffline() async throws {
        let dir = tmp()
        URLProtocolStub.error = nil
        URLProtocolStub.responder = { _ in
            (Data("{\"current\":false,\"hash\":\"h9\",\"forms\":[]}".utf8), 200)
        }
        let c = client(URLProtocolStub.makeSession(), dir)
        _ = try await c.fetchConfig(cachedHash: nil)
        URLProtocolStub.error = URLError(.notConnectedToInternet)
        let resp = try await c.effectiveConfig()
        guard case .updated(let hash, _) = resp else { return XCTFail("expected cached") }
        XCTAssertEqual(hash, "h9")
    }
}
