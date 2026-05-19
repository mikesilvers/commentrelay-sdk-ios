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
            apiKey: "k", baseURL: URL(string: "https://example.test")!, userIdentifier: "u"),
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

    // MARK: - Fix B: POST success + retryable finalize failure → queues for finalize, no re-POST

    /// Fix B core: when POST succeeds but finalize returns a retryable 500, submit() must:
    ///   1. Return .queued
    ///   2. Store the entry with the server's submissionId (from POST) and phase .needsFinalize
    ///   3. On subsequent flushQueue(), finalize without re-POSTing (POST hit exactly once total)
    func testPostSuccessThenRetryableFinalizeFailureQueuesForFinalizeNoRepost() async throws {
        let session = URLProtocolStub.makeSession()
        let dir = tmp()
        let c = client(session, dir)

        // Track POST /sdk/v1/submissions calls
        actor PostCounter { var n = 0; func increment() { n += 1 } }
        let postCounter = PostCounter()

        let fixedServerId = UUID()
        let fixedServerIdStr = fixedServerId.uuidString.lowercased()

        // Phase 1: POST succeeds, finalize returns 500 (retryable)
        URLProtocolStub.asyncResponder = { req in
            if req.url!.path.hasSuffix("/sdk/v1/submissions") && req.httpMethod == "POST" {
                await postCounter.increment()
                let body = "{\"submissionId\":\"\(fixedServerIdStr)\",\"hasUploads\":false,\"uploadUrls\":[]}"
                return (Data(body.utf8), 200)
            }
            if req.url!.path.contains("/finalize") {
                // Return 500 (retryable server error)
                return (Data("{\"message\":\"server error\"}".utf8), 500)
            }
            return (Data("{}".utf8), 200)
        }

        let outcome = try await c.submit(sub(), attachments: [])
        guard case .queued(let localId) = outcome else {
            return XCTFail("expected .queued when finalize fails retryably, got \(outcome)")
        }
        XCTAssertNotNil(localId)

        // Assert queued entry has serverSubmissionId == fixedServerId and phase == .needsFinalize
        // Read from disk: queue entries live at <cacheDir>/queue/<localId>/entry.json
        let queueDir = dir.appendingPathComponent("queue")
        let queueContents = try FileManager.default.contentsOfDirectory(
            at: queueDir, includingPropertiesForKeys: nil)
        XCTAssertEqual(queueContents.count, 1, "should have exactly 1 queued entry on disk")
        let entryURL = try XCTUnwrap(queueContents.first).appendingPathComponent("entry.json")
        let entryData = try Data(contentsOf: entryURL)
        let entry = try JSONDecoder().decode(QueuedSubmission.self, from: entryData)
        XCTAssertEqual(entry.serverSubmissionId, fixedServerId,
            "queued entry must carry the server's submissionId so flush can finalize without re-POSTing")
        XCTAssertEqual(entry.phase, .needsFinalize,
            "queued entry must be in .needsFinalize phase — not .needsSubmit")

        // Phase 2: switch finalize to 200, flush should complete WITHOUT re-POSTing
        URLProtocolStub.asyncResponder = { req in
            if req.url!.path.hasSuffix("/sdk/v1/submissions") && req.httpMethod == "POST" {
                await postCounter.increment()
                let body = "{\"submissionId\":\"\(fixedServerIdStr)\",\"hasUploads\":false,\"uploadUrls\":[]}"
                return (Data(body.utf8), 200)
            }
            if req.url!.path.contains("/finalize") {
                return (Data("{\"submissionId\":\"\(fixedServerIdStr)\",\"status\":\"complete\"}".utf8), 200)
            }
            return (Data("{}".utf8), 200)
        }

        await c.flushQueue()

        let pendingCount = await c.pendingSubmissionCount
        XCTAssertEqual(pendingCount, 0, "queue must be empty after successful finalize")

        let totalPostCount = await postCounter.n
        XCTAssertEqual(totalPostCount, 1,
            "POST /sdk/v1/submissions must be hit EXACTLY ONCE — no duplicate re-POST on finalize retry; got \(totalPostCount)")
    }

    // MARK: - Fix A: flushQueue broadcasts pending count on .pause

    /// Fix A: when flushQueue processes a terminal entry (deleted) then hits a .pause (403),
    /// the pending count broadcast must still fire so observers see the reduced count
    /// from the terminal deletion, even though .pause causes an early return.
    func testFlushPauseBroadcastsPendingCount() async throws {
        // Enqueue 2 entries with network failing (offline)
        URLProtocolStub.error = URLError(.notConnectedToInternet)
        let session = URLProtocolStub.makeSession()
        let dir = tmp()
        let c = client(session, dir)

        _ = try await c.submit(sub(), attachments: [])
        _ = try await c.submit(sub(), attachments: [])
        let preFlushed = await c.pendingSubmissionCount
        XCTAssertEqual(preFlushed, 2)

        // Subscribe to the stream BEFORE flush (so we capture the broadcast during flush)
        let stream = await c.pendingSubmissionCountStream()

        // Collect a bounded set of values from the stream
        // We expect at minimum the initial value (2) and a post-terminal-delete value (1)
        actor ValueCollector {
            var values: [Int] = []
            func append(_ v: Int) { values.append(v) }
            func contains(_ v: Int) -> Bool { values.contains(v) }
        }
        let collector = ValueCollector()

        // Set up responder: first entry → 400 (terminal/badRequest), second → 403 (pause/forbidden)
        actor RequestCounter { var n = 0; func next() -> Int { n += 1; return n } }
        let reqCounter = RequestCounter()

        URLProtocolStub.error = nil
        URLProtocolStub.asyncResponder = { [reqCounter] req in
            guard req.url!.path.hasSuffix("/sdk/v1/submissions") else {
                return (Data("{}".utf8), 200)
            }
            let callNum = await reqCounter.next()
            if callNum == 1 {
                // First entry: 400 → terminal → deleted from queue
                return (Data("{\"message\":\"bad\"}".utf8), 400)
            } else {
                // Second entry: 403 → pause → early return in flushQueue
                return (Data("{\"message\":\"forbidden\"}".utf8), 403)
            }
        }

        // Collect stream values in a background task while flush runs.
        // The collector task runs for at most 3 seconds or until it sees count=1.
        let collectorTask = Task {
            for await v in stream {
                await collector.append(v)
                if v == 1 { break }  // saw the post-terminal count; stop
            }
        }

        // Run flush
        await c.flushQueue()

        // Give the collector task up to 1s to process the broadcast after flush completes
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while !(await collector.contains(1)) {
            if ContinuousClock.now >= deadline { break }
            await Task.yield()
        }
        collectorTask.cancel()

        let observed = await collector.values
        // The stream must have emitted a value of 1 (one entry deleted, one still queued due to pause)
        // This proves broadcastPendingCount() ran on the .pause path (Fix A)
        XCTAssertTrue(observed.contains(1),
            "stream must observe count=1 after terminal delete + pause: fix A broadcasts before return; got \(observed)")

        // Final count: 1 entry remains (the one that hit 403/pause was retained in the queue;
        // note: 403 also disables the client via postSubmission's disable() call, so 403 IS forbidden)
        // Actually after 403: client is disabled (isEnabled=false) so entry stays.
        // The terminal entry (400) was deleted → count=1
        let finalCount = await c.pendingSubmissionCount
        XCTAssertEqual(finalCount, 1, "one entry remains after pause (terminal entry was deleted)")
    }

    // MARK: - CRLBS-116: Post-POST .pause enqueues for resume, still throws

    func testPostSuccessThenForbiddenFinalizeQueuesForFinalizeAndThrows() async throws {
        let session = URLProtocolStub.makeSession()
        let dir = tmp()
        let c = client(session, dir)
        actor PostCounter { var n = 0; func increment() { n += 1 } }
        let postCounter = PostCounter()
        let fixedServerId = UUID()
        let fixedServerIdStr = fixedServerId.uuidString.lowercased()

        URLProtocolStub.asyncResponder = { req in
            if req.url!.path.hasSuffix("/sdk/v1/submissions") && req.httpMethod == "POST" {
                await postCounter.increment()
                return (Data("{\"submissionId\":\"\(fixedServerIdStr)\",\"hasUploads\":false,\"uploadUrls\":[]}".utf8), 200)
            }
            if req.url!.path.contains("/finalize") {
                return (Data("{\"message\":\"forbidden\"}".utf8), 403)
            }
            return (Data("{}".utf8), 200)
        }

        do {
            _ = try await c.submit(sub(), attachments: [])
            XCTFail("submit must throw .forbidden after a 403 post-POST")
        } catch let e as CommentRelayError {
            guard case .forbidden = e else { return XCTFail("expected .forbidden, got \(e)") }
        } catch { return XCTFail("wrong error type: \(error)") }

        let queueDir = dir.appendingPathComponent("queue")
        let queueContents = try FileManager.default.contentsOfDirectory(at: queueDir, includingPropertiesForKeys: nil)
        XCTAssertEqual(queueContents.count, 1, "403 after a successful POST must leave a recoverable queued entry")
        let entryURL = try XCTUnwrap(queueContents.first).appendingPathComponent("entry.json")
        let entry = try JSONDecoder().decode(QueuedSubmission.self, from: Data(contentsOf: entryURL))
        XCTAssertEqual(entry.serverSubmissionId, fixedServerId)
        XCTAssertEqual(entry.phase, .needsFinalize)

        URLProtocolStub.asyncResponder = { req in
            if req.url!.path.hasSuffix("/sdk/v1/submissions") && req.httpMethod == "POST" {
                await postCounter.increment()
                return (Data("{\"submissionId\":\"\(fixedServerIdStr)\",\"hasUploads\":false,\"uploadUrls\":[]}".utf8), 200)
            }
            if req.url!.path.contains("/finalize") {
                return (Data("{\"submissionId\":\"\(fixedServerIdStr)\",\"status\":\"complete\"}".utf8), 200)
            }
            return (Data("{}".utf8), 200)
        }
        await c.reset()
        await c.flushQueue()

        let pending = await c.pendingSubmissionCount
        XCTAssertEqual(pending, 0, "queue must drain after reset()+flush finalizes the existing record")
        let posts = await postCounter.n
        XCTAssertEqual(posts, 1, "POST must be hit EXACTLY ONCE — finalize-first, no duplicate; got \(posts)")
    }

    func testPostSuccessThenForbiddenUploadQueuesAtNeedsUpload() async throws {
        let session = URLProtocolStub.makeSession()
        let dir = tmp()
        let c = client(session, dir)
        let fixedServerId = UUID()
        let fixedServerIdStr = fixedServerId.uuidString.lowercased()

        URLProtocolStub.asyncResponder = { req in
            if req.url!.path.hasSuffix("/sdk/v1/submissions") && req.httpMethod == "POST" {
                let body = "{\"submissionId\":\"\(fixedServerIdStr)\",\"hasUploads\":true,\"uploadUrls\":[{\"fieldId\":\"photo\",\"fileName\":\"a.png\",\"uploadUrl\":\"https://example.test/upload/a\"}]}"
                return (Data(body.utf8), 200)
            }
            return (Data("{\"message\":\"forbidden\"}".utf8), 403)
        }

        let att = CommentRelayQueuedAttachment(fieldId: "photo", fileName: "a.png",
                                               contentType: "image/png", data: Data([1, 2, 3]))
        do {
            _ = try await c.submit(sub(), attachments: [att])
            XCTFail("submit must throw .forbidden after a 403 during upload")
        } catch let e as CommentRelayError {
            guard case .forbidden = e else { return XCTFail("expected .forbidden, got \(e)") }
        } catch { return XCTFail("wrong error type: \(error)") }

        let queueDir = dir.appendingPathComponent("queue")
        let queueContents = try FileManager.default.contentsOfDirectory(at: queueDir, includingPropertiesForKeys: nil)
        XCTAssertEqual(queueContents.count, 1)
        let entryURL = try XCTUnwrap(queueContents.first).appendingPathComponent("entry.json")
        let entry = try JSONDecoder().decode(QueuedSubmission.self, from: Data(contentsOf: entryURL))
        XCTAssertEqual(entry.serverSubmissionId, fixedServerId)
        XCTAssertEqual(entry.phase, .needsUpload)
    }

    func testPostSuccessThenForbiddenWithQueueingDisabledThrowsAndDoesNotQueue() async throws {
        let session = URLProtocolStub.makeSession()
        let dir = tmp()
        let cfg = CommentRelayConfiguration(apiKey: "k",
                                            baseURL: URL(string: "https://example.test")!,
                                            userIdentifier: "u",
                                            offlineQueueingEnabled: false)
        let c = CommentRelayClient(configuration: cfg, session: session,
                                   cacheDirectory: dir, keychainService: "svc-\(UUID())")
        let fixedServerIdStr = UUID().uuidString.lowercased()
        URLProtocolStub.asyncResponder = { req in
            if req.url!.path.hasSuffix("/sdk/v1/submissions") && req.httpMethod == "POST" {
                return (Data("{\"submissionId\":\"\(fixedServerIdStr)\",\"hasUploads\":false,\"uploadUrls\":[]}".utf8), 200)
            }
            if req.url!.path.contains("/finalize") {
                return (Data("{\"message\":\"forbidden\"}".utf8), 403)
            }
            return (Data("{}".utf8), 200)
        }
        do {
            _ = try await c.submit(sub(), attachments: [])
            XCTFail("must throw when queueing disabled")
        } catch let e as CommentRelayError {
            guard case .forbidden = e else { return XCTFail("expected .forbidden, got \(e)") }
        } catch { return XCTFail("wrong error type: \(error)") }
        let queueDir = dir.appendingPathComponent("queue")
        let exists = FileManager.default.fileExists(atPath: queueDir.path)
        let count = exists ? (try FileManager.default.contentsOfDirectory(at: queueDir, includingPropertiesForKeys: nil)).count : 0
        XCTAssertEqual(count, 0, "queueing disabled → no entry persisted (unchanged behavior)")
    }

    func testPrePostForbiddenThrowsAndDoesNotQueue() async throws {
        let session = URLProtocolStub.makeSession()
        let dir = tmp()
        let c = client(session, dir)
        URLProtocolStub.asyncResponder = { req in
            if req.url!.path.hasSuffix("/sdk/v1/submissions") && req.httpMethod == "POST" {
                return (Data("{\"message\":\"forbidden\"}".utf8), 403)
            }
            return (Data("{}".utf8), 200)
        }
        do {
            _ = try await c.submit(sub(), attachments: [])
            XCTFail("must throw .forbidden")
        } catch let e as CommentRelayError {
            guard case .forbidden = e else { return XCTFail("expected .forbidden, got \(e)") }
        } catch { return XCTFail("wrong error type: \(error)") }
        let queueDir = dir.appendingPathComponent("queue")
        let exists = FileManager.default.fileExists(atPath: queueDir.path)
        let count = exists ? (try FileManager.default.contentsOfDirectory(at: queueDir, includingPropertiesForKeys: nil)).count : 0
        XCTAssertEqual(count, 0, "pre-POST 403 must not enqueue (no server record yet) — unchanged")
    }
}
