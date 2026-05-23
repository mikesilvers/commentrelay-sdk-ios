# Submission problem visibility in History (queued & failed, with retry/remove)

**Date:** 2026-05-19
**Ticket:** CRLBS-121
**Status:** Approved — proceeding to implementation plan.

## Problem

The History screen is populated solely from the server (`GET /sdk/v1/history`),
so it only ever lists *delivered* submissions. Submissions that are queued for
retry, or that failed terminally, are invisible to the end-user:

- Queued entries: only a numeric pending badge, no detail, no error.
- Terminal failures: deleted from the queue and only logged — no trace at all.

Discovered via CRLBS-119 (macOS submissions silently 500'd, queued, and were
reported as success). Users need to *see* when a submission has a problem,
understand why, and act on it.

## Goals

- Surface **both** still-queued (retrying) and **permanently-failed**
  submissions inside the existing History screen.
- Each problem entry expands to show a **friendly summary + technical detail**.
- Each problem entry offers **Try again** and **Remove**.
- Honest: a retry of a still-broken submission must not show false success.

## Non-goals / out of scope

- Changing the server history payload or API.
- Changing retry/backoff policy or `ErrorMapper` classification (the latent
  `default → .server` 401 issue noted in CRLBS-119 stays a separate concern).
- Surfacing problems anywhere other than the History screen.

## Locked decisions

- Scope: **queued + permanently-failed** (Core retains terminal failures
  instead of delete-and-log).
- Expanded content: **friendly summary + technical detail**.
- Actions: **Try again** and **Remove** per entry.
- Placement: a problems section **above** delivered history (option A from
  brainstorming), one screen.

## Architecture

### Core (`CommentRelayCore`)

**Retain terminal failures.** `QueuedSubmission` gains `var failedAt: Date?`
and `var lastAttemptAt: Date?` (set whenever an attempt fails — there is no
existing last-attempt timestamp; `nextEarliestAttempt` is the *next* time, not
the last).
The `flushQueue` `.terminal` branch stops calling `submissionQueue.delete(...)`;
instead it sets `failedAt = now`, persists, and continues. The flush loop skips
entries with `failedAt != nil` (they are not retried automatically). Existing
`maxEntries` / `maxAge` caps prune oldest entries (failed included) so retained
failures stay bounded.

**Structured error persistence.** Today only `lastError: String` (raw
`"\(err)"`) is stored. Add a stored error category/code (derived from
`CommentRelayError` at enqueue/fail time) alongside the existing raw detail
string, so a friendly message can be derived without re-parsing text. Existing
`lastError` string is retained as the technical detail.

**Pending count semantics unchanged.** `pendingSubmissionCount` (and its
stream) count **only retrying** entries (`failedAt == nil`). The toolbar badge
keeps meaning "will retry"; failed entries do not inflate it.

**Public API (4):**

- `func submissionProblems() async -> [CommentRelaySubmissionProblem]`
- `func retrySubmission(id: UUID) async`
- `func deleteProblemSubmission(id: UUID) async`
- `pendingSubmissionCount` / `pendingSubmissionCountStream()` — unchanged
  signature, semantics clarified above.

`public struct CommentRelaySubmissionProblem: Sendable, Equatable, Identifiable`:

| field | type | notes |
|---|---|---|
| `id` | `UUID` | the queue entry `localId` |
| `formId` | `String` | from the queued `CommentRelaySubmission` |
| `createdAt` | `Date` | when first enqueued |
| `kind` | `enum { case queuedRetrying, failed }` | `failed` ⇔ `failedAt != nil` |
| `friendlyMessage` | `String` | mapped from the stored error category |
| `technicalDetail` | `String` | raw `lastError` text |
| `attemptCount` | `Int` | existing field |
| `lastAttemptAt` | `Date?` | new `QueuedSubmission` field, set on each failed attempt |

**Friendly mapping shared.** The `CommentRelayError → Strings.error*`
mapping currently private in `CommentRelayView.message(for:)` is lifted into
Core (a small internal mapper) so both `submissionProblems()` and the existing
UI path use one source of truth.

