# History Problem Visibility (CRLBS-121) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface queued (retrying) and permanently-failed submissions in the History screen, each expandable to a friendly summary + technical detail, with per-entry Try again / Remove.

**Architecture:** Core retains terminal failures (marks `failedAt` instead of delete), exposes a read API + retry/remove; the pending count counts only retrying entries. UI merges local "problem" entries above the server-fetched history with an inline disclosure and actions; History stays usable offline.

**Tech Stack:** Swift Package Manager, XCTest, ViewInspector (existing UI test dep), `actor SubmissionQueue`, `actor CommentRelayClient`, Codable JSON queue entries, `.strings` localization (en + es-419).

**Spec:** `docs/superpowers/specs/2026-05-19-history-problem-visibility-design.md`

**Base / dependency:** Branch `feature/CRLBS-121-history-problem-visibility`. This plan **must be rebased onto a `develop` that already contains CRLBS-119's SDK companion (PR #17: `Route.queuedSaved`, `CommentRelayView.route(for:hasUserIdentifier:)`, `Route: Equatable`)**. Both touch `CommentRelayView.swift`/Strings. **Task 0 gates execution on that.**

**Refinement vs spec:** The spec said the friendly-message mapper is "lifted into Core." Localization bundles live in `CommentRelayUI`, not Core. So Core exposes a **structured `category` enum** (localization-free); the **UI** maps `category → Strings.error*` localized text. Net behavior is identical; this keeps Core localization-free and avoids duplicating the `.strings` bundle into Core.

**Verification commands:** `swift build`; `swift test`; targeted: `swift test --filter <TestClass>`. Sample app build: `cd Example/CommentRelaySample && xcodebuild -scheme CommentRelaySample -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DD build CODE_SIGNING_ALLOWED=NO`.

---

## File structure

- `Sources/CommentRelayCore/Internal/QueuedSubmission.swift` — add `failedAt`, `lastAttemptAt`, `errorCategory` (Codable; back-compat via Optional synthesis).
- `Sources/CommentRelayCore/Internal/SubmissionQueue.swift` — `markFailed`, `retryingCount`, `loadAll` unchanged; eviction/prune unchanged (failed entries are normal entries subject to caps).
- `Sources/CommentRelayCore/Public/CommentRelaySubmissionProblem.swift` — **new** public model + `Category` enum.
- `Sources/CommentRelayCore/Public/CommentRelayClient.swift` — `.terminal` branch marks failed (not delete); new `submissionProblems()`, `retrySubmission(id:)`, `deleteProblemSubmission(id:)`; pending count uses `retryingCount`; set `lastAttemptAt`/`errorCategory` on attempt failure.
- `Sources/CommentRelayUI/Screens/HistoryListView.swift` — accept `problems`, render a problems section above delivered list.
- `Sources/CommentRelayUI/Components/ProblemRow.swift` — **new** row: chip + disclosure + Try again / Remove.
- `Sources/CommentRelayUI/Shared/Strings.swift` + `Resources/{en,es-419}.lproj/Localizable.strings` — new keys.
- `Sources/CommentRelayUI/Screens/CommentRelayView.swift` — `HistoryLoader` loads problems concurrently; offline-resilient; passes problems down; map `Category → Strings`.
- Tests: `Tests/CommentRelayCoreTests/SubmissionProblemsTests.swift`, `Tests/CommentRelayCoreTests/QueuedSubmissionBackCompatTests.swift`, `Tests/CommentRelayUITests/ScreenTests/ProblemRowTests.swift`, `Tests/CommentRelayUITests/ScreenTests/HistoryProblemsTests.swift`.

---

## Task 0: Confirm base includes PR #17

**Files:** none (gate).

- [ ] **Step 1: Verify CRLBS-119 SDK companion is on the branch base**

Run:
```bash
git log --oneline | grep -i "don't present a queued submission as delivered" || echo "MISSING"
grep -n "case queuedSaved" Sources/CommentRelayUI/Screens/CommentRelayView.swift
grep -n "static func route(for outcome: SubmitOutcome" Sources/CommentRelayUI/Screens/CommentRelayView.swift
```
Expected: the grep prints the commit and both symbols are found.

- [ ] **Step 2: If MISSING, stop**

PR #17 must be merged to `develop` and this branch rebased onto it before continuing. Do not proceed; report back.

---

## Task 1: QueuedSubmission gains failure/diagnostic fields (back-compatible)

**Files:**
- Modify: `Sources/CommentRelayCore/Internal/QueuedSubmission.swift`
- Test: `Tests/CommentRelayCoreTests/QueuedSubmissionBackCompatTests.swift`

- [ ] **Step 1: Write the failing back-compat + new-field test**

