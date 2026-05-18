import XCTest
@testable import CommentRelayCore

final class FlushTriggerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        URLProtocolStub.error = nil
        URLProtocolStub.responder = nil
        URLProtocolStub.asyncResponder = nil
    }
    override func tearDown() {
        URLProtocolStub.error = nil
        URLProtocolStub.responder = nil
        URLProtocolStub.asyncResponder = nil
        super.tearDown()
    }

    private func tmp() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("trig-\(UUID())")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true); return u
    }
    private func sub() -> CommentRelaySubmission {
        CommentRelaySubmission(formId: "f", userIdentifier: "u", platform: .ios,
            fields: [.text(fieldId: "1", value: "hi")], osVersion: nil, deviceModel: nil,
            appVersion: nil, sdkVersion: nil, locale: nil, contactPreference: nil,
            contactDetails: nil, sessionId: nil)
    }

    func testConnectivityRestoredTriggersFlush() async throws {
        URLProtocolStub.error = URLError(.notConnectedToInternet)
        let session = URLProtocolStub.makeSession()
        let dir = tmp()
        let fake = FakeReachability(initial: false)
        let c = CommentRelayClient(configuration: CommentRelayConfiguration(
            baseURL: URL(string: "https://example.test")!, apiKey: "k", userIdentifier: "u"),
            session: session, cacheDirectory: dir, keychainService: "svc-\(UUID())",
            reachability: fake)
        _ = try await c.submit(sub(), attachments: [])
        let countBefore = await c.pendingSubmissionCount
        XCTAssertEqual(countBefore, 1)
        URLProtocolStub.error = nil
        URLProtocolStub.responder = { req in
            req.url!.path.hasSuffix("/finalize")
              ? (Data("{\"submissionId\":\"\(UUID().uuidString)\",\"status\":\"complete\"}".utf8), 200)
              : (Data("{\"submissionId\":\"\(UUID().uuidString)\",\"hasUploads\":false,\"uploadUrls\":[]}".utf8), 200)
        }
        fake.set(true)                              // connectivity restored

        // Wait deterministically: poll pendingSubmissionCount until it reaches 0,
        // with a bounded timeout (~3 s in 50 ms steps) so a genuine failure doesn't hang.
        var remaining = 60  // 60 × 50ms = 3 s ceiling
        while await c.pendingSubmissionCount > 0 && remaining > 0 {
            try await Task.sleep(nanoseconds: 50_000_000)
            remaining -= 1
        }

        let countAfter = await c.pendingSubmissionCount
        XCTAssertEqual(countAfter, 0)
    }
}