**`retrySubmission(id:)`:** clears `failedAt`, resets `nextEarliestAttempt`
(and resets backoff so the entry is immediately eligible), then triggers
`flushQueue()`. Works for `.failed` (un-fails) and `.queuedRetrying` (retry
now, bypassing backoff). If the underlying cause is still terminal, the entry
re-fails and reappears as `.failed` with an incremented `attemptCount` — no
false success.

**`deleteProblemSubmission(id:)`:** reuses the queue's existing
`delete(localId:)` (entry + attachment sidecars), then broadcasts the updated
pending count.

Both action APIs are idempotent: a no-op if the entry already flushed/was
removed between view and tap.

### UI (`CommentRelayUI`)

**`HistoryLoader`** (private in `CommentRelayView.swift`): additionally calls
`submissionProblems()` and passes the result to `HistoryListView`. Local
problems load independently of the server fetch.

**`HistoryListView`** gains an optional `problems: [CommentRelaySubmissionProblem]`
input. Renders a problems section **above** the existing delivered list;
server rows render unchanged. Reuses `EmptyStateView` when both are empty.

**`ProblemRow.swift`** (new, focused file): title (form title resolved from
cached config when available, else a generic label) + date + a **status chip**
— `Queued — will retry` (orange, clock) or `Failed to send` (red,
exclamation), reusing the existing badge styling vocabulary. Tapping toggles a
`DisclosureGroup` that reveals: friendly summary, then technical detail (raw
`lastError`, `attempt N`, `last tried <relative>`), then:

- **Try again** — calls `retrySubmission(id:)`; brief in-row spinner. On
  success the row disappears (delivered); on re-failure it stays / flips to
  `Failed` with incremented attempt count.
- **Remove** — destructive; `confirmationDialog` then
  `deleteProblemSubmission(id:)`.

**Offline resilience (improvement).** Today `HistoryLoader` replaces the whole
screen with `ErrorBanner` if the server fetch throws. New behavior: local
problems always render; if the *server* history fetch fails, problems still
show with a small non-blocking notice instead of a full-screen error — offline
is exactly when queued problems matter most.

**Live refresh.** After Try again / Remove, the view re-queries
`submissionProblems()`; the existing pending-count stream keeps the toolbar
badge correct.

**Strings (en + es-419):** status chips, friendly messages, `Try again`,
`Remove`, remove-confirmation title/body, `attempt` / `last tried` labels.

## Data flow

1. User opens History → `HistoryLoader` concurrently: `fetchHistory()`
   (server) and `submissionProblems()` (local).
2. `HistoryListView` renders problems section (top) + delivered list (below).
3. Expand → inline detail. Try again → `retrySubmission` → `flushQueue` →
   re-query problems + badge stream updates. Remove → confirm →
   `deleteProblemSubmission` → re-query.
4. Server fetch failure → problems still shown + non-blocking notice.

## Error handling

- All four Core APIs are safe/no-op on a missing entry id.
- Retry never reports success it didn't achieve; a terminal cause re-fails
  visibly.
- Caps prevent unbounded retained-failure growth.

## Testing

**Core (unit):** terminal failure retained (not deleted) and marked `failed`;
flush skips `failedAt != nil`; `pendingSubmissionCount` excludes failed;
`submissionProblems()` returns expected kinds/fields; `retrySubmission`
re-eligibles & re-fails on still-terminal; `deleteProblemSubmission` removes
entry + sidecars; caps prune retained failures; friendly mapper parity with
the prior `message(for:)`.

**UI (ViewInspector):** problem row shows correct chip; expand reveals
technical detail + both buttons; Try again invokes retry; Remove invokes
delete only after confirmation; server-fetch-fails path still shows problems
(no full-screen error); empty state when no problems and no history.

## Sequencing / dependencies

- Builds on CRLBS-119 (`feature/CRLBS-119-sdk-queued-not-delivered`, PR #17):
  that PR adds `.queuedSaved` + the pure route mapping. This feature is
  additive and should land **after** PR #17 to avoid conflicting edits in
  `CommentRelayView.swift` / Strings; the implementation plan will pin the
  base accordingly.
- Tracked as CRLBS-121; branch `feature/CRLBS-121-history-problem-visibility`.

## Open questions

None blocking. Form-title resolution for local entries is best-effort
(cached config or generic label); acceptable for v1.
