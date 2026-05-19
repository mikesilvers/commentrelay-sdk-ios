import XCTest
@testable import CommentRelayCore

final class ClientSubmitOutcomeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        URLProtocolStub.error = nil
        URLProtocolStub.responder = nil
    }
    override func tearDown() {
        URLProtocolStub.error = nil
        URLProtocolStub.responder = nil
        super.tearDown()
    }

    private func tmp() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("cso-\(UUID())")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true); return u
    }
    private func client(_ session: URLSession, _ dir: URL, queueing: Bool = true) -> CommentRelayClient {
        let cfg = CommentRelayConfiguration(apiKey: "k",
                                            baseURL: URL(string: "https://example.test")!,
                                            userIdentifier: "u",
                                            offlineQueueingEnabled: queueing)
        return CommentRelayClient(configuration: cfg, session: session,
                                  cacheDirectory: dir, keychainService: "svc-\(UUID())")
    }
    private func sub() -> CommentRelaySubmission {
        CommentRelaySubmission(formId: "f", userIdentifier: "u", platform: .ios,
            fields: [.text(fieldId: "1", value: "hi")], osVersion: nil, deviceModel: nil,
            appVersion: nil, sdkVersion: nil, locale: nil, contactPreference: nil,
            contactDetails: nil, sessionId: nil)
    }

    func testOfflineSubmitReturnsQueuedAndIncrementsCount() async throws {
        URLProtocolStub.error = URLError(.notConnectedToInternet)
        let session = URLProtocolStub.makeSession()
        let dir = tmp()
        let c = client(session, dir)
        let outcome = try await c.submit(sub(), attachments: [])
        guard case .queued(let id) = outcome else { return XCTFail("expected .queued, got \(outcome)") }
        XCTAssertNotNil(id)
        let count = await c.pendingSubmissionCount
        XCTAssertEqual(count, 1)
    }

    func testTerminalErrorStillThrowsAndDoesNotQueue() async {
        URLProtocolStub.responder = { _ in (Data("{\"message\":\"bad\"}".utf8), 400) }
        let session = URLProtocolStub.makeSession()
        let dir = tmp()
        let c = client(session, dir)
        do { _ = try await c.submit(sub(), attachments: []); XCTFail("should throw") }
        catch let e as CommentRelayError { guard case .badRequest = e else { return XCTFail("wrong: \(e)") } }
        catch { XCTFail("wrong type") }
        let count = await c.pendingSubmissionCount
        XCTAssertEqual(count, 0)
    }

    func testQueueingDisabledRethrowsTransport() async {
        URLProtocolStub.error = URLError(.notConnectedToInternet)
        let session = URLProtocolStub.makeSession()
        let c = client(session, tmp(), queueing: false)
        do { _ = try await c.submit(sub(), attachments: []); XCTFail("should throw") }
        catch let e as CommentRelayError { guard case .transport = e else { return XCTFail("wrong: \(e)") } }
        catch { XCTFail("wrong type") }
    }
}
