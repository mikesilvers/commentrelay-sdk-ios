# CRLBS-116 — 403-after-POST must not orphan the server record — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a 403 (`.pause`) occurs in `submit(_:attachments:)` *after* the POST has already created a server record, persist a recoverable queue entry (carrying `serverSubmissionId` + correct phase) while still throwing `.forbidden` — so `reset()` + a flush trigger finalizes the existing record via finalize-first instead of orphaning it.

**Architecture:** One-branch change in `CommentRelayClient.submit`'s post-POST `catch`: split `case .terminal, .pause` so `.pause` enqueues (respecting `offlineQueueingEnabled`) then rethrows. No changes to `advance`/`SubmissionQueue`/`RetryPolicy`/circuit-breaker/triggers — resume uses the existing 403 pause/resume contract.

**Tech Stack:** Swift 6 / SPM / XCTest; reuses the existing `URLProtocolStub` async-responder + `PostCounter` test harness.

**Spec:** `docs/superpowers/specs/2026-05-19-pause-after-post-orphan-design.md`
**Ticket:** CRLBS-116. **Branch:** `feature/CRLBS-116-pause-after-post-orphan` (off `develop`, already checked out, spec already committed).

## Conventions
- Commits: `type(CRLBS-116): description` ending with `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`. Push after the task.
- TDD strictly; SourceKit cross-file "cannot find type"/XCTest/line-~169 type-check-timeout are KNOWN false positives — `swift test` is authoritative. `swift package clean` if an unexplained linker error appears.
- Verify on the macOS host from `/Users/mikesilvers/repos/commentrelay-sdk/commentrelay-sdk-ios`. Baseline `swift test` = 194 / 0.

## File structure
| File | Responsibility | Action |
|---|---|---|
| `Sources/CommentRelayCore/Public/CommentRelayClient.swift` | post-POST `catch` `.pause` branch | Modify (one `switch`) |
| `Tests/CommentRelayCoreTests/SubmissionQueueFlushTests.swift` | new regression tests | Add tests |

The current post-POST `catch` (in `submit(_:attachments:)`, after the `// POST succeeded` comment) is exactly:
```swift
        } catch let err as CommentRelayError {
            switch RetryPolicy.classify(err) {
            case .terminal, .pause:
                throw err
            case .retry:
                guard configuration.offlineQueueingEnabled else { throw err }
                // Server already has the record — resume via finalize-first (no re-POST for the
                // no-attachment path; attachments still re-POST for fresh presigned URLs by design).
                let id = try await submissionQueue.enqueue(
                    submission, attachments: attachments,
                    serverSubmissionId: receipt.submissionId,
                    startingPhase: receipt.hasUploads ? .needsUpload : .needsFinalize)
                await broadcastPendingCount()
                return .queued(localId: id)
            }
        }
```
(The PRE-POST `catch` earlier in the same function — `case .terminal, .pause: throw err` / `case .retry: ... enqueue fresh ...` — MUST NOT be changed.)

`SubmissionQueueFlushTests` already provides reusable helpers: `tmp() -> URL`, `sub() -> CommentRelaySubmission`, `client(_ s: URLSession, _ d: URL) -> CommentRelayClient` (uses the test-only init), an `actor PostCounter { var n = 0; func increment() }` pattern, `URLProtocolStub` with `error`/`responder`/`asyncResponder`/`makeSession()` reset in setUp/tearDown, and reads queue entries from disk at `<cacheDir>/queue/<localId>/entry.json` decoded as `QueuedSubmission`. `CommentRelayClient` has `reset()` (re-enables after circuit-breaker), `pendingSubmissionCount`, `flushQueue()`.

---

## Task 1: Post-POST `.pause` enqueues for resume, still throws

**Files:**
- Modify: `Sources/CommentRelayCore/Public/CommentRelayClient.swift` (post-POST `catch` only)
- Test: `Tests/CommentRelayCoreTests/SubmissionQueueFlushTests.swift` (add 4 tests)

- [ ] **Step 1: Write the failing tests**

Append these four methods inside `final class SubmissionQueueFlushTests` (before the closing brace). They reuse the file's existing `tmp()`, `sub()`, `client(_:_:)` helpers and `URLProtocolStub`. Mirror the established `testPostSuccessThenRetryableFinalizeFailureQueuesForFinalizeNoRepost` structure (disk-read of `entry.json`, `PostCounter`).

