# SessionStore Keychain test seam (CRLBS-124)

**Date:** 2026-05-22
**Ticket:** CRLBS-124
**Status:** Design — awaiting user review before implementation plan.

## Problem

Running the SDK test suite against the iOS Simulator surfaces exactly one
failure:

```
SessionStoreTests.test_anonymousId_isStableAcrossInstances
  XCTAssertEqual failed: ("F3D7AF0B-…") is not equal to ("E2A996F1-…")
```

The same test passes on macOS. Root cause: `SessionStore` reads/writes the
anonymous identifier directly via the Security framework (`SecItem*`).
SPM iOS test bundles run without a host app, so Keychain entitlements /
access-group semantics differ — `SecItemAdd` doesn't persist in a way the
next `SecItemCopyMatching` can read back. The first `SessionStore` writes a
UUID; the second can't read it and mints a new one → the assertion fails.

The SDK code is correct in a real iOS app (proper entitlements + host
bundle). This is a test-infrastructure gap, not a production defect.

Secondary observation: `test_reset_generatesNewId` currently passes on iOS
**by accident** — with a non-functional Keychain, every `effectiveIdentifier`
read regenerates a fresh UUID, so "first ≠ second" holds even though nothing
is being persisted or reset. The test asserts the right outcome for the wrong
reason.

## Goals

- The full `CommentRelayCoreTests` suite passes on **both** macOS (`swift
  test`) and iOS Simulator (`xcodebuild test`).
- `SessionStore`'s identifier logic (host-supplied wins; anonymous id is
  stable across instances; reset rotates a persisted id) is tested
  hermetically — not skipped, and not dependent on real Keychain.
- Production behavior is byte-for-byte unchanged: the only consumer
  (`CommentRelayClient`) keeps constructing `SessionStore(service:hostSupplied:)`
  and transparently gets the real Keychain backing.

## Non-goals

- Unit-testing the real `SystemKeychain` adapter inside the SPM bundle —
  that is the very iOS-Simulator limitation we are routing around. It stays a
  thin, untested adapter whose behavior is unchanged from today and exercised
  in real apps.
- Adding an iOS test-host-app target (the heavier alternative). Out of scope.
- Changing the anonymous-id semantics, key names, or `kSecAttrAccessible`
  level.

## Locked decisions (from brainstorm)

- **Approach:** introduce an in-memory Keychain seam (a `KeychainBacking`
  protocol). Production defaults to the real `SecItem`-based impl; tests
  inject an in-memory double. Chosen over "skip on iOS Simulator" (hides the
  diagnostic, leaves the logic untested) and "host app" (overkill).

## Architecture

### Core changes (`Sources/CommentRelayCore/Internal/`)

**New protocol** `KeychainBacking` (internal, `Sendable`):

```swift
protocol KeychainBacking: Sendable {
    func read(service: String, account: String) -> String?
    func write(_ value: String, service: String, account: String)
    func delete(service: String, account: String)
}
```

**`SystemKeychain`** — the production implementation. Moves the existing
`baseQuery` / `SecItemCopyMatching` / `SecItemAdd` / `SecItemDelete` logic
verbatim behind the protocol. `kSecAttrAccessibleAfterFirstUnlock` and the
delete-before-add write semantics are preserved exactly. It holds no mutable
state, so it conforms to `Sendable` directly (a `struct` or `final class`) —
no `@unchecked` needed.

Placement: either appended to `SessionStore.swift` or a sibling
`Keychain.swift`. The plan will choose; both keep it internal to
`CommentRelayCore`.

**`SessionStore`** — gains a defaulted backing parameter; delegates the three
operations to it:

