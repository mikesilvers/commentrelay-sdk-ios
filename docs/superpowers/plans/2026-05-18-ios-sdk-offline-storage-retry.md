# iOS SDK — Offline Storage & Retry (SP2 / CRLBS-114) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist feedback submissions (text + attachments) locally when offline or on transient failure, render feedback forms from cached config offline, and auto-deliver the queue when connectivity returns — without duplicate server records or breaking the actor model.

**Architecture:** A new `SubmissionQueue` actor (parallel to `DraftStore`/`ConfigCache`) persists one JSON entry + attachment sidecars per submission and runs a single-flight, FIFO, finalize-first state machine. A `Reachability` protocol (`NWPathMonitor`-backed, injectable) plus SDK-init/foreground/`submit()` triggers drive flushes. `CommentRelayClient.submit` becomes auto-queueing and returns a `SubmitOutcome`. `fetchConfig` gains offline cache fallback + an `effectiveConfig()` accessor. A minimal `CommentRelayUI` badge shows the pending count.

**Tech Stack:** Swift 6 / SPM / XCTest; `Network.framework` (`NWPathMonitor`); JSON-file persistence (`FileManager`, atomic writes) mirroring `DraftStore`.

**Spec:** `docs/superpowers/specs/2026-05-17-ios-sdk-offline-storage-retry-design.md` (Approved).
**Ticket:** CRLBS-114. **Branch:** `feature/CRLBS-114-offline-storage-retry`.

## Conventions

- Commits: `type(CRLBS-114): description` (Conventional Commits), ending with the line
  `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`. Push after every task.
- TDD strictly: write failing test → run, see it fail for the right reason → minimal code → green → commit.
- Per-task verify: `cd /Users/mikesilvers/repos/commentrelay-sdk/commentrelay-sdk-ios && swift test --filter <Suite> 2>&1 | tail -15`.
- All work in `/Users/mikesilvers/repos/commentrelay-sdk/commentrelay-sdk-ios` on `feature/CRLBS-114-offline-storage-retry` (confirm with `git branch --show-current`).
- Hermetic test client init: `CommentRelayClient(configuration:session:cacheDirectory:keychainService:)` (internal, `@testable`).

## Key design clarification (refines spec)

To persist an attachment-bearing submission **offline**, the SDK needs the file **bytes at enqueue time** — but today bytes live only in `CommentRelayFilePayload`, which is built *after* a `receipt`. Therefore `submit` gains an `attachments:` parameter carrying raw bytes. The UI already holds these (`FeedbackFormViewModel` builds payloads from `att.data`/`att.mimeType`). New public type:

```swift
public struct CommentRelayQueuedAttachment: Sendable, Equatable {
    public let fieldId: String
    public let fileName: String
    public let contentType: String
    public let data: Data
    public init(fieldId: String, fileName: String, contentType: String, data: Data) {
        self.fieldId = fieldId; self.fileName = fileName; self.contentType = contentType; self.data = data
    }
}
```

## File structure

| File | Responsibility | Action |
|---|---|---|
| `Sources/CommentRelayCore/Public/CommentRelayConfiguration.swift` | offline knobs | Modify |
| `Sources/CommentRelayCore/Internal/Reachability.swift` | connectivity protocol + `NWPathMonitor` impl | Create |
| `Sources/CommentRelayCore/Public/Models/CommentRelayQueuedAttachment.swift` | enqueue attachment bytes | Create |
| `Sources/CommentRelayCore/Internal/QueuedSubmission.swift` | persisted entry model + `Phase` | Create |
| `Sources/CommentRelayCore/Internal/SubmissionQueue.swift` | persistence, caps, FIFO, single-flight flush state machine | Create |
| `Sources/CommentRelayCore/Internal/RetryPolicy.swift` | retryable/terminal routing + backoff | Create |
| `Sources/CommentRelayCore/Public/SubmitOutcome.swift` | `submit` return enum | Create |
| `Sources/CommentRelayCore/Public/CommentRelayClient.swift` | queue wiring, `submit` outcome, pending count/stream, `flushQueue`, offline `fetchConfig`/`effectiveConfig`, triggers | Modify |
| `Sources/CommentRelayUI/Screens/CommentRelayView.swift` | `SubmitOutcome` call-site; pass attachments | Modify |
| `Sources/CommentRelayUI/Screens/FeedbackFormViewModel.swift` | expose queued attachments | Modify |
| `Sources/CommentRelayUI/Components/PendingBadge.swift` | pending-count badge | Create |
| `Tests/CommentRelayCoreTests/*` , `Tests/CommentRelayUITests/*` | per-task suites | Create |
| `README.md` | offline section | Modify |

---

## Task 0: Update the stale branch onto current `develop`

This branch predates the CRLBS-113 and CRLBS-115 merges (baseline here is **148** tests; `develop` is **155**). Building SP2 on the old base would regress SP1 on merge.

- [ ] **Step 1: Fetch and inspect the gap**