Create `Tests/CommentRelayCoreTests/QueuedSubmissionBackCompatTests.swift`:
```swift
import XCTest
@testable import CommentRelayCore

final class QueuedSubmissionBackCompatTests: XCTestCase {
    private func sampleSubmissionJSON() -> String {
        // Minimal valid CommentRelaySubmission shape used elsewhere in tests.
        #"{"form_id":"f","user_identifier":"u","platform":"ios","fields":[]}"#
    }

    func test_decodes_legacy_entry_without_new_keys() throws {
        let json = """
        {"localId":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
         "submission":\(sampleSubmissionJSON()),
         "phase":"needsSubmit","attachments":[],"attemptCount":2,
         "createdAt":768000000.0}
        """
        let e = try JSONDecoder().decode(QueuedSubmission.self, from: Data(json.utf8))
        XCTAssertNil(e.failedAt)
        XCTAssertNil(e.lastAttemptAt)
        XCTAssertNil(e.errorCategory)
        XCTAssertEqual(e.attemptCount, 2)
    }

    func test_roundtrips_new_fields() throws {
        let json = """
        {"localId":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
         "submission":\(sampleSubmissionJSON()),
         "phase":"needsSubmit","attachments":[],"attemptCount":1,
         "createdAt":768000000.0,"failedAt":768000050.0,
         "lastAttemptAt":768000040.0,"errorCategory":"server"}
        """
        let e = try JSONDecoder().decode(QueuedSubmission.self, from: Data(json.utf8))
        let back = try JSONEncoder().encode(e)
        let e2 = try JSONDecoder().decode(QueuedSubmission.self, from: back)
        XCTAssertEqual(e2.errorCategory, "server")
        XCTAssertEqual(e2.failedAt, e.failedAt)
        XCTAssertEqual(e2.lastAttemptAt, e.lastAttemptAt)
    }
}
```
(If the `CommentRelaySubmission` JSON shape differs, copy the exact minimal JSON used in `Tests/CommentRelayCoreTests/ClientSubmitOutcomeTests.swift`.)

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter QueuedSubmissionBackCompatTests`
Expected: FAIL — `errorCategory`/`failedAt`/`lastAttemptAt` are not members.

- [ ] **Step 3: Add the fields**

In `Sources/CommentRelayCore/Internal/QueuedSubmission.swift`, add to `struct QueuedSubmission` after `var lastError: String?`:
```swift
    /// Set when the entry hits a terminal failure (CRLBS-121). Non-nil ⇒ not retried automatically.
    var failedAt: Date?
    /// Timestamp of the most recent failed attempt (there is no other last-attempt record).
    var lastAttemptAt: Date?
    /// Stable token for the last error's category (raw value of CommentRelayError → category),
    /// used by the UI to render a localized friendly message without re-parsing `lastError`.
    var errorCategory: String?
```
Swift synthesizes `decodeIfPresent` for Optional properties, so legacy `entry.json` files (missing these keys) decode with `nil` — no custom `init(from:)` needed.

- [ ] **Step 4: Update the `enqueue` initializer**

In `Sources/CommentRelayCore/Internal/SubmissionQueue.swift`, the `QueuedSubmission(...)` literal in `enqueue(...)` currently ends `... createdAt: Date(), lastError: nil)`. Change to:
```swift
            attemptCount: 0, nextEarliestAttempt: nil, createdAt: Date(),
            lastError: nil, failedAt: nil, lastAttemptAt: nil, errorCategory: nil)
```

- [ ] **Step 5: Run to verify pass**

Run: `swift test --filter QueuedSubmissionBackCompatTests`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add Sources/CommentRelayCore/Internal/QueuedSubmission.swift Sources/CommentRelayCore/Internal/SubmissionQueue.swift Tests/CommentRelayCoreTests/QueuedSubmissionBackCompatTests.swift
git commit -m "feat(CRLBS-121): QueuedSubmission failure/diagnostic fields (back-compatible)"
```

---

## Task 2: SubmissionQueue — markFailed + retryingCount

**Files:**
- Modify: `Sources/CommentRelayCore/Internal/SubmissionQueue.swift`
- Test: `Tests/CommentRelayCoreTests/SubmissionProblemsTests.swift` (create here, extended in Task 4)

- [ ] **Step 1: Write failing test**

Create `Tests/CommentRelayCoreTests/SubmissionProblemsTests.swift`:
```swift
import XCTest
@testable import CommentRelayCore

final class SubmissionProblemsTests: XCTestCase {
    private func makeQueue() -> SubmissionQueue {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("crl-\(UUID().uuidString)")
        return SubmissionQueue(directory: dir, maxEntries: 50, maxAge: 86_400)
    }
    private func sub() throws -> CommentRelaySubmission {
        try JSONDecoder().decode(CommentRelaySubmission.self,
            from: Data(#"{"form_id":"f","user_identifier":"u","platform":"ios","fields":[]}"#.utf8))
    }

    func test_markFailed_sets_failedAt_and_excludes_from_retryingCount() async throws {
        let q = makeQueue()
        let id = try await q.enqueue(try sub(), attachments: [])
        var before = await q.retryingCount
        XCTAssertEqual(before, 1)
        await q.markFailed(localId: id, category: "server", detail: #"server(message: "HTTP 500")"#)
        let all = await q.loadAll()
        XCTAssertEqual(all.first?.failedAt != nil, true)
        XCTAssertEqual(all.first?.errorCategory, "server")
        XCTAssertEqual(all.first?.lastError, #"server(message: "HTTP 500")"#)
        let after = await q.retryingCount
        XCTAssertEqual(after, 0)            // failed ⇒ not "retrying"
        XCTAssertEqual(await q.count, 1)    // still retained
        _ = before
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter SubmissionProblemsTests`
Expected: FAIL — `markFailed`/`retryingCount` undefined.

- [ ] **Step 3: Implement markFailed + retryingCount**

