# SessionStore Keychain test seam (CRLBS-124) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `CommentRelayCoreTests` pass on iOS Simulator by routing `SessionStore`'s Keychain access through an injectable `KeychainBacking` seam, so tests use an in-memory double instead of the real Keychain (which doesn't persist in SPM iOS test bundles).

**Architecture:** Extract the three Keychain operations `SessionStore` performs behind a `KeychainBacking` protocol. Production keeps the exact `SecItem*` behavior via a `SystemKeychain` default; the test target injects an `InMemoryKeychain`. No production behavior or public API changes — `SessionStore` and all new types stay internal to `CommentRelayCore`.

**Tech Stack:** Swift Package Manager, XCTest, Security framework (`SecItem*`), `NSLock`.

**Spec:** `docs/superpowers/specs/2026-05-22-sessionstore-keychain-seam-design.md`

**Base / dependency:** Branch `feature/CRLBS-124-sessionstore-keychain-seam` off `develop` (HEAD `f92a53b`). Spec committed as `81fe923` on this branch.

**Verification commands:**
- `swift build`
- `swift test --filter SessionStoreTests` (targeted) / `swift test` (full macOS suite)
- iOS Simulator: `xcodebuild test -scheme CommentRelay-Package -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/crlbs124-ios-DD`

---

## File structure

- `Sources/CommentRelayCore/Internal/SessionStore.swift` — add `KeychainBacking` protocol + `SystemKeychain` impl; refactor `SessionStore` to delegate through an injected `keychain` (defaulted to `SystemKeychain()`). Keeping all three in one file is appropriate: they are a single cohesive unit (the store + its backing abstraction) and the file stays small (~90 lines).
- `Tests/CommentRelayCoreTests/SessionStoreTests.swift` — add `InMemoryKeychain` double; rewrite the 3 existing tests to inject it; add 1 new persistence test.

No other files change. The single production consumer (`CommentRelayClient`) constructs `SessionStore(service:hostSupplied:)` and is unaffected by the new defaulted parameter.

---

## Task 1: Introduce the KeychainBacking seam in SessionStore

**Files:**
- Modify: `Sources/CommentRelayCore/Internal/SessionStore.swift`

This task is a behavior-preserving refactor of production code. The existing `SessionStoreTests` still pass against it on macOS unchanged (they use the real `SystemKeychain` default), so they act as the regression guard for this step. Test rewrites happen in Task 2.

- [ ] **Step 1: Replace the file contents with the seam version**

Replace the entire contents of `Sources/CommentRelayCore/Internal/SessionStore.swift` with:

```swift
// Sources/CommentRelayCore/Internal/SessionStore.swift
import Foundation
import Security

/// Abstraction over the three Keychain operations SessionStore performs.
/// Production uses `SystemKeychain` (real `SecItem*`); tests inject an
/// in-memory double. SPM iOS test bundles run without a host app, so the real
/// Keychain doesn't persist there — the seam keeps the identifier logic
/// testable on every platform (CRLBS-124).
protocol KeychainBacking: Sendable {
    func read(service: String, account: String) -> String?
    func write(_ value: String, service: String, account: String)
    func delete(service: String, account: String)
}

/// Real Keychain backing. Holds no mutable state, so it is `Sendable` directly.
struct SystemKeychain: KeychainBacking {
    private func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func read(service: String, account: String) -> String? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, let s = String(data: data, encoding: .utf8) else {
            return nil
        }
        return s
    }

    func write(_ value: String, service: String, account: String) {
        var attrs = baseQuery(service: service, account: account)
        attrs[kSecValueData as String] = Data(value.utf8)
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
        SecItemAdd(attrs as CFDictionary, nil)
    }

    func delete(service: String, account: String) {
        SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
    }
}

final class SessionStore: @unchecked Sendable {
    private let service: String
    private let account = "anonymousId"
    private let hostSupplied: String?
    private let keychain: KeychainBacking

    init(service: String, hostSupplied: String?, keychain: KeychainBacking = SystemKeychain()) {
        self.service = service
        self.hostSupplied = hostSupplied
        self.keychain = keychain
    }

    var isAnonymous: Bool { hostSupplied == nil }

    var effectiveIdentifier: String {
        if let hostSupplied { return hostSupplied }
        if let existing = keychain.read(service: service, account: account) { return existing }
        let generated = UUID().uuidString
        keychain.write(generated, service: service, account: account)
        return generated
    }

    @discardableResult
    func resetAnonymous() -> String {
        keychain.delete(service: service, account: account)
        return effectiveIdentifier
    }
}
```

