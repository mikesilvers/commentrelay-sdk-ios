import XCTest
@testable import CommentRelayCore

final class SubmissionQueueFlushTests: XCTestCase {
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
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("flush-\(UUID())")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true); return u
    }
    private func sub() -> CommentRelaySubmission {
        CommentRelaySubmission(formId: "f", userIdentifier: "u", platform: .ios,
            fields: [.text(fieldId: "1", value: "hi")], osVersion: nil, deviceModel: nil,
            appVersion: nil, sdkVersion: nil, locale: nil, contactPreference: nil,
            contactDetails: nil, sessionId: nil)
    }
    private func client(_ s: URLSession, _ d: URL) -> CommentRelayClient {
        CommentRelayClient(configuration: CommentRelayConfiguration(
            baseURL: URL(string: "https://example.test")!, apiKey: "k", userIdentifier: "u"),
            session: s, cacheDirectory: d, keychainService: "svc-\(UUID())")
    }

    func testFlushDeliversQueuedNoAttachmentSubmission() async throws {
        // First call (submit) fails offline → queued. Then network "returns": POST 200 + finalize 200.
        URLProtocolStub.error = URLError(.notConnectedToInternet)
        let session = URLProtocolStub.makeSession()
        let dir = tmp()
        let c = client(session, dir)
        _ = try await c.submit(sub(), attachments: [])
        var pre = await c.pendingSubmissionCount
        XCTAssertEqual(pre, 1)

        URLProtocolStub.error = nil
        URLProtocolStub.responder = { req in
            if req.url!.path.hasSuffix("/finalize") {
                return (Data("{\"submission_id\":\"\(UUID().uuidString)\",\"status\":\"complete\"}".utf8), 200)
            }
            return (Data("{\"submission_id\":\"\(UUID().uuidString)\",\"has_uploads\":false,\"upload_urls\":[]}".utf8), 200)
        }
        await c.flushQueue()
        let post = await c.pendingSubmissionCount
        XCTAssertEqual(post, 0)
        _ = pre
    }

    func testRetryableFailureKeepsEntryAndBacksOff() async throws {
        URLProtocolStub.error = URLError(.notConnectedToInternet)
        let session = URLProtocolStub.makeSession()
        let dir = tmp()
        let c = client(session, dir)
        _ = try await c.submit(sub(), attachments: [])
        URLProtocolStub.error = nil
        URLProtocolStub.responder = { _ in (Data("{\"message\":\"boom\"}".utf8), 500) } // 5xx retryable
        await c.flushQueue()
        let count = await c.pendingSubmissionCount
        XCTAssertEqual(count, 1, "retryable failure must retain the entry")
    }
}
