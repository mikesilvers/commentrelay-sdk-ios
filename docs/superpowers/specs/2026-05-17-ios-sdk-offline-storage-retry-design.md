# iOS SDK — Offline storage & retry for feedback submissions

**Date:** 2026-05-17
**Status:** Approved (design)
**Ticket:** CRLBS-114
**Sub-project:** SP2 of 2. SP1 = API conformance/privacy/SPM (CRLBS-113, separate spec). Independent of SP2 except both touch `CommentRelayClient`.
**Repo:** `commentrelay-sdk-ios` (branch `feature/CRLBS-114-offline-storage-retry`).

## Goal

Let users compose and submit feedback while offline (or during transient failures): persist submissions locally, present feedback forms from cached config when offline, and automatically deliver queued submissions when connectivity returns — without duplicating data or breaking the actor/concurrency model.

## Analysis basis (verified against current source)

- `CommentRelayClient` is an `actor`; `submit → uploadFiles → finalize` is a 3-step flow with no persistence between steps. `BackgroundUploadManager` tracks in-flight uploads in memory only. `DraftStore` persists *pre-submission text drafts* (debounced JSON), not submissions.
- Presigned S3 upload URLs expire in 15 min and are returned by `POST /sdk/v1/submissions`. They must never be cached; a resumed submission re-POSTs for fresh URLs.
- `finalize` is idempotent (`409 CONFLICT` already treated as success). 403 engages an existing circuit-breaker (`isEnabled`/`reset()`).
- Error taxonomy: retryable = `transport`, `rateLimited(retryAfter:)` (429), `server` (5xx); terminal = `badRequest` (400), `paymentRequired` (402), `notFound` (404), `decoding`; `forbidden` (403) = terminal + circuit-breaker.
- Config caching **already exists**: `ConfigCache` persists `Snapshot { hash, forms:[CommentRelayForm] }`; `CommentRelayField` already decodes/persists `options:[FieldOption]?` and `parentFieldId`. **Gap:** `fetchConfig` throws on offline and never falls back to the cache; there is no public accessor for the effective (cached) forms.
- No reachability monitoring exists today.
- A prior design (deferred "Plan B") approved: persistent queue, max 50 / 30-day age / FIFO, pending-count indicator, never cache presigned URLs, upload retry ×3, 429 exponential backoff to 30s.

## Decisions (confirmed with user)

1. **Queue storage:** one JSON entry per submission (no SQLite — supersedes the stale Plan B note; matches existing JSON-file persistence and the no-external-deps stance).
2. **Attachments:** persist file bytes as sidecars; enforce API caps at enqueue.
3. **Flush triggers:** `NWPathMonitor` connectivity-restored + SDK init + app-foreground + any `submit()`/`flushQueue()` call.
4. **API behavior:** `submit()` auto-queues by default; opt-out via configuration; terminal errors still throw.
5. **Resume strategy:** finalize-first — if `serverSubmissionId` exists, try `finalize` before re-POSTing (minimizes duplicates).
6. **Pending indicator:** Core observable count **and** a minimal `CommentRelayUI` badge.
7. **Offline config-availability folded into SP2** (prerequisite for offline submission UX to be meaningful).

## Architecture

### New components (`CommentRelayCore`)

- **`SubmissionQueue`** (actor, `Sources/CommentRelayCore/Internal/SubmissionQueue.swift`) — persistence, FIFO ordering, caps/eviction, lifecycle, single-flight flush. Constructed in both `CommentRelayClient.init`s alongside `configCache`/`draftStore`.
- **`Reachability`** (`Sources/CommentRelayCore/Internal/Reachability.swift`) — a `Sendable` protocol + `NWPathMonitor`-backed implementation exposing `isConnected` and an `AsyncStream<Bool>` of changes. Injectable for hermetic tests.
- **`QueuedSubmission`** (Codable, Sendable):
  - `localId: UUID`
  - `submission: CommentRelaySubmission`
  - `phase: Phase` — `needsSubmit | needsUpload | needsFinalize | done`
  - `serverSubmissionId: UUID?` (set after a successful POST)
  - `attachments: [QueuedFileRef]` — `{ fieldId, fileName, contentType, size }`
  - `attemptCount: Int`, `nextEarliestAttempt: Date?`, `createdAt: Date`, `lastError: String?`
- **On-disk layout:** `<appSupport>/CommentRelay/<fingerprint>/queue/<localId>/entry.json` + one sidecar file per attachment (`<fileName>`). Atomic writes. Presigned URLs are never written.

### Persistence rules

- Enqueue copies attachment bytes into the entry folder. Enforce API caps at enqueue: ≤10,000,000 bytes/file, ≤3 files/field, allowed MIME set (`image/jpeg|png|heic|heif|webp`, `application/pdf`, `text/plain`). Over-cap attachments → the submission is rejected with a terminal `badRequest`-style error (does not enter the queue).
- Queue caps: FIFO; max 50 entries; max age 30 days. On overflow at enqueue → evict the oldest entry (delete folder). Aged-out entries pruned at the start of each flush.
- Single source of order: directory scan sorted by `createdAt`.

## State machine & flush

A flush pass (actor-serialized; only one at a time):

