# iOS SDK — 403 after a successful POST must not orphan the server record

**Date:** 2026-05-19
**Status:** Approved (design)
**Ticket:** CRLBS-116
**Repo:** `commentrelay-sdk-ios` (branch `feature/CRLBS-116-pause-after-post-orphan`, off `develop`).
**Found during:** CRLBS-114 PR #6 review (pre-existing gap, split out).

## Problem

In `CommentRelayClient.submit(_:attachments:)`, after `postSubmission` succeeds (the server now holds a record `receipt.submissionId`), if the subsequent `uploadFiles`/`finalize` throws a `.forbidden` (403) — classified `.pause` by `RetryPolicy` — the post-POST `catch` does `case .terminal, .pause: throw err` and does **not** enqueue. The circuit-breaker is engaged (`finalize`/`uploadFiles` call `disable()` internally on `.forbidden`), but no queue entry exists, so the unfinalized server record has **no local resume path**: even after `reset()` and connectivity, that submission is never finalized (orphaned server-side until any TTL cleanup).

A `.retry` failure at the same point already (post CRLBS-114, commit `6af5ae3`) enqueues with `serverSubmissionId` + `needsFinalize`/`needsUpload`, so finalize-first resumes it. The `.pause` path is the remaining gap. Pure `.terminal` after a successful POST (e.g. 400/decoding) is out of scope — non-recoverable, acceptable to leave to server TTL.

## Decision (confirmed with user)

Post-POST `.pause`: **throw + enqueue** (respecting `offlineQueueingEnabled`). The caller still sees the 403 (auth failures must surface, not be hidden behind `.queued`; the circuit-breaker is already engaged), but the in-flight record is persisted so it resumes via the existing 403 pause/resume contract.

## Scope

- **Change:** `CommentRelayClient.submit(_:attachments:)` post-POST `catch` block only.
- **Unchanged:** the pre-POST `catch` (no server record exists yet — nothing to orphan; still `throw err`, no enqueue); `advance`/finalize-first; `SubmissionQueue` (the `enqueue(serverSubmissionId:startingPhase:)` capability already exists from CRLBS-114); `RetryPolicy`; circuit-breaker; flush triggers.

## Design

Replace the post-POST `catch`'s `case .terminal, .pause: throw err` with:

```swift
case .terminal:
    throw err
case .pause:
    if configuration.offlineQueueingEnabled {
        _ = try await submissionQueue.enqueue(
            submission, attachments: attachments,
            serverSubmissionId: receipt.submissionId,
            startingPhase: receipt.hasUploads ? .needsUpload : .needsFinalize)
        await broadcastPendingCount()
    }
    throw err
case .retry:
    // unchanged (CRLBS-114 6af5ae3)
```

Notes:
- The `.pause` branch **enqueues then rethrows** — `submit()` does not return on this path; the caller observes the thrown `.forbidden` exactly as today. The only change is that a recoverable queue entry now exists.
- `enqueue` may itself throw (cap/sanitization — attachments were already accepted for the POST, so this is not expected here, but `try` is correct and any such throw propagates, matching the existing `.retry` branch's behavior).
- Resume path is the **existing, unchanged** contract: while `!isEnabled` (post-403), `flushQueue` early-returns retaining entries. After the caller `reset()`s and any flush trigger fires (`flushQueue`, connectivity, init, foreground), `advance`'s finalize-first guard (`serverSubmissionId != nil && phase == .needsFinalize`) finalizes the existing server record — **no re-POST, no duplicate** for the no-attachment path. The attachment path (`.needsUpload`) re-POSTs for fresh presigned URLs per the pre-existing, spec-documented limitation, but is no longer orphaned.

## Testing (TDD)

Add to the existing client/flush test suite (reuse the established `URLProtocolStub` + actor-counter patterns):

1. **No-attachment, post-POST 403 → throw + recoverable entry:** POST `/sdk/v1/submissions` → 200 (fixed `submissionId`); finalize → 403. Assert `submit(sub, attachments: [])` **throws** `.forbidden`. Assert a queued entry exists with `serverSubmissionId == that id` and `phase == .needsFinalize`. Then `client.reset()`, switch finalize → 200, `await flushQueue()`; assert pending count → 0 **and** the `/sdk/v1/submissions` POST was hit **exactly once** total (no re-POST → no duplicate). Must fail pre-fix (no entry enqueued).
2. **Attachment, post-POST 403:** POST 200 → `uploadFiles` 403 → `submit` throws `.forbidden`; queued entry exists with `serverSubmissionId` set and `phase == .needsUpload`.
3. **Queueing disabled:** `offlineQueueingEnabled == false`, post-POST 403 → throws `.forbidden`, **no** entry enqueued (unchanged).
4. **Pre-POST 403 unchanged:** POST itself → 403 → throws `.forbidden`, no entry (unchanged).
5. Existing `.retry` post-POST behavior and full suite remain green (regression).

Determinism: no bare-sleep gating; bounded waits / explicit signals consistent with the existing flush tests.

## Success criteria

- A 403 after a successful POST leaves a recoverable queued entry (correct `serverSubmissionId` + phase) while still throwing `.forbidden`.
- After `reset()` + a flush trigger, the record is finalized with **no duplicate server record** (no-attachment path verified by exactly-once POST assertion).
- `offlineQueueingEnabled == false` and pre-POST 403 behavior unchanged.
- Full SDK `swift test` suite green on the macOS host, 0 failures.

## Out of scope

- The attachment `.needsUpload` re-POST-for-fresh-presigned-URLs duplicate window (pre-existing, spec-documented limitation; CRLBS-114).
- Pure `.terminal`-after-POST orphan (non-recoverable; server TTL).
- Any change to `RetryPolicy`, `advance`, `SubmissionQueue`, or the circuit-breaker/trigger machinery.