In `Sources/CommentRelayCore/Internal/SubmissionQueue.swift`, add after `func delete(localId:)`:
```swift
    /// Marks an entry terminally failed (CRLBS-121): retained for History, skipped by flush.
    func markFailed(localId: UUID, category: String, detail: String) {
        guard var e = loadAll().first(where: { $0.localId == localId }) else { return }
        let now = Date()
        e.failedAt = now
        e.lastAttemptAt = now
        e.errorCategory = category
        e.lastError = detail
        try? persist(e)
    }
```
Replace `var count: Int { loadAll().count }` with:
```swift
    var count: Int { loadAll().count }
    /// Entries still eligible for automatic retry (not terminally failed).
    var retryingCount: Int { loadAll().filter { $0.failedAt == nil }.count }
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter SubmissionProblemsTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CommentRelayCore/Internal/SubmissionQueue.swift Tests/CommentRelayCoreTests/SubmissionProblemsTests.swift
git commit -m "feat(CRLBS-121): SubmissionQueue.markFailed + retryingCount"
```

---

## Task 3: Public problem model + Category mapping

**Files:**
- Create: `Sources/CommentRelayCore/Public/CommentRelaySubmissionProblem.swift`
- Test: extend `Tests/CommentRelayCoreTests/SubmissionProblemsTests.swift`

- [ ] **Step 1: Write failing test (append to SubmissionProblemsTests)**

Append:
```swift
extension SubmissionProblemsTests {
    func test_category_maps_from_commentRelayError() {
        XCTAssertEqual(CommentRelaySubmissionProblem.Category(.server(message: "x")), .server)
        XCTAssertEqual(CommentRelaySubmissionProblem.Category(.forbidden(message: "x")), .forbidden)
        XCTAssertEqual(CommentRelaySubmissionProblem.Category(.rateLimited(retryAfter: nil)), .rateLimited)
        XCTAssertEqual(CommentRelaySubmissionProblem.Category(.badRequest(message: "x")), .badRequest)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter SubmissionProblemsTests`
Expected: FAIL — type `CommentRelaySubmissionProblem` undefined.

- [ ] **Step 3: Create the model**

Create `Sources/CommentRelayCore/Public/CommentRelaySubmissionProblem.swift`:
```swift
import Foundation

/// A submission that did not deliver: still queued for retry, or terminally failed.
public struct CommentRelaySubmissionProblem: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable { case queuedRetrying, failed }

    /// Localization-free error category; the UI maps this to a friendly message.
    public enum Category: String, Sendable, Equatable {
        case server, transport, rateLimited, forbidden, badRequest
        case paymentRequired, notFound, decoding, conflict
        case uploadFailed, uploadUrlExpired, unknown

        public init(_ error: CommentRelayError) {
            switch error {
            case .server:          self = .server
            case .transport:       self = .transport
            case .rateLimited:     self = .rateLimited
            case .forbidden:       self = .forbidden
            case .badRequest:      self = .badRequest
            case .paymentRequired: self = .paymentRequired
            case .notFound:        self = .notFound
            case .decoding:        self = .decoding
            case .conflict:        self = .conflict
            case .uploadFailed:    self = .uploadFailed
            case .uploadUrlExpired:self = .uploadUrlExpired
            }
        }
        init(token: String?) { self = token.flatMap(Category.init(rawValue:)) ?? .unknown }
    }

    public let id: UUID            // queue localId
    public let formId: String
    public let createdAt: Date
    public let kind: Kind
    public let category: Category
    public let technicalDetail: String   // raw lastError text ("" if none)
    public let attemptCount: Int
    public let lastAttemptAt: Date?
}
```
Note: the `switch` over `CommentRelayError` must be exhaustive. If `Tests`/build reports a missing case, add it — the source of truth is the `CommentRelayError` enum in `Sources/CommentRelayCore`.

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter SubmissionProblemsTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CommentRelayCore/Public/CommentRelaySubmissionProblem.swift Tests/CommentRelayCoreTests/SubmissionProblemsTests.swift
git commit -m "feat(CRLBS-121): public CommentRelaySubmissionProblem + Category mapping"
```

---

## Task 4: Client API — retain on terminal, submissionProblems, retry, delete

**Files:**
- Modify: `Sources/CommentRelayCore/Public/CommentRelayClient.swift`
- Test: extend `Tests/CommentRelayCoreTests/SubmissionProblemsTests.swift`

Context (current code in `CommentRelayClient.swift`):
- `flushQueue`'s `.terminal` branch: `await submissionQueue.delete(localId: entry.localId)` + an error log.
- `flushQueue`'s `.retry` branch already sets `entry.attemptCount += 1`, `entry.lastError = "\(err)"`, `entry.nextEarliestAttempt = …`, `try? await submissionQueue.persist(entry)`.
- `broadcastPendingCount()` and `pendingSubmissionCount` use `submissionQueue.count`.

- [ ] **Step 1: Write failing tests (append)**

Append to `SubmissionProblemsTests`:
```swift
extension SubmissionProblemsTests {
    private func makeClient() -> CommentRelayClient {
        let cfg = CommentRelayConfiguration(apiKey: "k", baseURL: URL(string: "https://example.invalid")!)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("crl-\(UUID())")
        return CommentRelayClient(configuration: cfg, session: .shared,
                                  cacheDirectory: dir, keychainService: "t-\(UUID())")
    }

