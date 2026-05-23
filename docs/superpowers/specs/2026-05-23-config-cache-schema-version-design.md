# Schema-versioned config cache (CRLBS-128)

**Date:** 2026-05-23
**Ticket:** CRLBS-128
**Status:** Design — approved; spec for the record.
**Repo:** `commentrelay-sdk-ios` (SDK only).

## Problem

CRLBS-127 made `formId:` open a form by its `client_form_id` slug, with passing
tests. But against production (`crk_live_`) the slug deep-link still failed —
until the app was deleted. Confirmed: clearing the app's on-disk cache fixes it.

`ConfigCache` persists `Snapshot { hash, forms: [CommentRelayForm] }` to
`config.json` and has **no schema version**. The pre-CRLBS-127 build wrote
snapshots whose forms lacked `client_form_id` (the old model didn't decode it),
along with the project's `config_hash`. The CRLBS-127 build reads that cache,
sends the cached hash, and — because the project config is unchanged — the
server replies `.current`. On `.current`, `fetchConfig` returns the **cached**
forms (`CommentRelayClient.swift:156-157`), i.e. the stale, slug-less ones, so
`clientFormId` is `nil` at runtime and the slug can't match → picker fallback.
Nothing invalidates the cache when the model gains a field, so an upgraded
install serves stale forms until the cache is cleared or the project config
changes.

This is general: **any** future cached-model field addition is invisible to
existing installs. CRLBS-127 surfaced it.

## Goals

- A cache written by an older SDK whose cached shape differs is **discarded**,
  so the SDK fetches fresh config (which includes the new fields) instead of
  serving stale data.
- Self-healing: no user action (reinstall) required; the next launch with
  network rewrites a current cache.

## Non-goals

- No change to the matcher (CRLBS-127 is correct), the API, or the wire format.
- No cache encryption / migration of old data — discard-and-refetch is enough
  (config is a cheap GET).

## Locked decision

**Version the cache by a schema version, not the SDK version.** A schema version
invalidates only when the cached format actually changes, preserving the offline
cache across ordinary SDK upgrades. Keying to the SDK version would discard the
cache (and offline render) on every upgrade even when nothing changed.

## Architecture (`Sources/CommentRelayCore/Internal/ConfigCache.swift`)

- Add `schemaVersion: Int` to `Snapshot` (required) and a
  `private static let currentSchemaVersion = 1` constant.
- `read()`: decode, then return the snapshot **only if**
  `snap.schemaVersion == Self.currentSchemaVersion`; otherwise `nil`.
  - Old caches predate the field → decode fails (`keyNotFound`) → `try?` → `nil`.
  - Future format changes → bump the constant; mismatched snapshots → `nil`.
- `write(hash:forms:)`: stamp `schemaVersion: Self.currentSchemaVersion`.
- Document next to the constant: **bump when the cached form shape changes.**

No change to `read()`/`write()` signatures, `fetchConfig`, or callers.

## Data flow (self-heal)

`stale/old cache → read() returns nil → fetchConfig sends no hash → server
returns full config (.updated) → fresh forms (with client_form_id) written with
schemaVersion=1 → slug matches → form opens.`

## Testing (`Tests/CommentRelayCoreTests/ConfigCacheTests.swift`)

- **Old/unversioned cache discarded:** write a raw `config.json` containing
  `{"hash":...,"forms":[...]}` with **no** `schemaVersion` into the cache dir;
  `read()` returns `nil`.
- **Wrong schema version discarded:** raw `config.json` with
  `"schemaVersion": 999` → `read()` returns `nil`.
- **Round-trip still works:** existing `write` → `read` returns the snapshot
  (now carrying the current version) — the existing tests must stay green.

## Deploy / sequencing

- Branch `feature/CRLBS-128-config-cache-schema-version` off `develop` (created).
- SDK-only. Ships on its own `develop` PR. Reaches users with the next iOS
  SemVer tag (alongside CRLBS-120/121/123/124/127). On that upgrade, each
  install's old cache is discarded once and the slug deep-link starts working.

## Open questions

None.
