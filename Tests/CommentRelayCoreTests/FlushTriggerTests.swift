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

    private let maxPollSteps = 60   // 60 × 50 ms = 3 s ceiling

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

    /// Regression test for the race where a connectivity-restored event fired DURING the
    /// init flush (before the `for await connected in stream` loop is reached) was silently
    /// dropped. The fixed ordering registers the changes stream BEFORE the init flush so any
    /// event during that window is buffered and drained by the loop.
    ///
    /// Design: entry A is written directly to the queue directory (no client needed, bypasses
    /// all retry/backoff), so it has nextEarliestAttempt=nil and is immediately processable.
    /// The gate asyncResponder stalls the init flush's POST for entry A. While the gate holds:
    ///   (a) entry B is enqueued via submit() (offline error → queued, no backoff),
    ///   (b) fake.set(true) fires the connectivity event.
    /// Entry B was added AFTER the init flush's loadAll() ran, so init flush never sees B.
    /// After the gate releases, init flush succeeds for A only. Then the `for await` loop starts.
    ///   RED  (old ordering): event dropped → no second flush → B stays → pendingCount == 1.
    ///   GREEN (new ordering): event buffered → second flush drains B → pendingCount == 0.
    func testConnectivityEventDuringInitFlushIsNotMissed() async throws {
        let dir = tmp()

        // --- 1. Directly write entry A to the queue directory (no client, no backoff) ---
        // Construct a fresh QueuedSubmission using the internal types (available via @testable)
        // and encode it with JSONEncoder so the date format matches what SubmissionQueue reads.
        // This bypasses any seeder-client retry/backoff entirely: nextEarliestAttempt stays nil.
        let entryAId = UUID()
        let queueRoot = dir.appendingPathComponent("queue")
        let entryADir = queueRoot.appendingPathComponent(entryAId.uuidString)
        try FileManager.default.createDirectory(at: entryADir, withIntermediateDirectories: true)
        let entryA = QueuedSubmission(
            localId: entryAId,
            submission: sub(),
            phase: .needsSubmit,
            serverSubmissionId: nil,
            attachments: [],
            attemptCount: 0,
            nextEarliestAttempt: nil,
            createdAt: Date(),
            lastError: nil)
        try JSONEncoder().encode(entryA).write(to: entryADir.appendingPathComponent("entry.json"))

        // --- 2. Set up gate asyncResponder BEFORE creating the test client ---
        // The gate stalls the first POST to /submissions so the init flush is provably
        // in-flight and the `for await connected in stream` loop has NOT yet been reached.
        let (gateStream, gateCont) = AsyncStream<Void>.makeStream()
        let (inFlightStream, inFlightCont) = AsyncStream<Void>.makeStream()

        let fixedIdA = UUID().uuidString.lowercased()
        let fixedIdB = UUID().uuidString.lowercased()
        actor SubmissionCallTracker {
            var count = 0
            func isFirstAndIncrement() -> Bool { count += 1; return count == 1 }
        }
        let tracker = SubmissionCallTracker()

        URLProtocolStub.error = nil
        URLProtocolStub.asyncResponder = { req in
            if req.url!.path.hasSuffix("/sdk/v1/submissions") {
                let isFirst = await tracker.isFirstAndIncrement()
                if isFirst {
                    // Handshake: signal test that init flush's POST is in-flight.
                    inFlightCont.yield(())
                    inFlightCont.finish()
                    // Gate: block until test releases.
                    var it = gateStream.makeAsyncIterator()
                    _ = await it.next()
                    return (Data("{\"submissionId\":\"\(fixedIdA)\",\"hasUploads\":false,\"uploadUrls\":[]}".utf8), 200)
                }
                // Second call: entry B from connectivity-triggered flush.
                return (Data("{\"submissionId\":\"\(fixedIdB)\",\"hasUploads\":false,\"uploadUrls\":[]}".utf8), 200)
            }
            if req.url!.path.hasSuffix("/finalize") {
                // Both finalizes succeed; use a generic success response.
                return (Data("{\"submissionId\":\"\(fixedIdA)\",\"status\":\"complete\"}".utf8), 200)
            }
            return (Data("{\"submissionId\":\"\(fixedIdA)\",\"hasUploads\":false,\"uploadUrls\":[]}".utf8), 200)
        }

        // --- 3. Create test client (triggers startFlushTriggers → init flush Task starts) ---
        let fake = FakeReachability(initial: false)
        let session = URLProtocolStub.makeSession()
        let c = CommentRelayClient(
            configuration: CommentRelayConfiguration(
                baseURL: URL(string: "https://example.test")!,
                apiKey: "k", userIdentifier: "u"),
            session: session,
            cacheDirectory: dir,
            keychainService: "svc-test-\(UUID())",
            reachability: fake)

        // --- 4. Handshake: wait until init flush's POST for entry A is blocked at gate ---
        var inFlightIter = inFlightStream.makeAsyncIterator()
        _ = await inFlightIter.next()
        // Init flush is NOW in-flight (blocked at gate). The `for await connected in stream`
        // loop has NOT yet been reached (old ordering) or not yet consuming (new ordering).

        // --- 5. Enqueue entry B while init flush is in-flight ---
        // error takes precedence over asyncResponder in URLProtocolStub, so this submit()
        // fails the network call immediately and queues B. The already-in-flight gated
        // request (entry A's POST) is unaffected — it's already past the error check.
        URLProtocolStub.error = URLError(.notConnectedToInternet)
        _ = try await c.submit(sub(), attachments: [])
        URLProtocolStub.error = nil
        // Both A (seeded on disk) and B (just queued) should be in the queue.
        let countAB = await c.pendingSubmissionCount
        XCTAssertEqual(countAB, 2,
            "pre-condition: A (on-disk seed) and B (just queued) must both be pending")

        // --- 6. Fire connectivity-restored event WHILE init flush is gated ---
        // OLD ordering: no continuation registered → event dropped → B never flushed.
        // NEW ordering: stream captured before flushQueue() → event buffered → B flushed after A.
        fake.set(true)

        // --- 7. Release gate → init flush unblocks, A processed, init flush exits ---
        // B was added AFTER init flush's loadAll() so init flush never sees B.
        gateCont.yield(())
        gateCont.finish()

        // --- 8. Bounded poll: wait up to 3 s for pendingCount == 0 (50 ms steps) ---
        var remaining = maxPollSteps
        while await c.pendingSubmissionCount > 0 && remaining > 0 {
            try await Task.sleep(nanoseconds: 50_000_000)
            remaining -= 1
        }

        let countFinal = await c.pendingSubmissionCount
        XCTAssertEqual(countFinal, 0,
            "connectivity event during init flush must be buffered (not dropped): B must drain")
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
        var remaining = maxPollSteps
        while await c.pendingSubmissionCount > 0 && remaining > 0 {
            try await Task.sleep(nanoseconds: 50_000_000)
            remaining -= 1
        }

        let countAfter = await c.pendingSubmissionCount
        XCTAssertEqual(countAfter, 0)
    }
}