```swift
    func testPostSuccessThenForbiddenFinalizeQueuesForFinalizeAndThrows() async throws {
        let session = URLProtocolStub.makeSession()
        let dir = tmp()
        let c = client(session, dir)
        actor PostCounter { var n = 0; func increment() { n += 1 } }
        let postCounter = PostCounter()
        let fixedServerId = UUID()
        let fixedServerIdStr = fixedServerId.uuidString.lowercased()

        // Phase 1: POST 200, finalize 403 (forbidden → .pause)
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

        // A recoverable entry must exist with the server's id and .needsFinalize
        let queueDir = dir.appendingPathComponent("queue")
        let queueContents = try FileManager.default.contentsOfDirectory(at: queueDir, includingPropertiesForKeys: nil)
        XCTAssertEqual(queueContents.count, 1, "403 after a successful POST must leave a recoverable queued entry")
        let entryURL = try XCTUnwrap(queueContents.first).appendingPathComponent("entry.json")
        let entry = try JSONDecoder().decode(QueuedSubmission.self, from: Data(contentsOf: entryURL))
        XCTAssertEqual(entry.serverSubmissionId, fixedServerId)
        XCTAssertEqual(entry.phase, .needsFinalize)

        // Phase 2: reset() re-enables; finalize → 200; flush finalizes WITHOUT re-POSTing
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

        // POST 200 with an upload target; PUT (S3 upload) → 403
        URLProtocolStub.asyncResponder = { req in
            if req.url!.path.hasSuffix("/sdk/v1/submissions") && req.httpMethod == "POST" {
                let body = "{\"submissionId\":\"\(fixedServerIdStr)\",\"hasUploads\":true,\"uploadUrls\":[{\"fieldId\":\"photo\",\"fileName\":\"a.png\",\"uploadUrl\":\"https://example.test/upload/a\"}]}"
                return (Data(body.utf8), 200)
            }
            // any non-submissions request (the presigned PUT) → 403
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
        let cfg = CommentRelayConfiguration(baseURL: URL(string: "https://example.test")!,
                                            apiKey: "k", userIdentifier: "u",
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
        // The POST itself → 403 (pre-POST; no server record exists)
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
```

- [ ] **Step 2: Run the new tests, verify they FAIL for the right reason**

Run: `cd /Users/mikesilvers/repos/commentrelay-sdk/commentrelay-sdk-ios && swift test --filter SubmissionQueueFlushTests 2>&1 | tail -30`
Expected: the two new post-POST-403 tests FAIL — `testPostSuccessThenForbiddenFinalizeQueuesForFinalizeAndThrows` (no queued entry: `queueContents.count` is 0, because pre-fix `.pause` throws without enqueuing) and `testPostSuccessThenForbiddenUploadQueuesAtNeedsUpload` (same). `testPostSuccessThenForbiddenWithQueueingDisabledThrowsAndDoesNotQueue` and `testPrePostForbiddenThrowsAndDoesNotQueue` PASS already (they assert the unchanged behavior). Confirm the two failures are the missing-entry assertions, not compile errors.

- [ ] **Step 3: Implement — split `.terminal, .pause` in the post-POST catch**

In `Sources/CommentRelayCore/Public/CommentRelayClient.swift`, in the **post-POST** `catch` (the one after the `// POST succeeded: the server now holds a record` comment — NOT the pre-POST one), replace exactly:
```swift
            case .terminal, .pause:
                throw err
            case .retry:
                guard configuration.offlineQueueingEnabled else { throw err }
                // Server already has the record — resume via finalize-first (no re-POST for the
                // no-attachment path; attachments still re-POST for fresh presigned URLs by design).
                let id = try await submissionQueue.enqueue(
                    submission, attachments: attachments,
                    serverSubmissionId: receipt.submissionId,
                    startingPhase: receipt.hasUploads ? .needsUpload : .needsFinalize)
                await broadcastPendingCount()
                return .queued(localId: id)
```
with:
```swift
            case .terminal:
                throw err
            case .pause:
                // 403 after a successful POST: still surface the error (circuit-breaker already
                // engaged), but persist a recoverable entry so reset()+flush finalizes the
                // existing server record via finalize-first instead of orphaning it (CRLBS-116).
                if configuration.offlineQueueingEnabled {
                    _ = try await submissionQueue.enqueue(
                        submission, attachments: attachments,
                        serverSubmissionId: receipt.submissionId,
                        startingPhase: receipt.hasUploads ? .needsUpload : .needsFinalize)
                    await broadcastPendingCount()
                }
                throw err
            case .retry:
                guard configuration.offlineQueueingEnabled else { throw err }
                // Server already has the record — resume via finalize-first (no re-POST for the
                // no-attachment path; attachments still re-POST for fresh presigned URLs by design).
                let id = try await submissionQueue.enqueue(
                    submission, attachments: attachments,
                    serverSubmissionId: receipt.submissionId,
                    startingPhase: receipt.hasUploads ? .needsUpload : .needsFinalize)
                await broadcastPendingCount()
                return .queued(localId: id)
```
Do not touch the pre-POST `catch`, `advance`, `SubmissionQueue`, `RetryPolicy`, or anything else.