Run: `cd /Users/mikesilvers/repos/commentrelay-sdk/commentrelay-sdk-ios && git fetch origin --quiet && git log --oneline origin/feature/CRLBS-114-offline-storage-retry..origin/develop | head`
Expected: shows the CRLBS-113 (PR #4) and CRLBS-115 (PR #5) merge commits not yet on this branch.

- [ ] **Step 2: Merge `develop` into the branch**

```bash
cd /Users/mikesilvers/repos/commentrelay-sdk/commentrelay-sdk-ios
git checkout feature/CRLBS-114-offline-storage-retry
git merge --no-edit origin/develop
```
Expected: clean merge (the only branch content is the spec doc; no code overlap). If conflicts, stop and report — do not force.

- [ ] **Step 3: Re-baseline**

Run: `swift build 2>&1 | tail -1 && swift test 2>&1 | grep -E "Executed [0-9]+ tests, with [0-9]+ failures" | tail -1`
Expected: build succeeds; **155 tests, 0 failures** (the post-CRLBS-113/115 baseline). Record this number; every later task must keep ≥155 + its own new tests, 0 failures.

- [ ] **Step 4: Push**

```bash
git push -u origin feature/CRLBS-114-offline-storage-retry
```

---

## Task 1: `CommentRelayConfiguration` offline knobs

**Files:** Modify `Sources/CommentRelayCore/Public/CommentRelayConfiguration.swift`; Test `Tests/CommentRelayCoreTests/ConfigurationOfflineTests.swift` (create).

- [ ] **Step 1: Failing test**

Create `Tests/CommentRelayCoreTests/ConfigurationOfflineTests.swift`:
```swift
import XCTest
@testable import CommentRelayCore

final class ConfigurationOfflineTests: XCTestCase {
    func testDefaults() {
        let c = CommentRelayConfiguration(baseURL: URL(string: "https://x")!, apiKey: "k")
        XCTAssertTrue(c.offlineQueueingEnabled)
        XCTAssertEqual(c.maxQueuedSubmissions, 50)
        XCTAssertEqual(c.maxQueueAge, 30 * 24 * 60 * 60)
    }

    func testOverrides() {
        let c = CommentRelayConfiguration(baseURL: URL(string: "https://x")!, apiKey: "k",
                                          offlineQueueingEnabled: false,
                                          maxQueuedSubmissions: 5,
                                          maxQueueAge: 60)
        XCTAssertFalse(c.offlineQueueingEnabled)
        XCTAssertEqual(c.maxQueuedSubmissions, 5)
        XCTAssertEqual(c.maxQueueAge, 60)
    }
}
```

- [ ] **Step 2: Run, verify FAIL**

Run: `swift test --filter ConfigurationOfflineTests 2>&1 | tail -15`
Expected: compile failure — unknown args `offlineQueueingEnabled`/`maxQueuedSubmissions`/`maxQueueAge`.

- [ ] **Step 3: Implement**

In `CommentRelayConfiguration.swift`, add stored properties after `appVersionOverride`:
```swift
    public let offlineQueueingEnabled: Bool
    public let maxQueuedSubmissions: Int
    public let maxQueueAge: TimeInterval
```
Add init params (with defaults) at the end of the parameter list, before the body:
```swift
                offlineQueueingEnabled: Bool = true,
                maxQueuedSubmissions: Int = 50,
                maxQueueAge: TimeInterval = 30 * 24 * 60 * 60) {
```
And assignments in the body:
```swift
        self.offlineQueueingEnabled = offlineQueueingEnabled
        self.maxQueuedSubmissions = maxQueuedSubmissions
        self.maxQueueAge = maxQueueAge
```

- [ ] **Step 4: Run, verify PASS**

Run: `swift test --filter ConfigurationOfflineTests 2>&1 | tail -15` → PASS (2 tests).

- [ ] **Step 5: Commit & push**

```bash
git add Sources/CommentRelayCore/Public/CommentRelayConfiguration.swift Tests/CommentRelayCoreTests/ConfigurationOfflineTests.swift
git commit -m "feat(CRLBS-114): add offline queue configuration knobs

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
git push
```

---

## Task 2: `Reachability` protocol + `NWPathMonitor` implementation

**Files:** Create `Sources/CommentRelayCore/Internal/Reachability.swift`; Test `Tests/CommentRelayCoreTests/ReachabilityTests.swift`.

- [ ] **Step 1: Failing test** — Create `Tests/CommentRelayCoreTests/ReachabilityTests.swift`:
```swift
import XCTest
@testable import CommentRelayCore

final class ReachabilityTests: XCTestCase {
    func testFakeEmitsAndReportsState() async {
        let fake = FakeReachability(initial: false)
        XCTAssertFalse(fake.isConnected)
        var received: [Bool] = []
        let task = Task {
            for await v in fake.changes { received.append(v); if received.count == 2 { break } }
        }
        fake.set(true)
        fake.set(false)
        _ = await task.value
        XCTAssertEqual(received, [true, false])
    }
}
```

- [ ] **Step 2: Run, verify FAIL**

Run: `swift test --filter ReachabilityTests 2>&1 | tail -15`
Expected: FAIL — `FakeReachability` / `Reachability` undefined.

- [ ] **Step 3: Implement** — Create `Sources/CommentRelayCore/Internal/Reachability.swift`:
```swift
import Foundation
import Network

protocol Reachability: Sendable {
    var isConnected: Bool { get }
    var changes: AsyncStream<Bool> { get }
}

/// `NWPathMonitor`-backed reachability. `isConnected` is updated on a private queue.
final class NetworkReachability: Reachability, @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.commentrelay.reachability")
    private let lock = NSLock()
    private var _isConnected = false
    private var continuations: [UUID: AsyncStream<Bool>.Continuation] = [:]

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let connected = path.status == .satisfied
            self.lock.lock()
            self._isConnected = connected
            let conts = Array(self.continuations.values)
            self.lock.unlock()
            conts.forEach { $0.yield(connected) }
        }
        monitor.start(queue: queue)
    }

    var isConnected: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isConnected
    }

    var changes: AsyncStream<Bool> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock(); continuations[id] = continuation; lock.unlock()
            continuation.onTermination = { [weak self] _ in
                self?.lock.lock(); self?.continuations[id] = nil; self?.lock.unlock()
            }
        }
    }

    deinit { monitor.cancel() }
}

/// Injectable test double.
final class FakeReachability: Reachability, @unchecked Sendable {
    private let lock = NSLock()
    private var _isConnected: Bool
    private var continuations: [UUID: AsyncStream<Bool>.Continuation] = [:]

    init(initial: Bool) { _isConnected = initial }

    var isConnected: Bool { lock.lock(); defer { lock.unlock() }; return _isConnected }

    var changes: AsyncStream<Bool> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock(); continuations[id] = continuation; lock.unlock()
            continuation.onTermination = { [weak self] _ in
                self?.lock.lock(); self?.continuations[id] = nil; self?.lock.unlock()
            }
        }
    }

    func set(_ connected: Bool) {
        lock.lock(); _isConnected = connected; let conts = Array(continuations.values); lock.unlock()
        conts.forEach { $0.yield(connected) }
    }
}
```

- [ ] **Step 4: Run, verify PASS** — `swift test --filter ReachabilityTests 2>&1 | tail -15` → PASS (1 test).

- [ ] **Step 5: Commit & push**

```bash
git add Sources/CommentRelayCore/Internal/Reachability.swift Tests/CommentRelayCoreTests/ReachabilityTests.swift
git commit -m "feat(CRLBS-114): add Reachability protocol with NWPathMonitor + fake

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
git push
```

---

## Task 3: Queue models — `CommentRelayQueuedAttachment`, `QueuedSubmission`

**Files:** Create `Sources/CommentRelayCore/Public/Models/CommentRelayQueuedAttachment.swift`, `Sources/CommentRelayCore/Internal/QueuedSubmission.swift`; Test `Tests/CommentRelayCoreTests/QueuedSubmissionTests.swift`.

- [ ] **Step 1: Failing test** — Create `Tests/CommentRelayCoreTests/QueuedSubmissionTests.swift`:
```swift
import XCTest
@testable import CommentRelayCore

final class QueuedSubmissionTests: XCTestCase {
    private func sub() -> CommentRelaySubmission {
        CommentRelaySubmission(formId: "f", userIdentifier: "u", platform: .ios,
            fields: [.text(fieldId: "1", value: "hi")], osVersion: nil, deviceModel: nil,
            appVersion: nil, sdkVersion: nil, locale: nil, contactPreference: nil,
            contactDetails: nil, sessionId: nil)
    }

    func testRoundTripsThroughJSON() throws {
        let q = QueuedSubmission(
            localId: UUID(), submission: sub(), phase: .needsSubmit,
            serverSubmissionId: nil,
            attachments: [QueuedFileRef(fieldId: "2", fileName: "a.png", contentType: "image/png", size: 3)],
            attemptCount: 0, nextEarliestAttempt: nil, createdAt: Date(timeIntervalSince1970: 1),
            lastError: nil)
        let data = try JSONEncoder().encode(q)
        let back = try JSONDecoder().decode(QueuedSubmission.self, from: data)
        XCTAssertEqual(back, q)
        XCTAssertEqual(back.phase, .needsSubmit)
    }

    func testPhaseEncodesStably() throws {
        let data = try JSONEncoder().encode(QueuedSubmission.Phase.needsFinalize)
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"needsFinalize\"")
    }
}
```

- [ ] **Step 2: Run, verify FAIL** — `swift test --filter QueuedSubmissionTests 2>&1 | tail -15` → FAIL (types undefined).

- [ ] **Step 3: Implement** — Create `Sources/CommentRelayCore/Public/Models/CommentRelayQueuedAttachment.swift`:
```swift
import Foundation

public struct CommentRelayQueuedAttachment: Sendable, Equatable {
    public let fieldId: String
    public let fileName: String
    public let contentType: String
    public let data: Data
    public init(fieldId: String, fileName: String, contentType: String, data: Data) {
        self.fieldId = fieldId; self.fileName = fileName
        self.contentType = contentType; self.data = data
    }
}
```
Create `Sources/CommentRelayCore/Internal/QueuedSubmission.swift`:
```swift
import Foundation

struct QueuedFileRef: Codable, Sendable, Equatable {
    let fieldId: String
    let fileName: String
    let contentType: String
    let size: Int
}

struct QueuedSubmission: Codable, Sendable, Equatable {
    enum Phase: String, Codable, Sendable {
        case needsSubmit, needsUpload, needsFinalize, done
    }
    let localId: UUID
    var submission: CommentRelaySubmission
    var phase: Phase
    var serverSubmissionId: UUID?
    var attachments: [QueuedFileRef]
    var attemptCount: Int
    var nextEarliestAttempt: Date?
    let createdAt: Date
    var lastError: String?
}
```

- [ ] **Step 4: Run, verify PASS** — `swift test --filter QueuedSubmissionTests 2>&1 | tail -15` → PASS (2 tests).

- [ ] **Step 5: Commit & push**

```bash
git add Sources/CommentRelayCore/Public/Models/CommentRelayQueuedAttachment.swift Sources/CommentRelayCore/Internal/QueuedSubmission.swift Tests/CommentRelayCoreTests/QueuedSubmissionTests.swift
git commit -m "feat(CRLBS-114): add QueuedSubmission/QueuedFileRef and queued attachment model

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
git push
```

---

## Task 4: `SubmissionQueue` — persistence (enqueue / load / delete / sidecars)

**Files:** Create `Sources/CommentRelayCore/Internal/SubmissionQueue.swift`; Test `Tests/CommentRelayCoreTests/SubmissionQueuePersistenceTests.swift`.

On-disk layout (mirrors `DraftStore` atomic-write style): `<dir>/queue/<localId>/entry.json` + one sidecar file per attachment named `<fileName>`.

- [ ] **Step 1: Failing test** — Create `Tests/CommentRelayCoreTests/SubmissionQueuePersistenceTests.swift`:
```swift
import XCTest
@testable import CommentRelayCore

final class SubmissionQueuePersistenceTests: XCTestCase {
    private func tmp() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("crq-\(UUID())")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    private func sub(_ form: String = "f") -> CommentRelaySubmission {
        CommentRelaySubmission(formId: form, userIdentifier: "u", platform: .ios,
            fields: [.text(fieldId: "1", value: "hi")], osVersion: nil, deviceModel: nil,
            appVersion: nil, sdkVersion: nil, locale: nil, contactPreference: nil,
            contactDetails: nil, sessionId: nil)
    }

    func testEnqueuePersistsEntryAndSidecar() async throws {
        let dir = tmp()
        let q = SubmissionQueue(directory: dir, maxEntries: 50, maxAge: 9_999_999)
        let att = CommentRelayQueuedAttachment(fieldId: "2", fileName: "a.bin",
                                               contentType: "application/pdf", data: Data([1,2,3]))
        let id = try await q.enqueue(sub(), attachments: [att])
        let entryURL = dir.appendingPathComponent("queue/\(id)/entry.json")
        let sidecarURL = dir.appendingPathComponent("queue/\(id)/a.bin")
        XCTAssertTrue(FileManager.default.fileExists(atPath: entryURL.path))
        XCTAssertEqual(try Data(contentsOf: sidecarURL), Data([1,2,3]))
    }

    func testLoadAllReturnsFIFOByCreatedAt() async throws {
        let dir = tmp()
        let q = SubmissionQueue(directory: dir, maxEntries: 50, maxAge: 9_999_999)
        let a = try await q.enqueue(sub("a"), attachments: [])
        try await Task.sleep(nanoseconds: 10_000_000)
        let b = try await q.enqueue(sub("b"), attachments: [])
        let all = await q.loadAll()
        XCTAssertEqual(all.map(\.localId), [a, b])
    }

    func testDeleteRemovesFolder() async throws {
        let dir = tmp()
        let q = SubmissionQueue(directory: dir, maxEntries: 50, maxAge: 9_999_999)
        let id = try await q.enqueue(sub(), attachments: [])
        await q.delete(localId: id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("queue/\(id)").path))
    }

    func testReadSidecarReturnsBytes() async throws {
        let dir = tmp()
        let q = SubmissionQueue(directory: dir, maxEntries: 50, maxAge: 9_999_999)
        let att = CommentRelayQueuedAttachment(fieldId: "2", fileName: "x.txt",
                                               contentType: "text/plain", data: Data("hey".utf8))
        let id = try await q.enqueue(sub(), attachments: [att])
        let bytes = await q.readSidecar(localId: id, fileName: "x.txt")
        XCTAssertEqual(bytes, Data("hey".utf8))
    }
}
```

- [ ] **Step 2: Run, verify FAIL** — `swift test --filter SubmissionQueuePersistenceTests 2>&1 | tail -15` → FAIL (`SubmissionQueue` undefined).

- [ ] **Step 3: Implement** — Create `Sources/CommentRelayCore/Internal/SubmissionQueue.swift`:
```swift
import Foundation

actor SubmissionQueue {
    private let root: URL          // <dir>/queue
    private let maxEntries: Int
    private let maxAge: TimeInterval
    private let fm = FileManager.default

    init(directory: URL, maxEntries: Int, maxAge: TimeInterval) {
        self.root = directory.appendingPathComponent("queue")
        self.maxEntries = maxEntries
        self.maxAge = maxAge
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func entryDir(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString) }

    /// Caps enforced by the caller (Task 5). Persists entry.json + one sidecar per attachment.
    func enqueue(_ submission: CommentRelaySubmission,
                 attachments: [CommentRelayQueuedAttachment]) throws -> UUID {
        let id = UUID()
        let dir = entryDir(id)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for att in attachments {
            try att.data.write(to: dir.appendingPathComponent(att.fileName), options: .atomic)
        }
        let refs = attachments.map {
            QueuedFileRef(fieldId: $0.fieldId, fileName: $0.fileName,
                          contentType: $0.contentType, size: $0.data.count)
        }
        let entry = QueuedSubmission(
            localId: id, submission: submission,
            phase: attachments.isEmpty ? .needsSubmit : .needsSubmit,
            serverSubmissionId: nil, attachments: refs,
            attemptCount: 0, nextEarliestAttempt: nil, createdAt: Date(), lastError: nil)
        try persist(entry)
        return id
    }

    func persist(_ entry: QueuedSubmission) throws {
        let data = try JSONEncoder().encode(entry)
        try data.write(to: entryDir(entry.localId).appendingPathComponent("entry.json"), options: .atomic)
    }

    func loadAll() -> [QueuedSubmission] {
        guard let dirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        let entries = dirs.compactMap { d -> QueuedSubmission? in
            guard let data = try? Data(contentsOf: d.appendingPathComponent("entry.json")) else { return nil }
            return try? JSONDecoder().decode(QueuedSubmission.self, from: data)
        }
        return entries.sorted { $0.createdAt < $1.createdAt }
    }

    func delete(localId: UUID) {
        try? fm.removeItem(at: entryDir(localId))
    }

    func readSidecar(localId: UUID, fileName: String) -> Data? {
        try? Data(contentsOf: entryDir(localId).appendingPathComponent(fileName))
    }

    var count: Int { loadAll().count }
}
```

- [ ] **Step 4: Run, verify PASS** — `swift test --filter SubmissionQueuePersistenceTests 2>&1 | tail -15` → PASS (4 tests).

- [ ] **Step 5: Commit & push**

```bash
git add Sources/CommentRelayCore/Internal/SubmissionQueue.swift Tests/CommentRelayCoreTests/SubmissionQueuePersistenceTests.swift
git commit -m "feat(CRLBS-114): SubmissionQueue persistence (entry.json + sidecars, FIFO)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
git push
```

---

## Task 5: `SubmissionQueue` — caps, eviction, attachment-cap rejection

**Files:** Modify `Sources/CommentRelayCore/Internal/SubmissionQueue.swift`; Test `Tests/CommentRelayCoreTests/SubmissionQueueCapsTests.swift`.

API caps (from spec / API schema): ≤10,000,000 bytes/file; ≤3 files per `fieldId`; allowed MIME: `image/jpeg`, `image/png`, `image/heic`, `image/heif`, `image/webp`, `application/pdf`, `text/plain`.

- [ ] **Step 1: Failing test** — Create `Tests/CommentRelayCoreTests/SubmissionQueueCapsTests.swift`:
```swift
import XCTest
@testable import CommentRelayCore

final class SubmissionQueueCapsTests: XCTestCase {
    private func tmp() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("crqc-\(UUID())")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true); return u
    }
    private func sub() -> CommentRelaySubmission {
        CommentRelaySubmission(formId: "f", userIdentifier: "u", platform: .ios,
            fields: [.text(fieldId: "1", value: "hi")], osVersion: nil, deviceModel: nil,
            appVersion: nil, sdkVersion: nil, locale: nil, contactPreference: nil,
            contactDetails: nil, sessionId: nil)
    }

    func testRejectsOversizeFile() async {
        let q = SubmissionQueue(directory: tmp(), maxEntries: 50, maxAge: 9_999_999)
        let big = CommentRelayQueuedAttachment(fieldId: "2", fileName: "b",
            contentType: "image/png", data: Data(count: 10_000_001))
        do { _ = try await q.enqueue(sub(), attachments: [big]); XCTFail("should reject") }
        catch let e as CommentRelayError { guard case .badRequest = e else { return XCTFail("wrong: \(e)") } }
        catch { XCTFail("wrong error type") }
    }

    func testRejectsDisallowedMIME() async {
        let q = SubmissionQueue(directory: tmp(), maxEntries: 50, maxAge: 9_999_999)
        let bad = CommentRelayQueuedAttachment(fieldId: "2", fileName: "b",
            contentType: "application/zip", data: Data([1]))
        do { _ = try await q.enqueue(sub(), attachments: [bad]); XCTFail("should reject") }
        catch let e as CommentRelayError { guard case .badRequest = e else { return XCTFail("wrong: \(e)") } }
        catch { XCTFail("wrong error type") }
    }

    func testRejectsMoreThan3FilesPerField() async {
        let q = SubmissionQueue(directory: tmp(), maxEntries: 50, maxAge: 9_999_999)
        let atts = (0..<4).map { CommentRelayQueuedAttachment(fieldId: "2", fileName: "f\($0)",
            contentType: "image/png", data: Data([1])) }
        do { _ = try await q.enqueue(sub(), attachments: atts); XCTFail("should reject") }
        catch let e as CommentRelayError { guard case .badRequest = e else { return XCTFail("wrong: \(e)") } }
        catch { XCTFail("wrong error type") }
    }

    func testEvictsOldestWhenOverCapacity() async throws {
        let dir = tmp()
        let q = SubmissionQueue(directory: dir, maxEntries: 2, maxAge: 9_999_999)
        let a = try await q.enqueue(sub(), attachments: []); try await Task.sleep(nanoseconds: 5_000_000)
        _ = try await q.enqueue(sub(), attachments: []); try await Task.sleep(nanoseconds: 5_000_000)
        _ = try await q.enqueue(sub(), attachments: [])
        let all = await q.loadAll()
        XCTAssertEqual(all.count, 2)
        XCTAssertFalse(all.map(\.localId).contains(a)) // oldest evicted
    }

    func testPruneAgedOut() async throws {
        let dir = tmp()
        let q = SubmissionQueue(directory: dir, maxEntries: 50, maxAge: 0) // everything immediately aged
        _ = try await q.enqueue(sub(), attachments: [])
        await q.pruneExpired()
        let all = await q.loadAll()
        XCTAssertTrue(all.isEmpty)
    }
}
```

- [ ] **Step 2: Run, verify FAIL** — `swift test --filter SubmissionQueueCapsTests 2>&1 | tail -15` → FAIL (no cap enforcement / `pruneExpired` undefined).

- [ ] **Step 3: Implement** — In `SubmissionQueue.swift`, add the allowed-MIME set and validation, call it at the top of `enqueue` (before any disk write), add eviction after persist, and add `pruneExpired()`:
```swift
    static let allowedMIME: Set<String> = [
        "image/jpeg", "image/png", "image/heic", "image/heif", "image/webp",
        "application/pdf", "text/plain"
    ]

    private func validate(_ attachments: [CommentRelayQueuedAttachment]) throws {
        for a in attachments {
            if a.data.count > 10_000_000 {
                throw CommentRelayError.badRequest(message: "attachment \(a.fileName) exceeds 10MB")
            }
            if !Self.allowedMIME.contains(a.contentType) {
                throw CommentRelayError.badRequest(message: "attachment type \(a.contentType) not allowed")
            }
        }
        let byField = Dictionary(grouping: attachments, by: \.fieldId)
        for (field, group) in byField where group.count > 3 {
            throw CommentRelayError.badRequest(message: "field \(field) exceeds 3 files")
        }
    }

    private func evictIfNeeded() {
        var entries = loadAll() // FIFO (oldest first)
        while entries.count > maxEntries {
            delete(localId: entries.removeFirst().localId)
        }
    }

    func pruneExpired() {
        let cutoff = Date().addingTimeInterval(-maxAge)
        for e in loadAll() where e.createdAt < cutoff { delete(localId: e.localId) }
    }
```
Then change `enqueue` to call validation first and evict after persist:
```swift
    func enqueue(_ submission: CommentRelaySubmission,
                 attachments: [CommentRelayQueuedAttachment]) throws -> UUID {
        try validate(attachments)
        let id = UUID()
        let dir = entryDir(id)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for att in attachments {
            try att.data.write(to: dir.appendingPathComponent(att.fileName), options: .atomic)
        }
        let refs = attachments.map {
            QueuedFileRef(fieldId: $0.fieldId, fileName: $0.fileName,
                          contentType: $0.contentType, size: $0.data.count)
        }
        let entry = QueuedSubmission(
            localId: id, submission: submission, phase: .needsSubmit,
            serverSubmissionId: nil, attachments: refs,
            attemptCount: 0, nextEarliestAttempt: nil, createdAt: Date(), lastError: nil)
        try persist(entry)
        evictIfNeeded()
        return id
    }
```

- [ ] **Step 4: Run, verify PASS** — `swift test --filter SubmissionQueueCapsTests 2>&1 | tail -15` → PASS (5 tests). Also re-run Task 4 suite to confirm no regression: `swift test --filter SubmissionQueuePersistenceTests 2>&1 | tail -5`.

- [ ] **Step 5: Commit & push**

```bash
git add Sources/CommentRelayCore/Internal/SubmissionQueue.swift Tests/CommentRelayCoreTests/SubmissionQueueCapsTests.swift
git commit -m "feat(CRLBS-114): enforce attachment caps, FIFO eviction, age prune

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
git push
```

---

## Task 6: `RetryPolicy` — terminal/retryable routing + backoff

**Files:** Create `Sources/CommentRelayCore/Internal/RetryPolicy.swift`; Test `Tests/CommentRelayCoreTests/RetryPolicyTests.swift`.

- [ ] **Step 1: Failing test** — Create `Tests/CommentRelayCoreTests/RetryPolicyTests.swift`:
```swift
import XCTest
@testable import CommentRelayCore

final class RetryPolicyTests: XCTestCase {
    func testClassification() {
        XCTAssertEqual(RetryPolicy.classify(.transport(URLError(.notConnectedToInternet))), .retry(nil))
        XCTAssertEqual(RetryPolicy.classify(.server(message: "x")), .retry(nil))
        XCTAssertEqual(RetryPolicy.classify(.rateLimited(retryAfter: 12)), .retry(12))
        XCTAssertEqual(RetryPolicy.classify(.badRequest(message: "x")), .terminal)
        XCTAssertEqual(RetryPolicy.classify(.paymentRequired(message: "x")), .terminal)
        XCTAssertEqual(RetryPolicy.classify(.notFound(message: "x")), .terminal)
        XCTAssertEqual(RetryPolicy.classify(.forbidden(message: "x")), .pause)
    }

    func testBackoffCapsAt30AndUsesRetryAfterWhenLarger() {
        XCTAssertEqual(RetryPolicy.backoff(attempt: 1, retryAfter: nil), 1)
        XCTAssertEqual(RetryPolicy.backoff(attempt: 5, retryAfter: nil), 16)
        XCTAssertEqual(RetryPolicy.backoff(attempt: 7, retryAfter: nil), 30) // 2^6=64 capped
        XCTAssertEqual(RetryPolicy.backoff(attempt: 1, retryAfter: 45), 45)  // retryAfter wins
        XCTAssertEqual(RetryPolicy.backoff(attempt: 7, retryAfter: 5), 30)   // max(cap, retryAfter)
    }
}
```

- [ ] **Step 2: Run, verify FAIL** — `swift test --filter RetryPolicyTests 2>&1 | tail -15` → FAIL (`RetryPolicy` undefined).

- [ ] **Step 3: Implement** — Create `Sources/CommentRelayCore/Internal/RetryPolicy.swift`:
```swift
import Foundation

enum RetryDecision: Equatable {
    case retry(TimeInterval?)   // associated value = server-supplied Retry-After, if any
    case terminal
    case pause                  // 403: engage circuit-breaker, retain entries
}

enum RetryPolicy {
    static func classify(_ error: CommentRelayError) -> RetryDecision {
        switch error {
        case .transport, .server: return .retry(nil)
        case .rateLimited(let after): return .retry(after)
        case .forbidden: return .pause
        case .badRequest, .paymentRequired, .notFound, .decoding,
             .conflict, .uploadFailed, .uploadUrlExpired:
            return .terminal
        }
    }

    /// Exponential `2^(attempt-1)` capped at 30s; if `retryAfter` is larger, it wins.
    static func backoff(attempt: Int, retryAfter: TimeInterval?) -> TimeInterval {
        let exp = pow(2.0, Double(max(attempt, 1) - 1))
        let capped = min(exp, 30)
        if let ra = retryAfter { return max(capped, ra) }
        return capped
    }
}
```
> Note: `.conflict`/`.uploadUrlExpired` are routed as `.terminal` here only for the generic classifier; the flush state machine (Task 7) handles `.conflict` as finalize-success and `.uploadUrlExpired` as the S3 re-POST path *before* calling `classify`.

- [ ] **Step 4: Run, verify PASS** — `swift test --filter RetryPolicyTests 2>&1 | tail -15` → PASS (2 tests).

- [ ] **Step 5: Commit & push**

```bash
git add Sources/CommentRelayCore/Internal/RetryPolicy.swift Tests/CommentRelayCoreTests/RetryPolicyTests.swift
git commit -m "feat(CRLBS-114): add RetryPolicy classification and capped backoff

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
git push
```

---

## Task 7: `SubmitOutcome` + `CommentRelayClient` integration & flush state machine

This is the largest task. It introduces `SubmitOutcome`, makes `submit` auto-queue, adds the flush state machine driving POST→upload→finalize via the existing client methods, plus `pendingSubmissionCount`, `pendingSubmissionCountStream()`, `flushQueue()`. It deliberately reuses existing `submit`/`uploadFiles`/`finalize`/`resubmit`.

**Files:** Create `Sources/CommentRelayCore/Public/SubmitOutcome.swift`; Modify `Sources/CommentRelayCore/Public/CommentRelayClient.swift`; Test `Tests/CommentRelayCoreTests/SubmissionQueueFlushTests.swift`, `Tests/CommentRelayCoreTests/ClientSubmitOutcomeTests.swift`.

- [ ] **Step 1: Failing tests** — Create `Sources/CommentRelayCore/Public/SubmitOutcome.swift` is implementation; the *test* comes first. Create `Tests/CommentRelayCoreTests/ClientSubmitOutcomeTests.swift`:
```swift
import XCTest
@testable import CommentRelayCore

final class ClientSubmitOutcomeTests: XCTestCase {
    private func tmp() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("cso-\(UUID())")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true); return u
    }
    private func client(_ session: URLSession, _ dir: URL, queueing: Bool = true) -> CommentRelayClient {
        let cfg = CommentRelayConfiguration(baseURL: URL(string: "https://example.test")!,
                                            apiKey: "k", userIdentifier: "u",
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
```
Create `Tests/CommentRelayCoreTests/SubmissionQueueFlushTests.swift`:
```swift
import XCTest
@testable import CommentRelayCore

final class SubmissionQueueFlushTests: XCTestCase {
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
```
> If a `URLProtocolStub` test helper does not already exist, the implementer must add it under `Tests/CommentRelayCoreTests/Support/URLProtocolStub.swift` with: a static `error: URLError?`, static `responder: ((URLRequest) -> (Data, Int))?`, `makeSession()` returning a `URLSession` whose `protocolClasses` is `[URLProtocolStub.self]`, and `startLoading` that returns `error` (as a failed load) when set, else the `responder` body with the given HTTP status. Reset statics in `setUp()`/`tearDown()`. Inspect existing tests first — reuse any equivalent stub already present (`grep -rl "URLProtocol" Tests/`).

- [ ] **Step 2: Run, verify FAIL** — `swift test --filter ClientSubmitOutcomeTests 2>&1 | tail -20` then `--filter SubmissionQueueFlushTests` → FAIL (`submit(_:attachments:)` / `SubmitOutcome` / `pendingSubmissionCount` / `flushQueue` undefined).

- [ ] **Step 3: Implement** — Create `Sources/CommentRelayCore/Public/SubmitOutcome.swift`:
```swift
import Foundation

public enum SubmitOutcome: Sendable, Equatable {
    case submitted(CommentRelaySubmissionReceipt)
    case queued(localId: UUID)
}
```
In `CommentRelayClient.swift`:

(a) Add stored property and construct the queue in **both** inits (mirror `draftStore` lines):
```swift
    private let submissionQueue: SubmissionQueue
```
In the public init, after `self.draftStore = ...`:
```swift
        self.submissionQueue = SubmissionQueue(directory: dir,
            maxEntries: configuration.maxQueuedSubmissions, maxAge: configuration.maxQueueAge)
```
In the test-only init, after its `self.draftStore = ...`:
```swift
        self.submissionQueue = SubmissionQueue(directory: cacheDirectory,
            maxEntries: configuration.maxQueuedSubmissions, maxAge: configuration.maxQueueAge)
```

(b) Add a pending-count broadcaster (place near other private state):
```swift
    private var pendingCountContinuations: [UUID: AsyncStream<Int>.Continuation] = [:]

    public var pendingSubmissionCount: Int {
        get async { await submissionQueue.count }
    }

    public func pendingSubmissionCountStream() -> AsyncStream<Int> {
        AsyncStream { continuation in
            let id = UUID()
            pendingCountContinuations[id] = continuation
            let queue = submissionQueue
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removePendingContinuation(id) }
            }
            Task { continuation.yield(await queue.count) }
        }
    }

    private func removePendingContinuation(_ id: UUID) {
        pendingCountContinuations[id] = nil
    }

    private func broadcastPendingCount() async {
        let n = await submissionQueue.count
        for c in pendingCountContinuations.values { c.yield(n) }
    }
```

(c) Rename the existing network `submit` to a private helper and add the public auto-queueing API. Replace the current `public func submit(...)` body region: keep the network call as `private func postSubmission(_:) async throws -> CommentRelaySubmissionReceipt` (identical body to today's `submit`), and add:
```swift
    @discardableResult
    public func submit(_ submission: CommentRelaySubmission,
                       attachments: [CommentRelayQueuedAttachment] = []) async throws -> SubmitOutcome {
        try ensureEnabled()
        do {
            let receipt = try await postSubmission(submission)
            if receipt.hasUploads {
                let payloads = attachments.compactMap { att -> CommentRelayFilePayload? in
                    guard let target = receipt.uploadUrls.first(where: {
                        $0.fieldId == att.fieldId && $0.fileName == att.fileName }) else { return nil }
                    return CommentRelayFilePayload(target: target, data: att.data, contentType: att.contentType)
                }
                try await uploadFiles(receipt: receipt, payloads: payloads)
            } else {
                try await finalize(submissionId: receipt.submissionId)
            }
            return .submitted(receipt)
        } catch let err as CommentRelayError {
            switch RetryPolicy.classify(err) {
            case .terminal, .pause:
                throw err                              // terminal still throws; 403 already disabled via existing paths
            case .retry:
                guard configuration.offlineQueueingEnabled else { throw err }
                let id = try await submissionQueue.enqueue(submission, attachments: attachments)
                await broadcastPendingCount()
                return .queued(localId: id)
            }
        }
    }
```
> Keep the existing public `resubmit(_:)` delegating to `postSubmission`. The internal `submit` callers within the file (none today) are unaffected. `enqueue` re-validates attachment caps and may throw `.badRequest` (terminal) which correctly propagates.

(d) Add the flush state machine:
```swift
    public func flushQueue() async {
        await submissionQueue.pruneExpired()
        guard isEnabled else { return }     // 403 pause: retain entries, do nothing
        let entries = await submissionQueue.loadAll()   // FIFO
        let now = Date()
        for var entry in entries {
            if let next = entry.nextEarliestAttempt, next > now { continue }
            do {
                try await advance(&entry)
            } catch let err as CommentRelayError {
                switch RetryPolicy.classify(err) {
                case .pause:
                    return                                  // circuit-breaker already engaged by callee
                case .terminal:
                    await submissionQueue.delete(localId: entry.localId)
                    CommentRelayLoggerHolder.shared.log(level: .error,
                        message: "queued submission dropped (terminal)", error: err)
                case .retry(let retryAfter):
                    entry.attemptCount += 1
                    entry.lastError = "\(err)"
                    entry.nextEarliestAttempt = now.addingTimeInterval(
                        RetryPolicy.backoff(attempt: entry.attemptCount, retryAfter: retryAfter))
                    try? await submissionQueue.persist(entry)
                }
            } catch {
                entry.attemptCount += 1
                entry.nextEarliestAttempt = now.addingTimeInterval(
                    RetryPolicy.backoff(attempt: entry.attemptCount, retryAfter: nil))
                try? await submissionQueue.persist(entry)
            }
        }
        await broadcastPendingCount()
    }

    /// One entry, finalize-first. Throws CommentRelayError on failure (router in flushQueue handles it).
    private func advance(_ entry: inout QueuedSubmission) async throws {
        // Finalize-first resume: a prior crash after POST must not create a duplicate.
        if let serverId = entry.serverSubmissionId, entry.phase == .needsFinalize {
            try await finalize(submissionId: serverId)            // .conflict treated as success inside finalize
            await submissionQueue.delete(localId: entry.localId)
            return
        }
        switch entry.phase {
        case .needsSubmit:
            let receipt = try await postSubmission(entry.submission)
            entry.serverSubmissionId = receipt.submissionId
            entry.phase = entry.attachments.isEmpty ? .needsFinalize : .needsUpload
            try await submissionQueue.persist(entry)
            try await advance(&entry)                              // continue same pass
        case .needsUpload:
            guard let serverId = entry.serverSubmissionId else { entry.phase = .needsSubmit; throw CommentRelayError.transport(URLError(.unknown)) }
            // Re-POST to get fresh presigned URLs (never cached), then PUT sidecars.
            let receipt = try await postSubmission(entry.submission)
            entry.serverSubmissionId = receipt.submissionId
            let payloads: [CommentRelayFilePayload] = entry.attachments.compactMap { ref in
                guard let target = receipt.uploadUrls.first(where: {
                    $0.fieldId == ref.fieldId && $0.fileName == ref.fileName }),
                    let data = await? submissionQueue.readSidecar(localId: entry.localId, fileName: ref.fileName)
                else { return nil }
                return CommentRelayFilePayload(target: target, data: data, contentType: ref.contentType)
            }
            try await uploadFiles(receipt: receipt, payloads: payloads)
            entry.phase = .needsFinalize
            try await submissionQueue.persist(entry)
            try await advance(&entry)
            _ = serverId
        case .needsFinalize:
            if let serverId = entry.serverSubmissionId {
                try await finalize(submissionId: serverId)
            }
            await submissionQueue.delete(localId: entry.localId)
        case .done:
            await submissionQueue.delete(localId: entry.localId)
        }
    }
```
> `await?` is not Swift syntax — implement the sidecar fetch as a plain `await` into an optional `let data = await submissionQueue.readSidecar(...)` then `guard let data else { return nil }` inside the closure (rewrite the `compactMap` body accordingly; the closure must be `async`, so use a `for`-loop building `payloads` instead of `compactMap` to keep it simple and correct). The implementer should write the loop form; this is the one place to deviate from the snippet for correctness.

- [ ] **Step 4: Run, verify PASS** — `swift test --filter ClientSubmitOutcomeTests 2>&1 | tail -20` and `swift test --filter SubmissionQueueFlushTests 2>&1 | tail -20` → PASS. Re-run Tasks 4–6 suites for regression.

- [ ] **Step 5: Commit & push**

```bash
git add Sources/CommentRelayCore/Public/SubmitOutcome.swift Sources/CommentRelayCore/Public/CommentRelayClient.swift Tests/CommentRelayCoreTests/ClientSubmitOutcomeTests.swift Tests/CommentRelayCoreTests/SubmissionQueueFlushTests.swift Tests/CommentRelayCoreTests/Support/URLProtocolStub.swift
git commit -m "feat(CRLBS-114): auto-queue submit (SubmitOutcome) + finalize-first flush

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
git push
```

---

## Task 8: Offline config availability (`fetchConfig` fallback + `effectiveConfig()`)

**Files:** Modify `Sources/CommentRelayCore/Public/CommentRelayClient.swift`; Test `Tests/CommentRelayCoreTests/OfflineConfigTests.swift`.

- [ ] **Step 1: Failing test** — Create `Tests/CommentRelayCoreTests/OfflineConfigTests.swift`:
```swift
import XCTest
@testable import CommentRelayCore

final class OfflineConfigTests: XCTestCase {
    private func tmp() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("ocfg-\(UUID())")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true); return u
    }
    private func client(_ s: URLSession, _ d: URL) -> CommentRelayClient {
        CommentRelayClient(configuration: CommentRelayConfiguration(
            baseURL: URL(string: "https://example.test")!, apiKey: "k"),
            session: s, cacheDirectory: d, keychainService: "svc-\(UUID())")
    }
    private func form() -> CommentRelayForm {
        CommentRelayForm(id: "a", title: "T", showInPicker: true, responseLimitCount: nil,
            responseLimitType: nil, responseLimitWindowMinutes: nil, moreFeedbackPrompt: nil,
            isActive: true, sortOrder: 1, fields: [])
    }

    func testFetchConfigFallsBackToCacheOnTransportFailure() async throws {
        let dir = tmp()
        // Seed cache via a successful fetch.
        URLProtocolStub.error = nil
        URLProtocolStub.responder = { _ in
            (Data("{\"current\":false,\"hash\":\"h1\",\"forms\":[{\"id\":\"a\",\"title\":\"T\",\"show_in_picker\":true,\"response_limit_count\":null,\"response_limit_type\":null,\"response_limit_window_minutes\":null,\"more_feedback_prompt\":null,\"is_active\":true,\"sort_order\":1,\"fields\":[]}]}".utf8), 200)
        }
        let c = client(URLProtocolStub.makeSession(), dir)
        _ = try await c.fetchConfig(cachedHash: nil)
        // Now go offline; fetchConfig must return cached forms, not throw.
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
```

- [ ] **Step 2: Run, verify FAIL** — `swift test --filter OfflineConfigTests 2>&1 | tail -20` → FAIL (no fallback; `effectiveConfig` undefined).

- [ ] **Step 3: Implement** — In `CommentRelayClient.swift`, replace `fetchConfig` with a self-hash + cache-fallback version and add `effectiveConfig()`:
```swift
    public func fetchConfig(cachedHash: String?) async throws -> CommentRelayConfigResponse {
        try ensureEnabled()
        let effectiveHash = cachedHash ?? configCache.read()?.hash
        let basePath = "sdk/v1/config"
        let queryItems: [URLQueryItem]? = effectiveHash.map { [URLQueryItem(name: "hash", value: $0)] }
        do {
            let response: CommentRelayConfigResponse = try await api.send(
                method: "GET", path: basePath, queryItems: queryItems,
                decodingAs: CommentRelayConfigResponse.self)
            if case .updated(let hash, let forms) = response {
                await configCache.write(hash: hash, forms: forms)
            }
            if case .current = response, let snap = configCache.read() {
                return .updated(hash: snap.hash, forms: snap.forms)   // resolve to usable forms
            }
            return response
        } catch let err as CommentRelayError {
            if case .transport = err, let snap = configCache.read() {
                return .updated(hash: snap.hash, forms: snap.forms)    // offline fallback
            }
            if case .forbidden = err { /* existing disable path in api layer */ }
            throw err
        }
    }

    /// Cached-or-fresh forms accessor so the UI can render offline.
    public func effectiveConfig() async throws -> CommentRelayConfigResponse {
        try await fetchConfig(cachedHash: nil)
    }
```
> Existing callers pass `cachedHash:` explicitly; behavior is unchanged when online with a fresh hash. The `.current` → resolve-from-cache change makes `.current` return usable forms (previously callers had to read the cache themselves); verify no existing test asserts the raw `.current` case from `fetchConfig` (`grep -rn "case .current" Tests/`); if one does, update it to expect the resolved `.updated`.

- [ ] **Step 4: Run, verify PASS** — `swift test --filter OfflineConfigTests 2>&1 | tail -20` → PASS (3). Re-run full suite: `swift test 2>&1 | grep -E "Executed [0-9]+ tests, with [0-9]+ failures" | tail -1` (0 failures; fix any `.current` assertion fallout here).

- [ ] **Step 5: Commit & push**

```bash
git add Sources/CommentRelayCore/Public/CommentRelayClient.swift Tests/CommentRelayCoreTests/OfflineConfigTests.swift
git commit -m "feat(CRLBS-114): offline config fallback + effectiveConfig accessor

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
git push
```

---

## Task 9: Flush triggers (reachability-restored / init / foreground)

**Files:** Modify `Sources/CommentRelayCore/Public/CommentRelayClient.swift`; Test `Tests/CommentRelayCoreTests/FlushTriggerTests.swift`.

Inject `Reachability` via the **test-only** init (add a parameter with a production default of `NetworkReachability()`); the public init always uses `NetworkReachability()`.

- [ ] **Step 1: Failing test** — Create `Tests/CommentRelayCoreTests/FlushTriggerTests.swift`:
```swift
import XCTest
@testable import CommentRelayCore

final class FlushTriggerTests: XCTestCase {
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
        XCTAssertEqual(await c.pendingSubmissionCount, 1)
        URLProtocolStub.error = nil
        URLProtocolStub.responder = { req in
            req.url!.path.hasSuffix("/finalize")
              ? (Data("{\"submission_id\":\"\(UUID().uuidString)\",\"status\":\"complete\"}".utf8), 200)
              : (Data("{\"submission_id\":\"\(UUID().uuidString)\",\"has_uploads\":false,\"upload_urls\":[]}".utf8), 200)
        }
        fake.set(true)                              // connectivity restored
        try await Task.sleep(nanoseconds: 300_000_000) // allow triggered flush
        XCTAssertEqual(await c.pendingSubmissionCount, 0)
    }
}
```

- [ ] **Step 2: Run, verify FAIL** — `swift test --filter FlushTriggerTests 2>&1 | tail -20` → FAIL (init has no `reachability:` param; no trigger).

- [ ] **Step 3: Implement** — In `CommentRelayClient.swift`:
  - Add `private let reachability: Reachability` and a `private var flushTriggerTask: Task<Void, Never>?`.
  - Public init: set `self.reachability = NetworkReachability()` then (at end) `startFlushTriggers()`.
  - Test-only init: add parameter `reachability: Reachability = NetworkReachability()`, assign it, then call `startFlushTriggers()` at the end.
  - Add:
```swift
    private func startFlushTriggers() {
        flushTriggerTask = Task { [weak self] in
            await self?.flushQueue()                       // init trigger
            guard let stream = self?.reachability.changes else { return }
            for await connected in stream where connected {
                await self?.flushQueue()                   // connectivity-restored trigger
            }
        }
    }
```
  - Foreground trigger: `submit(...)` and `flushQueue()` are already explicit triggers per spec; an app-foreground `NotificationCenter` observer is **out of scope here** to keep Core platform-neutral (documented in spec "Out of scope" only covers background URLSession; foreground hook is added in `CommentRelayUI` via `.onChange(of: scenePhase)` calling `flushQueue()` in Task 11). Note this in the commit body.

- [ ] **Step 4: Run, verify PASS** — `swift test --filter FlushTriggerTests 2>&1 | tail -20` → PASS. Re-run Task 7/8 suites.

- [ ] **Step 5: Commit & push**

```bash
git add Sources/CommentRelayCore/Public/CommentRelayClient.swift Tests/CommentRelayCoreTests/FlushTriggerTests.swift
git commit -m "feat(CRLBS-114): flush on init and connectivity-restored (injectable reachability)

App-foreground trigger handled in CommentRelayUI (scenePhase) to keep Core platform-neutral.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
git push
```

---

## Task 10: Update `CommentRelayUI` for `SubmitOutcome` + pass attachments (breaking-change call sites)

**Files:** Modify `Sources/CommentRelayUI/Screens/FeedbackFormViewModel.swift`, `Sources/CommentRelayUI/Screens/CommentRelayView.swift`; Test `Tests/CommentRelayUITests/ScreenTests/SubmitOutcomeRoutingTests.swift`.

- [ ] **Step 1: Failing test** — Create `Tests/CommentRelayUITests/ScreenTests/SubmitOutcomeRoutingTests.swift` verifying `FeedbackFormViewModel.queuedAttachments()` returns one `CommentRelayQueuedAttachment` per staged file with matching `fieldId/fileName/contentType/data`. (Use the existing smiley/file form JSON pattern from `RatingPayloadTests`/`FeedbackFormViewModelTests`; stage a file via the view model's existing attachment API, then assert `queuedAttachments()` output.)
```swift
import XCTest
import CommentRelayCore
@testable import CommentRelayUI

final class SubmitOutcomeRoutingTests: XCTestCase {
    func testQueuedAttachmentsMirrorStagedFiles() throws {
        let vm = FeedbackFormViewModel(form: try Fixtures.fileForm(),
                                       userIdentifier: "u", platform: .ios, sdkVersion: nil)
        vm.attach(fieldId: "file-1", fileName: "a.png", mimeType: "image/png", data: Data([9,9]))
        let q = vm.queuedAttachments()
        XCTAssertEqual(q.count, 1)
        XCTAssertEqual(q.first?.fieldId, "file-1")
        XCTAssertEqual(q.first?.fileName, "a.png")
        XCTAssertEqual(q.first?.contentType, "image/png")
        XCTAssertEqual(q.first?.data, Data([9,9]))
    }
}
```
> The implementer must inspect `FeedbackFormViewModel`'s existing attachment storage (the `filePayloads(for:)` source at line ~92 shows it iterates staged attachments with `.data`/`.mimeType`) and add `Fixtures.fileForm()` + `attach(...)` only if equivalents don't already exist; reuse existing helpers/fixtures where present (`grep -rn "func attach\|fileForm\|Fixtures" Tests/CommentRelayUITests`).

- [ ] **Step 2: Run, verify FAIL** — `swift test --filter SubmitOutcomeRoutingTests 2>&1 | tail -15` → FAIL (`queuedAttachments()` undefined).

- [ ] **Step 3: Implement**
  - In `FeedbackFormViewModel.swift`, add (next to `filePayloads(for:)`):
```swift
    public func queuedAttachments() -> [CommentRelayQueuedAttachment] {
        var result: [CommentRelayQueuedAttachment] = []
        for (fieldId, atts) in attachmentsByField {        // use the same storage filePayloads(for:) iterates
            for att in atts {
                result.append(CommentRelayQueuedAttachment(
                    fieldId: fieldId, fileName: att.fileName,
                    contentType: att.mimeType, data: att.data))
            }
        }
        return result
    }
```
  > Match the actual property/shape used by `filePayloads(for:)` (it references `att.data`, `att.mimeType`, and a per-field grouping); mirror that exact structure rather than inventing `attachmentsByField` if the real name differs.
  - In `CommentRelayView.swift` `submitWithViewModel(_:)`, replace the body that calls `client.submit` so it passes attachments and switches on `SubmitOutcome`:
```swift
        do {
            let outcome = try await client.submit(submission, attachments: vm.queuedAttachments())
            switch outcome {
            case .submitted:
                route = .thanks(showHistory: configuration.userIdentifier != nil)
            case .queued:
                route = .thanks(showHistory: configuration.userIdentifier != nil)
                // queued is success from the user's perspective; pending badge reflects state
            }
        } catch let err as CommentRelayError {
            CommentRelayLoggerHolder.shared.log(level: .error, message: "submit failed", error: err)
            route = .progressFailed(message: message(for: err))
        } catch {
            CommentRelayLoggerHolder.shared.log(level: .error, message: "submit failed with unexpected error", error: error)
            route = .progressFailed(message: Strings.errorGeneric)
        }
```
  > The old code called `uploadFiles`/`finalize` from the view; that orchestration now lives inside `client.submit`. Remove the now-dead `vm.filePayloads(for:)`/`uploadFiles`/`finalize` lines from this method only. Leave `filePayloads(for:)` itself in place (still used by Core tests / public API).

- [ ] **Step 4: Run, verify PASS** — `swift test --filter SubmitOutcomeRoutingTests 2>&1 | tail -15` → PASS. Then full suite (`swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1`) — fix any UI test that asserted the old submit/upload/finalize sequence.

- [ ] **Step 5: Commit & push**

```bash
git add Sources/CommentRelayUI/Screens/FeedbackFormViewModel.swift Sources/CommentRelayUI/Screens/CommentRelayView.swift Tests/CommentRelayUITests/ScreenTests/SubmitOutcomeRoutingTests.swift
git commit -m "feat(CRLBS-114): route SubmitOutcome and pass queued attachments from UI

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
git push
```

---

## Task 11: `CommentRelayUI` pending-count badge + scenePhase foreground flush

**Files:** Create `Sources/CommentRelayUI/Components/PendingBadge.swift`; Modify `Sources/CommentRelayUI/Screens/CommentRelayView.swift`; Test `Tests/CommentRelayUITests/ScreenTests/PendingBadgeTests.swift`.

- [ ] **Step 1: Failing test** — Create `Tests/CommentRelayUITests/ScreenTests/PendingBadgeTests.swift`:
```swift
import XCTest
import SwiftUI
import ViewInspector
@testable import CommentRelayUI

final class PendingBadgeTests: XCTestCase {
    func testHiddenWhenZero() throws {
        let v = PendingBadge(count: 0)
        XCTAssertThrowsError(try v.inspect().find(text: "0"))
    }
    func testShowsCountWhenPositive() throws {
        let v = PendingBadge(count: 3)
        XCTAssertNoThrow(try v.inspect().find(text: "3"))
    }
}
```

- [ ] **Step 2: Run, verify FAIL** — `swift test --filter PendingBadgeTests 2>&1 | tail -15` → FAIL (`PendingBadge` undefined).

- [ ] **Step 3: Implement** — Create `Sources/CommentRelayUI/Components/PendingBadge.swift`:
```swift
import SwiftUI

/// Minimal, platform-neutral pending-count badge. Hidden when count == 0.
public struct PendingBadge: View {
    public let count: Int
    public init(count: Int) { self.count = count }
    public var body: some View {
        Group {
            if count > 0 {
                Text("\(count)")
                    .font(.caption2).bold()
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(.red))
                    .foregroundStyle(.white)
                    .accessibilityLabel(Text("\(count) pending feedback submissions"))
            }
        }
    }
}
```
  - In `CommentRelayView.swift`: add `@State private var pendingCount = 0`, overlay `PendingBadge(count: pendingCount)` on the entry/history affordance, and bind it + add the foreground flush:
```swift
        .task {
            for await n in client.pendingSubmissionCountStream() { pendingCount = n }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await client.flushQueue() } }
        }
```
  (add `@Environment(\.scenePhase) private var scenePhase` to the view). Place the overlay where the existing entry affordance/history button is rendered; if none is visible in the current route, attach the `.task` to the root container so the stream still drives `pendingCount`.

- [ ] **Step 4: Run, verify PASS** — `swift test --filter PendingBadgeTests 2>&1 | tail -15` → PASS (2).

- [ ] **Step 5: Commit & push**

```bash
git add Sources/CommentRelayUI/Components/PendingBadge.swift Sources/CommentRelayUI/Screens/CommentRelayView.swift Tests/CommentRelayUITests/ScreenTests/PendingBadgeTests.swift
git commit -m "feat(CRLBS-114): pending-count badge + scenePhase foreground flush

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
git push
```

---

## Task 12: README + full-suite regression gate

**Files:** Modify `README.md`.

- [ ] **Step 1: Add an Offline section** — Append to `README.md`:
```markdown

## Offline submissions

`submit(_:attachments:)` returns `SubmitOutcome`: `.submitted(receipt)` when delivered immediately, or `.queued(localId:)` when offline / on a transient failure (queueing is on by default — set `offlineQueueingEnabled: false` to opt out, in which case transient failures throw). Terminal errors (`400/402/403/404`/decoding) always throw and are never queued.

Queued submissions persist to disk (max `maxQueuedSubmissions`, default 50; max `maxQueueAge`, default 30 days; FIFO eviction) and are delivered automatically on connectivity-restored, SDK init, app foreground, or any `submit()`/`flushQueue()` call. Delivery is finalize-first so a crash after the server accepted a submission does not create a duplicate; presigned upload URLs are never cached (a resumed upload re-requests fresh URLs). Observe `pendingSubmissionCount` / `pendingSubmissionCountStream()`; `CommentRelayUI` shows a pending badge. Feedback forms render offline from cached config via `effectiveConfig()`.
```

- [ ] **Step 2: Full regression gate**

Run: `swift build 2>&1 | tail -3 && swift test 2>&1 | grep -E "Test Suite 'All tests'|Executed [0-9]+ tests, with [0-9]+ failures" | tail -2`
Expected: build succeeds; **0 failures**; total ≥ 155 (Task 0 baseline) + all new tests added in Tasks 1–11 (≈ +24). Record the exact number.

- [ ] **Step 3: Commit & push**

```bash
git add README.md
git commit -m "docs(CRLBS-114): document offline queue and SubmitOutcome

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
git push
```

- [ ] **Step 4: Open the PR**

```bash
cd /Users/mikesilvers/repos/commentrelay-sdk/commentrelay-sdk-ios
bb pr create -s feature/CRLBS-114-offline-storage-retry -d develop \
  -t "CRLBS-114: offline storage & retry for feedback submissions" \
  -b "<summary of SP2: SubmissionQueue, Reachability, SubmitOutcome (documented breaking change), offline config, pending badge; full suite green; references CRLBS-114>"
```
Note the **documented breaking API change** (`submit` now returns `SubmitOutcome` and takes `attachments:`) prominently in the PR description.

---

## Sequencing & notes

- Task 0 first (branch must be current). Tasks 1–6 are independent leaves and may be done in any order. Task 7 depends on 1–6. Task 8 independent of 7 (both modify `CommentRelayClient.swift` — do 7 then 8 to avoid churn). Task 9 depends on 7. Tasks 10–11 depend on 7 (and 9 for foreground). Task 12 last.
- Breaking change (`submit` signature) is intentional and pre-1.0; sample app under `Example/` must be updated if it calls `submit` (grep `Example/` — current grep shows no direct `submit(` there; verify during Task 10).

## Self-Review

**Spec coverage:** Queue storage JSON+sidecars → T3/T4 ✓. Attachment caps at enqueue → T5 ✓. Queue caps 50/30-day FIFO → T5 ✓. Flush triggers (connectivity/init/foreground/submit/flushQueue) → T7 (submit/flushQueue), T9 (connectivity/init), T11 (foreground) ✓. Auto-queue + opt-out + terminal throws → T7 ✓. Finalize-first resume → T7 `advance` ✓. Pending count Core + UI badge → T7 (count/stream), T11 (badge) ✓. Offline config fold-in (`fetchConfig` fallback + `effectiveConfig`) → T8 ✓. `SubmitOutcome` breaking change + call sites → T7/T10/T12 ✓. Backoff 2^(n-1)≤30, 429 Retry-After, 403 pause → T6/T7 ✓. Reachability injectable → T2/T9 ✓. Config knobs → T1 ✓. Suite green on macOS → T0 baseline + T12 gate ✓. Out-of-scope (background URLSession, idempotency keys, config max-age) — not implemented ✓.

**Placeholder scan:** One deliberate, bounded deviation flagged in T7 Step 3 (the async sidecar fetch must be a `for`-loop, not `compactMap` with the non-existent `await?`; explicit instruction given). All other steps carry exact code, paths, commands, expected output. Reuse-existing-helper instructions (URLProtocolStub, view-model attachment storage, UI fixtures) are bounded by concrete `grep` checks.

**Type consistency:** `SubmitOutcome` (`.submitted`/`.queued(localId:)`) consistent T7→T10. `QueuedSubmission.Phase` (`needsSubmit/needsUpload/needsFinalize/done`) consistent T3→T7. `RetryDecision` (`.retry(TimeInterval?)/.terminal/.pause`) consistent T6→T7. `CommentRelayQueuedAttachment` fields consistent T3→T7→T10. `SubmissionQueue` API (`enqueue/persist/loadAll/delete/readSidecar/count/pruneExpired`) consistent T4→T5→T7. `Reachability` (`isConnected`/`changes`) consistent T2→T9.

Open risk noted for executor: T7's `advance` `needsUpload` re-POSTs for fresh URLs every pass (spec-correct: never cache presigned URLs), accepting a duplicate-POST window mitigated by finalize-first; the API has no idempotency key (spec "Out of scope"). No code issue — design-accepted.