Key points to confirm while editing:
- `kSecAttrAccessibleAfterFirstUnlock` is preserved on write (unchanged from the original).
- The delete-before-add ordering in `write` is preserved (original called `SecItemDelete` then `SecItemAdd`).
- `SessionStore` stays `final class` + `@unchecked Sendable` (it now holds a `KeychainBacking`, which is `Sendable`, but the class keeps its existing annotation — no need to change it).
- The `account` constant ("anonymousId") and `service` field are unchanged; they're now passed into the backing calls.

- [ ] **Step 2: Build**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`. If the compiler complains that `SessionStore(service:hostSupplied:)` calls elsewhere are now ambiguous, that's not expected — the new parameter is defaulted, so existing call sites compile unchanged. Investigate any error before proceeding.

- [ ] **Step 3: Run the existing SessionStore tests as a regression guard (macOS)**

Run: `swift test --filter SessionStoreTests 2>&1 | grep -E "Executed [0-9]+ tests" | tail -2`
Expected: the 3 existing tests still pass on macOS (they use the default `SystemKeychain`, behavior identical to before). This proves the refactor is behavior-preserving.

- [ ] **Step 4: Run the full Core suite (no regression)**

Run: `swift test --filter CommentRelayCoreTests 2>&1 | grep -E "Executed [0-9]+ tests" | tail -2`
Expected: 0 failures.

- [ ] **Step 5: Commit**

```bash
git add Sources/CommentRelayCore/Internal/SessionStore.swift
git commit -m "refactor(CRLBS-124): route SessionStore Keychain access through a seam

Extract KeychainBacking protocol + SystemKeychain (real SecItem* impl).
SessionStore now delegates read/write/delete to an injected backing,
defaulted to SystemKeychain so production behavior and all call sites are
unchanged. Sets up the in-memory test double (Task 2) that makes the
identifier logic testable on the iOS Simulator.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: In-memory double + SessionStoreTests rewrite

**Files:**
- Modify: `Tests/CommentRelayCoreTests/SessionStoreTests.swift`

- [ ] **Step 1: Replace the test file contents**

Replace the entire contents of `Tests/CommentRelayCoreTests/SessionStoreTests.swift` with:

```swift
// Tests/CommentRelayCoreTests/SessionStoreTests.swift
import XCTest
@testable import CommentRelayCore

/// In-memory KeychainBacking double (CRLBS-124). Mirrors the real Keychain's
/// process-wide-shared, thread-safe semantics so a single instance shared
/// between two SessionStores behaves like the real shared Keychain — without
/// the SPM-iOS-test-bundle limitation that breaks the real one.
final class InMemoryKeychain: KeychainBacking, @unchecked Sendable {
    private let lock = NSLock()
    private var store: [String: String] = [:]
    private func key(_ service: String, _ account: String) -> String { "\(service)\u{0}\(account)" }

    func read(service: String, account: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return store[key(service, account)]
    }
    func write(_ value: String, service: String, account: String) {
        lock.lock(); defer { lock.unlock() }
        store[key(service, account)] = value
    }
    func delete(service: String, account: String) {
        lock.lock(); defer { lock.unlock() }
        store[key(service, account)] = nil
    }
}

final class SessionStoreTests: XCTestCase {
    func test_hostSupplied_wins() {
        let store = SessionStore(
            service: "crl.test.\(UUID().uuidString)",
            hostSupplied: "host-user-1",
            keychain: InMemoryKeychain())
        XCTAssertEqual(store.effectiveIdentifier, "host-user-1")
        XCTAssertFalse(store.isAnonymous)
    }

    func test_anonymousId_isStableAcrossInstances() {
        let service = "crl.test.\(UUID().uuidString)"
        let backing = InMemoryKeychain()   // shared between both stores
        let a = SessionStore(service: service, hostSupplied: nil, keychain: backing)
        let b = SessionStore(service: service, hostSupplied: nil, keychain: backing)
        XCTAssertEqual(a.effectiveIdentifier, b.effectiveIdentifier)
        XCTAssertTrue(a.isAnonymous)
    }

    func test_anonymousId_persists_after_write() {
        let service = "crl.test.\(UUID().uuidString)"
        let backing = InMemoryKeychain()
        let first = SessionStore(service: service, hostSupplied: nil, keychain: backing).effectiveIdentifier
        // A fresh store on the same backing must read the persisted id, not regenerate.
        let second = SessionStore(service: service, hostSupplied: nil, keychain: backing).effectiveIdentifier
        XCTAssertEqual(first, second)
    }

    func test_reset_generatesNewId() {
        let service = "crl.test.\(UUID().uuidString)"
        let backing = InMemoryKeychain()
        let store = SessionStore(service: service, hostSupplied: nil, keychain: backing)
        let firstId = store.effectiveIdentifier
        store.resetAnonymous()
        let secondId = store.effectiveIdentifier
        XCTAssertNotEqual(firstId, secondId)
    }
}
```