1. Prune aged-out / over-cap entries.
2. For each entry in FIFO order whose `nextEarliestAttempt` ≤ now:
   - **Resume (finalize-first):** if `serverSubmissionId != nil` and `phase == needsFinalize`, call `finalize`; `409`/success → mark `done`, delete entry. If finalize fails retryably, apply backoff and continue.
   - `needsSubmit`: `POST /sdk/v1/submissions` → store `serverSubmissionId`, advance to `needsUpload` (or `needsFinalize` if no attachments), persist entry.
   - `needsUpload`: PUT each sidecar to the **fresh** presigned URLs from the just-completed POST (×3 per file); on S3 403/expiry → discard URLs, set `phase=needsSubmit` (re-POST next pass via `resubmit`). On all files done → `needsFinalize`.
   - `needsFinalize`: `finalize` (idempotent) → `done`, delete entry + sidecars.
3. Errors per entry:
   - Retryable (`transport`/429/5xx): keep entry; `attemptCount += 1`; `nextEarliestAttempt = now + backoff` where backoff = min(2^(attempt-1), 30)s; 429 uses `retryAfter` if larger. No max-attempts drop — it persists until it succeeds or ages out.
   - Terminal (`badRequest`/`paymentRequired`/`notFound`/`decoding`): mark `lastError`, remove from active queue (do not retry forever), surface via `CommentRelayLogger`. No new public "failed count" API (YAGNI); failed entries simply leave the queue and `pendingSubmissionCount` reflects only still-pending entries.
   - `forbidden` (403): engage existing circuit-breaker; **pause** the queue (retain all entries); resume automatically on `reset()` + next trigger.

## Offline config-availability (folded in)

- `fetchConfig` becomes hash-self-managing: if caller passes no hash, it reads `ConfigCache.read()?.hash` internally.
- On `current:true` (unchanged) **or** a `transport`/offline failure: return the cached forms instead of throwing. Throw only if there is no cache at all and the network failed.
- New public accessor `effectiveConfig() async -> CommentRelayConfigResponse`-equivalent returning cached-or-fresh forms, so `CommentRelayUI` can render forms offline.
- Cache invalidation stays purely hash-driven (already correct). No max-age eviction for config (YAGNI — config is small).

## Public API & configuration

- `submit(_:)` returns `enum SubmitOutcome: Sendable { case submitted(CommentRelaySubmissionReceipt); case queued(localId: UUID) }`. Terminal errors still `throw`. On no connectivity or a retryable failure with queueing enabled → persist + return `.queued`. **Documented breaking change** (pre-1.0; sample app + `CommentRelayUI` call sites updated).
- New public surface on `CommentRelayClient`:
  - `var pendingSubmissionCount: Int { get async }`
  - `func pendingSubmissionCountStream() -> AsyncStream<Int>` (drives the UI badge)
  - `func flushQueue() async` (manual trigger; also auto-called by triggers)
  - `func effectiveConfig() async throws -> CommentRelayConfigResponse` returning the `.updated(hash, forms)` case from cache when offline/unchanged, fresh when available (offline-capable forms accessor)
- `CommentRelayConfiguration` additions: `offlineQueueingEnabled: Bool = true`; optional `maxQueuedSubmissions: Int = 50`; `maxQueueAge: TimeInterval = 30 days`.

### `CommentRelayUI`

- A minimal pending-count badge (e.g., on the entry point / history affordance) bound to `pendingSubmissionCountStream()`. SwiftUI, platform-neutral (no UIKit-only API; consistent with SP1 cross-platform rules).

## Testing

- `SubmissionQueue`: enqueue/persist/load, FIFO ordering, 50-cap eviction, 30-day prune, sidecar round-trip, attachment-cap rejection.
- State machine: resume from each phase incl. crash-after-POST (finalize-first path; verify no duplicate when `serverSubmissionId` set), S3-expiry → re-POST path.
- Backoff scheduling (deterministic clock injected); 429 `Retry-After` honored; terminal vs retryable routing; 403 pause then `reset()` resume.
- `Reachability` injected via protocol; flush triggers fire on connectivity-restored/init/foreground; single-flight (no concurrent flush).
- Offline config: `fetchConfig` returns cached forms on transport failure and on `current:true`; throws only with no cache; auto-hash path.
- `CommentRelayUI` badge reflects count via `ViewInspector`/snapshot.
- Full suite stays green on the macOS host (`swift build` + `swift test`, ≥ current 148, 0 failures).

## Out of scope

- Background `URLSession` uploads that continue while the app is suspended (current foreground session retained; queue resumes on next launch/foreground). Can be a later enhancement.
- Server-side idempotency keys (API contract has none; finalize-first is the dedup mitigation).
- SP1 items (conformance/privacy/SPM/macOS platform) — CRLBS-113.
- Config max-age eviction; analytics; threading/conversation history.

## Success criteria

- Submitting offline returns `.queued`; the submission is delivered automatically (text and attachments) when connectivity returns, with no duplicate server record in the common crash-after-POST case.
- Feedback forms render offline from cached config; hash still drives refresh.
- Queue respects caps (50 / 30 days / FIFO) and the 403 pause/resume contract.
- Pending count observable in Core and shown by the UI badge.
- No regression; suite green on macOS.
