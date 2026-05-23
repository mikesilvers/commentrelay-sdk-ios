# Schema-versioned config cache (CRLBS-128) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a schema version to the SDK config cache so an install upgraded across a cached-model change (e.g. the CRLBS-127 `client_form_id` field) discards its stale cache and refetches, instead of serving slug-less forms forever.

**Architecture:** SDK-only. `ConfigCache.Snapshot` gains a required `schemaVersion`; `read()` returns nil unless it equals `currentSchemaVersion` (old caches lack the field → decode fails → nil → full refetch); `write()` stamps it. Self-heals on next launch with network.

**Tech Stack:** Swift 6 / SwiftPM, XCTest.

**Spec:** `docs/superpowers/specs/2026-05-23-config-cache-schema-version-design.md`

**Base:** `feature/CRLBS-128-config-cache-schema-version` off `commentrelay-sdk-ios` `develop` (created).

**Verification:** `swift build`, `swift test` from repo root. Final acceptance: `xcodebuild test -scheme CommentRelay-Package -destination 'platform=iOS Simulator,name=iPhone 17'` (watch for the known flaky leaked-network-task teardown from CRLBS-124 — a clean re-run is the truth).

---

## File structure

- `Sources/CommentRelayCore/Internal/ConfigCache.swift` (modify) — `schemaVersion` on `Snapshot`, `currentSchemaVersion` constant, guard in `read()`, stamp in `write()`.
- `Tests/CommentRelayCoreTests/ConfigCacheTests.swift` (modify) — add discard-on-missing/wrong-version tests; existing round-trip tests must stay green.

No API, web, or other source change.

---

## Task 0: Verify base

**Files:** none (gate).

- [ ] **Step 1: Branch + clean tree**
```bash
cd /Users/mikesilvers/repos/commentrelay-sdk/commentrelay-sdk-ios
git branch --show-current   # feature/CRLBS-128-config-cache-schema-version
git status --short          # only the spec/plan (committed next) — otherwise clean
```

- [ ] **Step 2: Build + test baseline**
```bash
swift build 2>&1 | tail -3        # clean
swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1   # record count, 0 failures
```

---

## Task 1: Schema-versioned cache (TDD)

**Files:**
- Modify: `Sources/CommentRelayCore/Internal/ConfigCache.swift`
- Modify: `Tests/CommentRelayCoreTests/ConfigCacheTests.swift`

- [ ] **Step 1: Write the failing tests**

Append these two tests inside `final class ConfigCacheTests` (before its closing brace) in `Tests/CommentRelayCoreTests/ConfigCacheTests.swift`:
```swift
    func test_discardsCache_withoutSchemaVersion() async throws {
        // Simulates a cache written by a pre-CRLBS-128 build (no schemaVersion).
        let legacy = Data(#"{"hash":"old","forms":[]}"#.utf8)
        try legacy.write(to: tempDir.appendingPathComponent("config.json"), options: .atomic)
        let snap = await ConfigCache(directory: tempDir).read()
        XCTAssertNil(snap, "a cache without a schemaVersion must be discarded")
    }

    func test_discardsCache_withWrongSchemaVersion() async throws {
        let future = Data(#"{"schemaVersion":999,"hash":"x","forms":[]}"#.utf8)
        try future.write(to: tempDir.appendingPathComponent("config.json"), options: .atomic)
        let snap = await ConfigCache(directory: tempDir).read()
        XCTAssertNil(snap, "a cache with a mismatched schemaVersion must be discarded")
    }
```

- [ ] **Step 2: Run — expect failure**
```bash
swift test --filter ConfigCacheTests 2>&1 | tail -20
```
Expected: the two new tests fail — current `read()` decodes `{hash, forms}` with no version check, so the legacy/`999` snapshots are returned (non-nil) instead of discarded.

- [ ] **Step 3: Implement the schema version**

In `Sources/CommentRelayCore/Internal/ConfigCache.swift`:

Replace the `Snapshot` struct:
```swift
    struct Snapshot: Codable, Sendable {
        let hash: String
        let forms: [CommentRelayForm]
    }
```
with (add `schemaVersion` + the version constant right after):
```swift
    struct Snapshot: Codable, Sendable {
        let schemaVersion: Int
        let hash: String
        let forms: [CommentRelayForm]
    }

    /// Bump whenever the cached form shape changes (e.g. a new CommentRelayForm
    /// field). Existing installs then discard their stale cache and refetch,
    /// instead of serving forms that lack the new field. (CRLBS-128.)
    private static let currentSchemaVersion = 1
```

