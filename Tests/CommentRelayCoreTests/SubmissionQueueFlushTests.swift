import XCTest
@testable import CommentRelayCore

final class SubmissionQueueFlushTests: XCTestCase {
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

    // MARK: - FIX 1: Single-flight guard

    /// Two concurrent flushQueue() calls must result in exactly one POST to /submissions,
    /// not two. Without the isFlushing guard the actor reentrancy at the first `await` lets
    /// both calls proceed past the guard simultaneously, doubling the POST.
    func testFlushQueueIsSingleFlight() async throws {
        // 1. Enqueue one offline submission.
        URLProtocolStub.error = URLError(.notConnectedToInternet)
        let session = URLProtocolStub.makeSession()
        let dir = tmp()
        let c = client(session, dir)
        _ = try await c.submit(sub(), attachments: [])
        let pre = await c.pendingSubmissionCount
        XCTAssertEqual(pre, 1)

        // 2. Set up a post-count actor and a gate that stalls the first POST
        //    long enough for the second flushQueue() to enter its body.
        actor Counter { var n = 0; func increment() { n += 1 } }
        let counter = Counter()

        // Gate: the first POST responder blocks until the gate is opened.
        // We open the gate from the test after both flushQueue Tasks have been
        // started, guaranteeing they overlap.
        let (gateStream, gateCont) = AsyncStream<Void>.makeStream()

        let fixedId = UUID().uuidString.lowercased()
        URLProtocolStub.asyncResponder = { req in
            if req.url!.path.hasSuffix("/sdk/v1/submissions") {
                await counter.increment()
                // Stall until the test opens the gate.
                var it = gateStream.makeAsyncIterator()
                _ = await it.next()
            }
            if req.url!.path.hasSuffix("/finalize") {
                return (Data("{\"submissionId\":\"\(fixedId)\",\"status\":\"complete\"}".utf8), 200)
            }
            return (Data("{\"submissionId\":\"\(fixedId)\",\"hasUploads\":false,\"uploadUrls\":[]}".utf8), 200)
        }

        // 3. Fire two concurrent flushQueue() calls.
        URLProtocolStub.error = nil
        async let a: Void = c.flushQueue()
        async let b: Void = c.flushQueue()

        // Give both tasks a chance to enter flushQueue() before unblocking the POST.
        // We yield to let the Swift concurrency runtime schedule them.
        await Task.yield()
        await Task.yield()
        await Task.yield()

        // Open the gate so the (at most one) blocked POST can complete.
        gateCont.yield(())
        gateCont.finish()

        _ = await (a, b)

        // Exactly one POST must have been sent — the second flushQueue() must have
        // bailed out at the isFlushing guard before reaching the network.
        let postCount = await counter.n
        XCTAssertEqual(postCount, 1, "flushQueue must be single-flight: expected 1 POST, got \(postCount)")
        let finalCount = await c.pendingSubmissionCount
        XCTAssertEqual(finalCount, 0)
    }

    // MARK: - FIX 2: Correct happy-path flush test

    /// Proves DELIVERY: the queue entry is fully processed (POST + finalize both hit),
    /// not silently dropped via the terminal-decode error path.
    func testFlushDeliversQueuedNoAttachmentSubmission() async throws {
        // First call (submit) fails offline → queued.
        URLProtocolStub.error = URLError(.notConnectedToInternet)
        let session = URLProtocolStub.makeSession()
        let dir = tmp()
        let c = client(session, dir)
        _ = try await c.submit(sub(), attachments: [])
        let pre = await c.pendingSubmissionCount
        XCTAssertEqual(pre, 1)

        // Record which endpoints were actually hit.
        actor EndpointRecorder {
            var submissionsHit = false
            var finalizeHit = false
            func recordSubmissions() { submissionsHit = true }
            func recordFinalize() { finalizeHit = true }
        }
        let recorder = EndpointRecorder()

        let fixedId = UUID().uuidString.lowercased()
        // Use camelCase keys — APIClient.defaultDecoder() has no convertFromSnakeCase.
        URLProtocolStub.asyncResponder = { req in
            if req.url!.path.hasSuffix("/finalize") {
                await recorder.recordFinalize()
                return (Data("{\"submissionId\":\"\(fixedId)\",\"status\":\"complete\"}".utf8), 200)
            }
            await recorder.recordSubmissions()
            return (Data("{\"submissionId\":\"\(fixedId)\",\"hasUploads\":false,\"uploadUrls\":[]}".utf8), 200)
        }

        URLProtocolStub.error = nil
        await c.flushQueue()

        let post = await c.pendingSubmissionCount
        XCTAssertEqual(post, 0, "entry must be removed after delivery")
        let subHit = await recorder.submissionsHit
        XCTAssertTrue(subHit, "POST /sdk/v1/submissions must be hit during flush")
        let finHit = await recorder.finalizeHit
        XCTAssertTrue(finHit, "POST .../finalize must be hit during flush")
    }

    /// Proves TERMINAL DROP: a decode-error response causes the entry to be removed
    /// (count drops to 0) and finalize is NEVER called. This distinguishes the
    /// terminal-drop path from the delivery path above.
    func testFlushDropsEntryOnTerminalDecodeError() async throws {
        URLProtocolStub.error = URLError(.notConnectedToInternet)
        let session = URLProtocolStub.makeSession()
        let dir = tmp()
        let c = client(session, dir)
        _ = try await c.submit(sub(), attachments: [])
        let pre = await c.pendingSubmissionCount
        XCTAssertEqual(pre, 1)

        actor EndpointRecorder {
            var finalizeHit = false
            func recordFinalize() { finalizeHit = true }
        }
        let recorder = EndpointRecorder()

        URLProtocolStub.error = nil
        URLProtocolStub.asyncResponder = { req in
            if req.url!.path.hasSuffix("/finalize") {
                await recorder.recordFinalize()
                return (Data("{\"submissionId\":\"\(UUID().uuidString.lowercased())\",\"status\":\"complete\"}".utf8), 200)
            }
            // Return a body that fails CommentRelaySubmissionReceipt decoding → terminal error.
            return (Data("{\"garbage\":true}".utf8), 200)
        }

        await c.flushQueue()

        let post = await c.pendingSubmissionCount
        XCTAssertEqual(post, 0, "terminal decode error must drop the entry")
        let finHit = await recorder.finalizeHit
        XCTAssertFalse(finHit, "finalize must NOT be hit on terminal decode error")
        _ = pre
    }

    // MARK: - Retryable failure

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