Notes:
- `test_anonymousId_isStableAcrossInstances` now shares ONE `InMemoryKeychain` between `a` and `b` (the previous version relied on two stores hitting the same real Keychain service — that's exactly what failed on iOS).
- `test_anonymousId_persists_after_write` is NEW — it asserts the write actually landed (the property real Keychain failed to provide on iOS).
- `test_reset_generatesNewId` keeps the same assertion but now runs against a working backing, so it tests real rotation rather than passing by accident.
- The old `defer { _ = SessionStore(...).resetAnonymous() }` cleanup is gone — the in-memory backing is per-test, no global Keychain state to clean.

- [ ] **Step 2: Run the SessionStore tests (macOS)**

Run: `swift test --filter SessionStoreTests 2>&1 | grep -E "Executed [0-9]+ tests" | tail -2`
Expected: `Executed 4 tests, with 0 failures`.

- [ ] **Step 3: Run full Core + UI suites (macOS, no regression)**

Run: `swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -2`
Expected: 0 failures. (Total count rises by 1 vs the prior baseline — the new persistence test.)

- [ ] **Step 4: Commit**

```bash
git add Tests/CommentRelayCoreTests/SessionStoreTests.swift
git commit -m "test(CRLBS-124): inject in-memory Keychain in SessionStoreTests

Adds InMemoryKeychain double and rewrites the suite to inject it, so the
identifier logic is tested hermetically on every platform (no real Keychain).
Fixes test_anonymousId_isStableAcrossInstances on iOS Simulator, fixes
test_reset_generatesNewId's accidental pass, and adds an explicit
persists-after-write test.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Verify on iOS Simulator + push + PR

**Files:** none (verification + ship).

This task proves the actual CRLBS-124 acceptance criterion: the suite is green on iOS Simulator, where it previously failed.

- [ ] **Step 1: Run CommentRelayCoreTests on iOS Simulator**

Run:
```bash
xcodebuild test -scheme CommentRelay-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/crlbs124-ios-DD 2>&1 \
  | grep -E "Test Suite '(CommentRelayCoreTests|CommentRelayUITests|All tests)'|Executed [0-9]+ tests|error: -\[|\*\* TEST" | tail -20
```
Expected:
- `CommentRelayCoreTests.xctest` passes (no `SessionStoreTests` failure).
- `CommentRelayUITests.xctest` passes (was already green).
- `** TEST SUCCEEDED **`.

If `iPhone 17` is not an available simulator, list devices with `xcrun simctl list devices available | grep iPhone` and substitute an available one in the `-destination` (any modern iPhone simulator is fine; the failure was platform-class, not device-specific).

- [ ] **Step 2: Confirm the previously-failing test now passes on iOS**

In the Step 1 output, confirm there is NO line matching:
```
error: -[CommentRelayCoreTests.SessionStoreTests test_anonymousId_isStableAcrossInstances]
```
Its absence (plus `TEST SUCCEEDED`) is the CRLBS-124 fix verified.

- [ ] **Step 3: Clean the iOS derived-data dir**

Run: `rm -rf /tmp/crlbs124-ios-DD`

- [ ] **Step 4: Full macOS suite one more time + clean tree check**

Run: `swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -2`
Expected: 0 failures.

Run: `git status --porcelain`
Expected: empty.

- [ ] **Step 5: Push branch**

Run: `git push -u origin feature/CRLBS-124-sessionstore-keychain-seam 2>&1 | tail -2`

- [ ] **Step 6: Open Bitbucket PR to develop**

```bash
bb pr create -s feature/CRLBS-124-sessionstore-keychain-seam -d develop \
  -t "test(CRLBS-124): SessionStore Keychain seam — fixes iOS Simulator test failure" \
  -b "$(cat <<'PR_BODY_EOF'
Implements `docs/superpowers/specs/2026-05-22-sessionstore-keychain-seam-design.md` per `docs/superpowers/plans/2026-05-22-sessionstore-keychain-seam.md`.

## Problem
`SessionStoreTests.test_anonymousId_isStableAcrossInstances` fails on the iOS Simulator: SPM iOS test bundles run without a host app, so the real Keychain doesn't persist between two `SessionStore` instances. (`test_reset_generatesNewId` also passed only by accident — broken Keychain meant every read regenerated.) macOS was unaffected.

## Fix
- Extract a `KeychainBacking` protocol (internal). Production keeps the exact `SecItem*` behavior via a default `SystemKeychain`; `SessionStore` delegates read/write/delete to an injected backing. Production wiring and all call sites unchanged (defaulted parameter).
- Tests inject an `InMemoryKeychain` double (NSLock-guarded dictionary mirroring the real Keychain's shared, thread-safe semantics). The identifier logic is now tested hermetically on every platform.
- Rewrote the suite: `isStableAcrossInstances` shares one backing (the canary), `reset_generatesNewId` now tests real rotation, plus a new `persists_after_write` test asserting the write actually lands.

No public API change (all types internal to `CommentRelayCore`). No production behavior change.

## Verification
- `swift test` (macOS) → 0 failures.
- `xcodebuild test -scheme CommentRelay-Package -destination 'platform=iOS Simulator,name=iPhone 17'` → `CommentRelayCoreTests` green (the CRLBS-124 failure gone); `** TEST SUCCEEDED **`.

JIRA: https://commentrelay.atlassian.net/browse/CRLBS-124
Related: CRLBS-119/120/121/122/123 (this session's silent-failure + test-hardening work).

🤖 Generated with [Claude Code](https://claude.com/claude-code)
PR_BODY_EOF
)"
```
Paste the PR number + URL.

---

## Self-review

**1. Spec coverage:**
- `KeychainBacking` protocol — Task 1.
- `SystemKeychain` verbatim move (incl. `kSecAttrAccessibleAfterFirstUnlock` + delete-before-add) — Task 1.
- `SessionStore` defaulted-backing init, production wiring unchanged — Task 1.
- `InMemoryKeychain` double (NSLock, Sendable) — Task 2.
- 4-test matrix: hostSupplied wins, stable-across-instances (canary), reset-generates-new (fixed accidental pass), persists-after-write (new) — Task 2.
- macOS green + iOS Simulator green acceptance — Tasks 2 & 3.
- Non-goal (no SystemKeychain unit test, no host app) — respected; no task adds them.

**2. Placeholder scan:** No TBD/TODO. Every code step shows full file contents. Every command has an expected outcome. The one mechanical choice the spec left open (file placement) is resolved in the plan (single file, with rationale in File structure).

**3. Type consistency:**
- `KeychainBacking.read/write/delete(service:account:)` signatures are identical in `SystemKeychain` (Task 1), `SessionStore`'s call sites (Task 1), and `InMemoryKeychain` (Task 2).
- `SessionStore.init(service:hostSupplied:keychain:)` defined in Task 1 and used with the explicit `keychain:` argument in every Task 2 test.
- `account` constant value `"anonymousId"` unchanged; `service` passed through consistently.

**Known verification-time note (not a placeholder):** Task 3 Step 1 hard-codes the `iPhone 17` simulator; Step 1 already documents the `xcrun simctl list devices available` fallback if that exact device isn't present. The failure being fixed is platform-class (iOS Simulator without host app), not device-specific, so any modern iPhone simulator validates it.