Replace `read()`:
```swift
    func read() -> Snapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }
```
with:
```swift
    func read() -> Snapshot? {
        guard let data = try? Data(contentsOf: fileURL),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data),
              snap.schemaVersion == Self.currentSchemaVersion else { return nil }
        return snap
    }
```

Replace the first line of `write(hash:forms:)`:
```swift
        let snap = Snapshot(hash: hash, forms: forms)
```
with:
```swift
        let snap = Snapshot(schemaVersion: Self.currentSchemaVersion, hash: hash, forms: forms)
```
Leave `init`, `defaultDirectory`, `clear`, and the file path unchanged.

- [ ] **Step 4: Run — expect pass**
```bash
swift test --filter ConfigCacheTests 2>&1 | tail -12
```
Expected: all `ConfigCacheTests` pass — the two new discard tests AND the pre-existing `test_writeThenReadRoundTrip` / `test_survivesNewInstance` / `test_emptyOnFirstRead` (write now stamps the version; read accepts it).

- [ ] **Step 5: Full build + suite**
```bash
swift build 2>&1 | tail -3                                   # clean
swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1  # 0 failures (baseline + 2)
```

- [ ] **Step 6: Commit**
```bash
git add Sources/CommentRelayCore/Internal/ConfigCache.swift \
        Tests/CommentRelayCoreTests/ConfigCacheTests.swift
git commit -m "fix(CRLBS-128): version the config cache; discard stale snapshots

ConfigCache.Snapshot gains a schemaVersion; read() discards a snapshot whose
version is missing (old build) or mismatched, forcing a fresh config fetch.
Fixes upgraded installs serving slug-less forms cached before CRLBS-127.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Verify + push + PR

**Files:** none.

- [ ] **Step 1: Full checks**
```bash
swift build 2>&1 | tail -3                       # clean
swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1   # 0 failures
git status --porcelain                            # clean
```

- [ ] **Step 2: iOS acceptance**
```bash
xcodebuild test -scheme CommentRelay-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **`. If a leaked-network-task teardown failure appears (known flaky from CRLBS-124), re-run once; a clean run is the truth. Do not accept a false failure or mask a real one.

- [ ] **Step 3: Push + open PR**
```bash
git push -u origin feature/CRLBS-128-config-cache-schema-version 2>&1 | tail -2
bb pr create -s feature/CRLBS-128-config-cache-schema-version -d develop \
  -t "fix(CRLBS-128): schema-version the config cache (discard stale snapshots)" \
  -b "$(cat <<'PR_BODY_EOF'
Implements docs/superpowers/specs/2026-05-23-config-cache-schema-version-design.md.

## Problem
After CRLBS-127 shipped, the slug deep-link still failed against production until
the app was deleted. ConfigCache.Snapshot had no schema version: a cache written
by the pre-CRLBS-127 build held forms without client_form_id, and because the
project config_hash was unchanged the server returned .current, so fetchConfig
kept serving those stale, slug-less cached forms. Confirmed: clearing the app
cache fixes it. Any future cached-model field addition has the same problem.

## Fix (SDK-only)
- ConfigCache.Snapshot gains a required schemaVersion + a currentSchemaVersion
  constant.
- read() returns nil unless the snapshot's version matches (old caches lack the
  field -> decode fails -> nil; mismatched versions -> nil), forcing a fresh
  config fetch that rewrites a current cache (with client_form_id).
- write() stamps the version. Bump the constant when the cached form shape changes.

Self-heals on next launch with network; no reinstall needed.

## Tests
ConfigCacheTests: old/unversioned cache discarded, wrong-version discarded,
round-trip + cross-instance still work. swift test green; xcodebuild iOS
acceptance TEST SUCCEEDED. No API/web change.

JIRA: https://commentrelay.atlassian.net/browse/CRLBS-128

Generated with Claude Code
PR_BODY_EOF
)" 2>&1 | tail -4
```
Paste the PR number + URL.

---

## Self-review

**1. Spec coverage:** schemaVersion on Snapshot + constant (Task 1 Step 3); read() discards missing/mismatched (Step 3 + tests Step 1); write() stamps (Step 3); self-heal via refetch (covered by discard → nil → fetchConfig sends no hash). README/API untouched (out of scope, correct).

**2. Placeholder scan:** None. Every code step has full code; commands have expected output.

**3. Type consistency:** `Snapshot(schemaVersion:hash:forms:)` is used consistently in `write` and matches the struct's stored properties; `currentSchemaVersion` (Int, = 1) is referenced in both `read()` guard and `write()` stamp. The legacy-cache test writes raw JSON to `tempDir/config.json`, matching `ConfigCache`'s `directory.appendingPathComponent("config.json")` path.