```swift
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

The private `SecItem*` methods move into `SystemKeychain`. No other behavior
changes.

**Production wiring is unchanged.** The single call site in
`CommentRelayClient` constructs `SessionStore(service:hostSupplied:)`; the
defaulted `keychain: KeychainBacking = SystemKeychain()` means that call
compiles unchanged and uses the real Keychain.

### Test changes (`Tests/CommentRelayCoreTests/`)

**`InMemoryKeychain`** — test double conforming to `KeychainBacking`:

```swift
final class InMemoryKeychain: KeychainBacking, @unchecked Sendable {
    private let lock = NSLock()
    private var store: [String: String] = [:]
    private func key(_ service: String, _ account: String) -> String { "\(service)\u{0}\(account)" }
    func read(service: String, account: String) -> String? {
        lock.lock(); defer { lock.unlock() }; return store[key(service, account)]
    }
    func write(_ value: String, service: String, account: String) {
        lock.lock(); defer { lock.unlock() }; store[key(service, account)] = value
    }
    func delete(service: String, account: String) {
        lock.lock(); defer { lock.unlock() }; store[key(service, account)] = nil
    }
}
```

`NSLock` mirrors the real Keychain's process-wide-shared, thread-safe
semantics and satisfies `Sendable`. Modeling fidelity: a single
`InMemoryKeychain` instance shared between two `SessionStore`s with the same
service+account behaves exactly like the real shared Keychain.

**`SessionStoreTests` rewrite** — every test injects a shared
`InMemoryKeychain`; nothing touches the real Keychain; identical pass on macOS
and iOS Simulator:

| Test | Behavior |
|---|---|
| `test_hostSupplied_wins` | Inject a keychain for consistency (host-supplied path never reads it). Assert `effectiveIdentifier == "host-user-1"`, `isAnonymous == false`. |
| `test_anonymousId_isStableAcrossInstances` | The canary. `a` and `b` share the SAME `InMemoryKeychain` and service. Assert `a.effectiveIdentifier == b.effectiveIdentifier`, `a.isAnonymous`. Now genuinely tests read-after-write. |
| `test_reset_generatesNewId` | Fix the accidental pass. With a working backing: first read writes id A; `resetAnonymous()` deletes then returns fresh id B; assert `A != B` — now meaningful (rotates a persisted id, not a coincidence). |
| `test_anonymousId_persists_after_write` (NEW) | Read `effectiveIdentifier` on store 1 (writes A). Construct store 2 on the same backing/service; assert it returns A **without** regenerating — directly asserts the write landed (the exact property real Keychain failed to provide on iOS). |

## Data flow

1. Production: `CommentRelayClient` → `SessionStore(service:hostSupplied:)` →
   default `SystemKeychain` → `SecItem*`. Unchanged.
2. Tests: `SessionStore(service:hostSupplied:keychain: InMemoryKeychain())` →
   dictionary. No Security framework calls.

## Error handling

No new error surface. `SystemKeychain` preserves the existing
best-effort behavior (failed `SecItemAdd`/`SecItemCopyMatching` ⇒ `read`
returns nil ⇒ caller regenerates). `InMemoryKeychain` cannot fail.

## Testing / acceptance

- `swift test` (macOS host) → `CommentRelayCoreTests` green, including the 4
  SessionStore tests.
- `xcodebuild test -scheme CommentRelay-Package -destination 'platform=iOS Simulator,name=iPhone 17'`
  → `CommentRelayCoreTests` green (the CRLBS-124 failure gone). The
  `CommentRelayUITests` bundle was already green on iOS.
- No change to total production behavior; `CommentRelayClient` and all other
  consumers compile unchanged.

## Sequencing / dependencies

- Branch: `feature/CRLBS-124-sessionstore-keychain-seam` off `develop`
  (`f92a53b`). Already created.
- No API-repo coordination. SDK-only, test-infrastructure-focused.
- No new dependencies. No public API change (`SessionStore`,
  `KeychainBacking`, `SystemKeychain` are all internal to `CommentRelayCore`).

## Open questions

None blocking. File placement of `SystemKeychain`/`KeychainBacking` (same
file vs sibling) is a mechanical choice left to the implementation plan.