- [ ] **Step 4: Run the new tests, verify they PASS**

Run: `cd /Users/mikesilvers/repos/commentrelay-sdk/commentrelay-sdk-ios && swift test --filter SubmissionQueueFlushTests 2>&1 | tail -20`
Expected: all `SubmissionQueueFlushTests` pass (the 6 pre-existing + 4 new = 10), 0 failures. In particular `testPostSuccessThenForbiddenFinalizeQueuesForFinalizeAndThrows` now: submit throws `.forbidden`, an entry with `serverSubmissionId`+`.needsFinalize` exists, and after `reset()`+`flushQueue()` the queue drains with POST hit exactly once.

- [ ] **Step 5: Full regression suite**

Run: `cd /Users/mikesilvers/repos/commentrelay-sdk/commentrelay-sdk-ios && swift build 2>&1 | tail -2 && swift test 2>&1 | grep -E "Test Suite 'All tests'|Executed [0-9]+ tests, with [0-9]+ failures" | tail -2`
Expected: build succeeds; **0 failures**; total = 198 (194 baseline + 4 new). If any pre-existing test regressed (e.g. a CRLBS-114 post-POST `.retry` test), STOP — the split must preserve `.retry`/`.terminal` behavior exactly; investigate, do not weaken tests.

- [ ] **Step 6: Commit & push**
```bash
cd /Users/mikesilvers/repos/commentrelay-sdk/commentrelay-sdk-ios
git add Sources/CommentRelayCore/Public/CommentRelayClient.swift Tests/CommentRelayCoreTests/SubmissionQueueFlushTests.swift
git commit -m "fix(CRLBS-116): persist recoverable entry on 403 after a successful POST

Post-POST .pause now enqueues with serverSubmissionId + needsFinalize/needsUpload
(respecting offlineQueueingEnabled) then rethrows, so reset()+flush finalizes the
existing record via finalize-first instead of orphaning it. Pre-POST .pause and
.terminal/.retry behavior unchanged.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
git push
```

---

## Self-Review

**Spec coverage:** Decision "throw + enqueue, respecting offlineQueueingEnabled" → Step 3 ✓. `.terminal` unchanged → Step 3 (`case .terminal: throw err`) ✓. Pre-POST unchanged → not modified + `testPrePostForbiddenThrowsAndDoesNotQueue` ✓. Resume via existing finalize-first/pause-resume contract → no changes to advance/queue; `testPostSuccessThenForbiddenFinalizeQueuesForFinalizeAndThrows` exercises `reset()`+`flushQueue()` and asserts exactly-once POST (no duplicate) ✓. Attachment → `.needsUpload` → `testPostSuccessThenForbiddenUploadQueuesAtNeedsUpload` ✓. Queueing disabled unchanged → `testPostSuccessThenForbiddenWithQueueingDisabledThrowsAndDoesNotQueue` ✓. Suite green → Step 5 ✓. Out-of-scope (advance/RetryPolicy/terminal-orphan/attachment re-POST window) untouched ✓.

**Placeholder scan:** None — every step has exact code/commands/expected output.

**Type consistency:** `submissionQueue.enqueue(_:attachments:serverSubmissionId:startingPhase:)`, `QueuedSubmission.Phase.needsFinalize`/`.needsUpload`, `CommentRelayQueuedAttachment(fieldId:fileName:contentType:data:)`, `CommentRelayError.forbidden`, `client.reset()`/`pendingSubmissionCount`/`flushQueue()` all match the existing (post-CRLBS-114) APIs verified in source. The new `.pause` enqueue mirrors the adjacent `.retry` enqueue call exactly (same arguments) — consistent.

No issues outstanding.