    func test_submissionProblems_reports_failed_and_queued() async throws {
        let c = makeClient()
        // Two queued entries; fail one terminally via the queue seam.
        let q = await c._testQueue
        let idFailed = try await q.enqueue(try sub(), attachments: [])
        _ = try await q.enqueue(try sub(), attachments: [])
        await q.markFailed(localId: idFailed, category: "badRequest",
                           detail: #"badRequest(message: "Invalid field_id for form")"#)
        let problems = await c.submissionProblems()
        XCTAssertEqual(problems.count, 2)
        let failed = problems.first { $0.id == idFailed }
        XCTAssertEqual(failed?.kind, .failed)
        XCTAssertEqual(failed?.category, .badRequest)
        XCTAssertEqual(problems.filter { $0.kind == .queuedRetrying }.count, 1)
    }

    func test_deleteProblemSubmission_removes_entry() async throws {
        let c = makeClient()
        let q = await c._testQueue
        let id = try await q.enqueue(try sub(), attachments: [])
        await c.deleteProblemSubmission(id: id)
        XCTAssertEqual(await q.count, 0)
        XCTAssertTrue(await c.submissionProblems().isEmpty)
    }

    func test_retrySubmission_unfails_and_makes_eligible() async throws {
        let c = makeClient()
        let q = await c._testQueue
        let id = try await q.enqueue(try sub(), attachments: [])
        await q.markFailed(localId: id, category: "server", detail: "server(message: \"HTTP 500\")")
        await c.retrySubmission(id: id)
        let e = await q.loadAll().first { $0.localId == id }
        XCTAssertNil(e?.failedAt)               // un-failed
        XCTAssertNil(e?.nextEarliestAttempt)    // eligible immediately
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter SubmissionProblemsTests`
Expected: FAIL — `_testQueue`, `submissionProblems`, `deleteProblemSubmission`, `retrySubmission` undefined.

- [ ] **Step 3: Add a test-only queue accessor**

In `CommentRelayClient.swift`, near the other `// Test-only` seam, add:
```swift
    /// Test-only: direct queue access for problem-visibility tests (CRLBS-121).
    var _testQueue: SubmissionQueue { submissionQueue }
```

- [ ] **Step 4: Retain on terminal failure**

In `flushQueue`, replace the `.terminal` case body:
```swift
                case .terminal:
                    await submissionQueue.delete(localId: entry.localId)
                    CommentRelayLoggerHolder.shared.log(level: .error,
                        message: "queued submission dropped (terminal)", error: err)
```
with:
```swift
                case .terminal:
                    await submissionQueue.markFailed(
                        localId: entry.localId,
                        category: CommentRelaySubmissionProblem.Category(err).rawValue,
                        detail: "\(err)")
                    CommentRelayLoggerHolder.shared.log(level: .error,
                        message: "queued submission failed (terminal, retained for History)", error: err)
                    await broadcastPendingCount()
```

- [ ] **Step 5: Record category on retryable failures too**

In `flushQueue`'s `.retry(let retryAfter)` case, after `entry.lastError = "\(err)"` add:
```swift
                    entry.errorCategory = CommentRelaySubmissionProblem.Category(err).rawValue
                    entry.lastAttemptAt = now
```
(`now` is already defined at the top of the flush loop.)

- [ ] **Step 6: Pending count counts only retrying**

Change `pendingSubmissionCount`:
```swift
    public var pendingSubmissionCount: Int {
        get async { await submissionQueue.retryingCount }
    }
```
In `broadcastPendingCount()` change `let n = await submissionQueue.count` to `let n = await submissionQueue.retryingCount`. In `pendingSubmissionCountStream()` change `Task { continuation.yield(await queue.count) }` to `Task { continuation.yield(await queue.retryingCount) }`.

- [ ] **Step 7: Add the three public APIs**

In `CommentRelayClient.swift` (Public API section) add:
```swift
    /// Submissions that did not deliver: still queued for retry, or terminally failed (CRLBS-121).
    public func submissionProblems() async -> [CommentRelaySubmissionProblem] {
        await submissionQueue.loadAll().map { e in
            CommentRelaySubmissionProblem(
                id: e.localId,
                formId: e.submission.formId,
                createdAt: e.createdAt,
                kind: e.failedAt == nil ? .queuedRetrying : .failed,
                category: .init(token: e.errorCategory),
                technicalDetail: e.lastError ?? "",
                attemptCount: e.attemptCount,
                lastAttemptAt: e.lastAttemptAt)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    /// Re-enables a problem entry for immediate delivery. No-op if it no longer exists.
    public func retrySubmission(id: UUID) async {
        guard var e = await submissionQueue.loadAll().first(where: { $0.localId == id }) else { return }
        e.failedAt = nil
        e.nextEarliestAttempt = nil
        try? await submissionQueue.persist(e)
        await broadcastPendingCount()
        await flushQueue()
    }

    /// Removes a problem entry (and its attachment sidecars). No-op if absent.
    public func deleteProblemSubmission(id: UUID) async {
        await submissionQueue.delete(localId: id)
        await broadcastPendingCount()
    }
```
Confirm `CommentRelaySubmission` exposes `formId` (used above). If the property name differs, use the actual accessor — check `Sources/CommentRelayCore/Public/Models/`.

- [ ] **Step 8: Run to verify pass**

Run: `swift test --filter SubmissionProblemsTests`
Expected: PASS (all cases).

- [ ] **Step 9: Run full Core suite (no regressions)**

Run: `swift test --filter CommentRelayCoreTests`
Expected: all pass (existing flush/queue tests still green; if a test asserted terminal entries are *deleted*, update it to assert `failedAt != nil` + retained — that is the intended behavior change for CRLBS-121).

- [ ] **Step 10: Commit**

```bash
git add Sources/CommentRelayCore/Public/CommentRelayClient.swift Tests/CommentRelayCoreTests/SubmissionProblemsTests.swift
git commit -m "feat(CRLBS-121): retain terminal failures; submissionProblems/retry/delete APIs"
```

---

## Task 5: Localized strings

**Files:**
- Modify: `Sources/CommentRelayUI/Shared/Strings.swift`
- Modify: `Sources/CommentRelayUI/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/CommentRelayUI/Resources/es-419.lproj/Localizable.strings`

- [ ] **Step 1: Add Strings accessors**

In `Strings.swift`, after `static var historyNotesHeader…`, add:
```swift
    static var problemQueuedChip: String { string("crl.problem.queued_chip") }
    static var problemFailedChip: String { string("crl.problem.failed_chip") }
    static var problemTryAgain: String { string("crl.problem.try_again") }
    static var problemRemove: String { string("crl.problem.remove") }
    static var problemRemoveConfirmTitle: String { string("crl.problem.remove_confirm_title") }
    static var problemRemoveConfirm: String { string("crl.problem.remove_confirm") }
    static var problemHistoryUnavailable: String { string("crl.problem.history_unavailable") }
    static func problemAttempts(_ n: Int) -> String {
        String(format: string("crl.problem.attempts_format"), locale: .current, n)
    }
    static func friendlyError(_ c: CommentRelaySubmissionProblem.Category) -> String {
        switch c {
        case .rateLimited:     return errorRateLimited
        case .paymentRequired: return errorPaymentRequired
        case .uploadFailed, .uploadUrlExpired: return errorUploadFailed
        default:               return errorGeneric
        }
    }
```
Add `import CommentRelayCore` at the top of `Strings.swift` if not already present (needed for `CommentRelaySubmissionProblem`).

- [ ] **Step 2: Add en strings**

Append to `Sources/CommentRelayUI/Resources/en.lproj/Localizable.strings`:
```
"crl.problem.queued_chip" = "Queued — will retry";
"crl.problem.failed_chip" = "Failed to send";
"crl.problem.try_again" = "Try again";
"crl.problem.remove" = "Remove";
"crl.problem.remove_confirm_title" = "Remove this feedback?";
"crl.problem.remove_confirm" = "Remove";
"crl.problem.history_unavailable" = "Couldn't load past feedback. Showing items on this device.";
"crl.problem.attempts_format" = "Attempt %lld";
```

- [ ] **Step 3: Add es-419 strings**

Append to `Sources/CommentRelayUI/Resources/es-419.lproj/Localizable.strings`:
```
"crl.problem.queued_chip" = "En cola — se reintentará";
"crl.problem.failed_chip" = "No se pudo enviar";
"crl.problem.try_again" = "Reintentar";
"crl.problem.remove" = "Eliminar";
"crl.problem.remove_confirm_title" = "¿Eliminar estos comentarios?";
"crl.problem.remove_confirm" = "Eliminar";
"crl.problem.history_unavailable" = "No se pudo cargar el historial. Mostrando elementos de este dispositivo.";
"crl.problem.attempts_format" = "Intento %lld";
```

- [ ] **Step 4: Build**

Run: `swift build`
Expected: Build complete.

- [ ] **Step 5: Commit**

```bash
git add Sources/CommentRelayUI/Shared/Strings.swift Sources/CommentRelayUI/Resources/en.lproj/Localizable.strings Sources/CommentRelayUI/Resources/es-419.lproj/Localizable.strings
git commit -m "feat(CRLBS-121): localized strings for problem rows (en/es-419)"
```

---

## Task 6: ProblemRow view

**Files:**
- Create: `Sources/CommentRelayUI/Components/ProblemRow.swift`
- Test: `Tests/CommentRelayUITests/ScreenTests/ProblemRowTests.swift`

- [ ] **Step 1: Write failing ViewInspector test**

Create `Tests/CommentRelayUITests/ScreenTests/ProblemRowTests.swift`:
```swift
import XCTest
import SwiftUI
import ViewInspector
import CommentRelayCore
@testable import CommentRelayUI

final class ProblemRowTests: XCTestCase {
    private func problem(_ kind: CommentRelaySubmissionProblem.Kind) -> CommentRelaySubmissionProblem {
        .init(id: UUID(), formId: "f", createdAt: Date(), kind: kind,
              category: .server, technicalDetail: #"server(message: "HTTP 500")"#,
              attemptCount: 2, lastAttemptAt: Date())
    }

    func test_failed_row_shows_failed_chip_and_actions_on_expand() throws {
        var retried = false
        let row = ProblemRow(problem: problem(.failed),
                              onRetry: { retried = true }, onRemove: {})
        // Chip text present
        XCTAssertNoThrow(try row.inspect().find(text: Strings.problemFailedChip))
        // Expanded detail contains technical detail + Try again
        let btn = try row.inspect().find(button: Strings.problemTryAgain)
        try btn.tap()
        XCTAssertTrue(retried)
        XCTAssertNoThrow(try row.inspect().find(text: #"server(message: "HTTP 500")"#))
    }

    func test_queued_row_shows_queued_chip() throws {
        let row = ProblemRow(problem: problem(.queuedRetrying), onRetry: {}, onRemove: {})
        XCTAssertNoThrow(try row.inspect().find(text: Strings.problemQueuedChip))
    }
}
```
(For ViewInspector to reach contents inside a `DisclosureGroup`, the row exposes content unconditionally via an `@State` expansion bound in the body; see Step 3 — keep the detail in the view tree so `find` works.)

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter ProblemRowTests`
Expected: FAIL — `ProblemRow` undefined.

- [ ] **Step 3: Implement ProblemRow**

Create `Sources/CommentRelayUI/Components/ProblemRow.swift`:
```swift
import SwiftUI
import CommentRelayCore

struct ProblemRow: View {
    let problem: CommentRelaySubmissionProblem
    // Not @Sendable: SwiftUI actions run on the main actor.
    let onRetry: () -> Void
    let onRemove: () -> Void

    @State private var expanded = false
    @State private var confirmingRemove = false
    @State private var working = false

    private var isFailed: Bool { problem.kind == .failed }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { expanded.toggle() } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(problem.formId).font(.headline)
                        Text(problem.createdAt, style: .date)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    chip
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(Strings.friendlyError(problem.category))
                        .font(.callout)
                    Text(problem.technicalDetail)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text(Strings.problemAttempts(problem.attemptCount))
                        .font(.caption2).foregroundStyle(.tertiary)
                    HStack(spacing: 12) {
                        Button(Strings.problemTryAgain) {
                            working = true; onRetry()
                        }
                        .buttonStyle(.bordered)
                        .disabled(working)
                        Button(Strings.problemRemove, role: .destructive) {
                            confirmingRemove = true
                        }
                        .buttonStyle(.bordered)
                        if working { ProgressView().controlSize(.small) }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .confirmationDialog(Strings.problemRemoveConfirmTitle,
                            isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button(Strings.problemRemoveConfirm, role: .destructive) { onRemove() }
        }
    }

    private var chip: some View {
        Text(isFailed ? Strings.problemFailedChip : Strings.problemQueuedChip)
            .font(.caption2).bold()
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(isFailed ? Color.red : Color.orange))
            .foregroundStyle(.white)
    }
}
```
Note: the test taps `Try again` while `expanded` starts `false`. Update the test to expand first, OR (simpler, chosen) make `expanded` default `true` in tests by tapping the disclosure button first. Adjust Step 1's `test_failed_row_...`: before finding the button, do `try row.inspect().find(ViewType.Button.self).tap()` to toggle expansion. Keep the queued test asserting only the chip (always visible).

- [ ] **Step 4: Reconcile the test with the view**

Edit `ProblemRowTests.test_failed_row_...` so it expands before asserting inner content:
```swift
        let r = row.inspect()
        try r.find(text: Strings.problemFailedChip)            // chip visible collapsed
        try r.find(ViewType.Button.self).tap()                  // expand
        let btn = try row.inspect().find(button: Strings.problemTryAgain)
        try btn.tap()
        XCTAssertTrue(retried)
```

- [ ] **Step 5: Run to verify pass**

Run: `swift test --filter ProblemRowTests`
Expected: PASS (2 tests). If ViewInspector cannot resolve nested content, add `import ViewInspector` conformance `extension ProblemRow: Inspectable {}` in the test file (matches pattern in existing `ThankYouViewTests.swift` — check that file and mirror its conformance approach exactly).

- [ ] **Step 6: Commit**

```bash
git add Sources/CommentRelayUI/Components/ProblemRow.swift Tests/CommentRelayUITests/ScreenTests/ProblemRowTests.swift
git commit -m "feat(CRLBS-121): ProblemRow with chip, detail disclosure, retry/remove"
```

---

## Task 7: HistoryListView shows problems section

**Files:**
- Modify: `Sources/CommentRelayUI/Screens/HistoryListView.swift`
- Test: `Tests/CommentRelayUITests/ScreenTests/HistoryProblemsTests.swift`

- [ ] **Step 1: Write failing test**

Create `Tests/CommentRelayUITests/ScreenTests/HistoryProblemsTests.swift`:
```swift
import XCTest
import SwiftUI
import ViewInspector
import CommentRelayCore
@testable import CommentRelayUI

final class HistoryProblemsTests: XCTestCase {
    private func emptyHistory() throws -> CommentRelayHistory {
        try JSONDecoder().decode(CommentRelayHistory.self,
            from: Data(#"{"anonymousUser":false,"submissions":[]}"#.utf8))
    }
    private func problem() -> CommentRelaySubmissionProblem {
        .init(id: UUID(), formId: "Bug Report", createdAt: Date(), kind: .failed,
              category: .server, technicalDetail: "server(...)", attemptCount: 1, lastAttemptAt: nil)
    }

    func test_problems_render_even_when_history_empty() throws {
        let v = HistoryListView(history: try emptyHistory(),
                                problems: [problem()],
                                onSelect: { _ in }, onRetry: { _ in }, onRemove: { _ in })
        XCTAssertNoThrow(try v.inspect().find(text: Strings.problemFailedChip))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter HistoryProblemsTests`
Expected: FAIL — `HistoryListView` has no `problems`/`onRetry`/`onRemove`.

- [ ] **Step 3: Extend HistoryListView**

In `Sources/CommentRelayUI/Screens/HistoryListView.swift`, change the struct's stored properties/init and body. Replace the `public struct HistoryListView` declaration through the end of its `body` with:
```swift
public struct HistoryListView: View {
    public let history: CommentRelayHistory
    public let problems: [CommentRelaySubmissionProblem]
    // Not @Sendable: SwiftUI action closures run on the main actor.
    public let onSelect: (CommentRelayHistoryEntry) -> Void
    public let onRetry: (UUID) -> Void
    public let onRemove: (UUID) -> Void

    public init(history: CommentRelayHistory,
                problems: [CommentRelaySubmissionProblem] = [],
                onSelect: @escaping (CommentRelayHistoryEntry) -> Void,
                onRetry: @escaping (UUID) -> Void = { _ in },
                onRemove: @escaping (UUID) -> Void = { _ in }) {
        self.history = history
        self.problems = problems
        self.onSelect = onSelect
        self.onRetry = onRetry
        self.onRemove = onRemove
    }

    public var body: some View {
        Group {
            if history.submissions.isEmpty && problems.isEmpty {
                EmptyStateView(
                    systemImage: "tray",
                    title: Strings.historyTitle,
                    message: history.isAnonymous ? Strings.historyEmptyAnonymous : Strings.historyEmptyIdentified
                )
            } else {
                List {
                    if !problems.isEmpty {
                        Section {
                            ForEach(problems) { p in
                                ProblemRow(problem: p,
                                           onRetry: { onRetry(p.id) },
                                           onRemove: { onRemove(p.id) })
                            }
                        }
                    }
                    ForEach(history.submissions) { entry in
                        HistoryRow(entry: entry) { onSelect(entry) }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(Strings.historyTitle)
    }
}
```
Leave the existing `private struct HistoryRow` below unchanged. The default-valued `init` keeps the existing single call site (`HistoryListView(history:onSelect:)`) source-compatible until Task 8 wires the new closures.

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter HistoryProblemsTests`
Expected: PASS.

- [ ] **Step 5: Run UI suite (no regression)**

Run: `swift test --filter CommentRelayUITests`
Expected: all pass (existing `HistoryListView` callers compile via defaulted init).

- [ ] **Step 6: Commit**

```bash
git add Sources/CommentRelayUI/Screens/HistoryListView.swift Tests/CommentRelayUITests/ScreenTests/HistoryProblemsTests.swift
git commit -m "feat(CRLBS-121): HistoryListView renders problems section"
```

---

## Task 8: Wire HistoryLoader (concurrent load + offline resilience)

**Files:**
- Modify: `Sources/CommentRelayUI/Screens/CommentRelayView.swift` (private `HistoryLoader`)
- Test: extend `Tests/CommentRelayUITests/ScreenTests/HistoryProblemsTests.swift`

Current `HistoryLoader` (in `CommentRelayView.swift`): on `fetchHistory()` throw it sets `errorMessage` and renders `ErrorBanner`, hiding everything.

- [ ] **Step 1: Write failing test (append)**

Append to `HistoryProblemsTests`:
```swift
extension HistoryProblemsTests {
    func test_problems_shown_when_server_history_fails() throws {
        // Build the loader view directly with an injected failing fetch + problems.
        let view = HistoryProblemsLoaderHarness(
            problems: [problem()],
            serverFailed: true)
        XCTAssertNoThrow(try view.inspect().find(text: Strings.problemFailedChip))
        XCTAssertNoThrow(try view.inspect().find(text: Strings.problemHistoryUnavailable))
    }
}

/// Mirrors HistoryLoader's presentation logic with injected state so the
/// offline-resilience branch is unit-testable without a live client.
struct HistoryProblemsLoaderHarness: View {
    let problems: [CommentRelaySubmissionProblem]
    let serverFailed: Bool
    var body: some View {
        VStack {
            if serverFailed { Text(Strings.problemHistoryUnavailable).font(.footnote) }
            HistoryListView(
                history: try! JSONDecoder().decode(CommentRelayHistory.self,
                    from: Data(#"{"anonymousUser":false,"submissions":[]}"#.utf8)),
                problems: problems,
                onSelect: { _ in }, onRetry: { _ in }, onRemove: { _ in })
        }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter HistoryProblemsTests`
Expected: FAIL — `Strings.problemHistoryUnavailable` text not found (harness compiles; assertion drives the loader change for parity).

Actually the harness is self-contained and will PASS once Strings exist (Task 5 done). Its purpose is to lock the *presentation contract* the loader must follow. Treat a PASS here as the contract baseline; proceed to make the real loader match it.

- [ ] **Step 3: Rewrite HistoryLoader**

In `CommentRelayView.swift`, replace the `private struct HistoryLoader` body with:
```swift
private struct HistoryLoader: View {
    let client: CommentRelayClient
    @State private var history: CommentRelayHistory? = nil
    @State private var problems: [CommentRelaySubmissionProblem] = []
    @State private var selectedId: UUID? = nil
    @State private var serverFailed = false

    var body: some View {
        Group {
            if let history {
                VStack(spacing: 0) {
                    if serverFailed {
                        Text(Strings.problemHistoryUnavailable)
                            .font(.footnote).foregroundStyle(.secondary)
                            .padding(.horizontal)
                    }
                    HistoryListView(
                        history: history,
                        problems: problems,
                        onSelect: { entry in
                            let eid = entry.id
                            Task { @MainActor in selectedId = eid }
                        },
                        onRetry: { id in Task { await client.retrySubmission(id: id); await refreshProblems() } },
                        onRemove: { id in Task { await client.deleteProblemSubmission(id: id); await refreshProblems() } }
                    )
                    .navigationDestination(item: $selectedId) { entryId in
                        if let entry = history.submissions.first(where: { $0.id == entryId }) {
                            HistoryDetailView(entry: entry)
                        }
                    }
                }
            } else {
                LoadingView(label: nil)
            }
        }
        .task { await load() }
    }

    private func load() async {
        problems = await client.submissionProblems()
        do {
            history = try await client.fetchHistory()
        } catch {
            CommentRelayLoggerHolder.shared.log(level: .error, message: "fetchHistory failed", error: error)
            serverFailed = true
            // Show problems with an empty delivered list rather than hiding everything.
            history = (try? JSONDecoder().decode(
                CommentRelayHistory.self,
                from: Data(#"{"anonymousUser":false,"submissions":[]}"#.utf8)))
                ?? history
        }
    }

    private func refreshProblems() async { problems = await client.submissionProblems() }
}
```
Remove the now-unused `errorMessage` state and the `ErrorBanner` branch. If `ErrorBanner` becomes unreferenced project-wide, leave the type (it is public API); do not delete it.

- [ ] **Step 4: Build**

Run: `swift build`
Expected: Build complete. Fix any reference to removed `errorMessage`.

- [ ] **Step 5: Run full suite**

Run: `swift test`
Expected: all pass (Core + UI), including new tests.

- [ ] **Step 6: Commit**

```bash
git add Sources/CommentRelayUI/Screens/CommentRelayView.swift Tests/CommentRelayUITests/ScreenTests/HistoryProblemsTests.swift
git commit -m "feat(CRLBS-121): HistoryLoader loads problems + offline-resilient"
```

---

## Task 9: Full verification + sample app + PR

**Files:** none (verification).

- [ ] **Step 1: Full test suite**

Run: `swift test 2>&1 | tail -5`
Expected: `Executed N tests, with 0 failures` (N = prior count + new tests).

- [ ] **Step 2: Build the macOS sample**

Run:
```bash
cd Example/CommentRelaySample && xcodebuild -scheme CommentRelaySample -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DD build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3 ; rm -rf build ; cd -
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Push + open PR**

```bash
git push -u origin feature/CRLBS-121-history-problem-visibility
bb pr create -s feature/CRLBS-121-history-problem-visibility -d develop \
  -t "feat(CRLBS-121): surface queued & failed submissions in History" \
  -b "Implements docs/superpowers/specs/2026-05-19-history-problem-visibility-design.md. Retains terminal failures; submissionProblems/retry/delete APIs; problems section in History with friendly+technical detail and Try again/Remove; offline-resilient HistoryLoader. Depends on PR #17 (CRLBS-119). JIRA: https://commentrelay.atlassian.net/browse/CRLBS-121"
```
Expected: PR created.

- [ ] **Step 4: Move CRLBS-121 to Pending Release**

Per repo workflow (merged to `develop` ⇒ Pending Release). Report the PR URL and ask the user to review/merge; transition the ticket after merge.

---

## Self-Review

**Spec coverage:** retain failures (T2,T4) ✓; queued+failed surfaced (T4,T7) ✓; friendly+technical (T3,T5,T6) ✓; Try again/Remove (T4,T6,T8) ✓; pending count excludes failed (T4) ✓; caps prune failures (unchanged eviction/prune already operate on all entries — covered by existing queue cap tests; no new behavior needed) ✓; offline resilience (T8) ✓; tests Core+UI (T1–T8) ✓; strings en/es-419 (T5) ✓; sequencing/dep on PR #17 (T0) ✓.

**Placeholder scan:** no TBD/TODO; every code step has full code; commands have expected output.

**Type consistency:** `CommentRelaySubmissionProblem` fields/`Kind`/`Category` defined in T3 and used identically in T4/T6/T7/T8; `markFailed(localId:category:detail:)` defined T2, called T4; `retryingCount` defined T2, used T4; `submissionProblems()/retrySubmission(id:)/deleteProblemSubmission(id:)` signatures consistent T4↔T8; `HistoryListView(history:problems:onSelect:onRetry:onRemove:)` consistent T7↔T8; `ProblemRow(problem:onRetry:onRemove:)` consistent T6↔T7.

**Known verify-at-execution points (call out, not placeholders):** exact minimal `CommentRelaySubmission` JSON (copy from `ClientSubmitOutcomeTests.swift`); `CommentRelaySubmission.formId` accessor name; `CommentRelayError` case list for the exhaustive `Category` switch; ViewInspector `Inspectable` conformance pattern (mirror `ThankYouViewTests.swift`); whether any existing Core test asserts terminal-delete (update it to assert retained+failed). Each step says how to confirm.
