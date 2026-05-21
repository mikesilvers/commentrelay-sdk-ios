# ErrorMapper status classification & 401 handling (CRLBS-120)

**Date:** 2026-05-20
**Ticket:** CRLBS-120
**Status:** Design — awaiting user review before implementation plan.

## Problem

`ErrorMapper.map(response:data:)` enumerates 400/402/403/404/409/429 and routes
**everything else** — including 401, all other unknown 4xx, and all 5xx —
through `default: return .server(message:)`. `RetryPolicy.classify` then
treats `.server` as `.retry(nil)`, so every unenumerated status is silently
enqueued and retried forever.

For deterministic failures this is wrong:

- **HTTP 401 (auth failed)** — a bad/unprovisioned key will never succeed on
  retry. Today it queues indefinitely. `CommentRelayError` has no
  `.unauthorized` case at all, so even faithful modeling isn't possible
  without a small enum addition.
- **Other unknown 4xx** (405/410/415/422/451/…) — same fate: silently
  retried though the same request will never succeed.

5xx is the only catch-all status group that *should* retry; today it's
correct by accident but indistinguishable in the source code from the broken
4xx path.

Surfaced while root-causing CRLBS-119; explicitly scoped out of CRLBS-119/121
and tracked here.

## Goals

- 401 is surfaced (terminal) with a faithful error case and a dedicated,
  localized user-facing message.
- Unknown statuses are classified by HTTP range: **5xx retries**; everything
  else terminates.
- Public API additions are minimal, named honestly, and exhaustively switched
  (no `default` arms that would silently swallow new cases).
- No regression to existing retry/pause/terminal semantics for 400/402/403/
  404/409/429 or for `.transport`/`.decoding`/`.uploadFailed`/`.uploadUrlExpired`.

## Non-goals

- Reworking `.transport(URLError)` classification (some URLErrors are
  deterministic too — `.badURL`, `.cancelled`, etc. — but that's a separate
  rabbit hole; out of scope here).
- Changing 403's `.pause`/circuit-breaker behavior.
- Reclassifying 5xx as anything other than retry.

## Locked decisions (from brainstorm)

- **401 → terminal** (surface this submission as failed; subsequent submits
  fail independently). Not `pause` like 403; not "both."
- **Range-based catch-all**: status `>=500` → retryable; any other
  unenumerated status → terminal via a new `unexpectedStatus` case that
  preserves the actual code in the technical detail.
- **Dedicated localized unauthorized message** (new
  `crl.error.unauthorized` string), not the generic `errorGeneric`.

## Architecture

### Core (`CommentRelayCore`)

**`CommentRelayError` — add two public cases** (no behavior change to
existing cases):

```swift
case unauthorized(message: String)
case unexpectedStatus(statusCode: Int, message: String)
```

Any helper on `CommentRelayError` (e.g. `isTerminal`) that switches on cases
gets matching arms.

**`ErrorMapper.map(response:data:)`** — switch replaces the `default` bucket:

```swift
switch response.statusCode {
case 400:        .badRequest(message: …)
case 401:        .unauthorized(message: …)
case 402:        .paymentRequired(message: …)
case 403:        .forbidden(message: …)
case 404:        .notFound(message: …)
case 409:        .conflict(message: …)
case 429:        .rateLimited(retryAfter: …)
case 500..<600:  .server(message: …)                    // retryable
default:         .unexpectedStatus(statusCode: …, message: …)  // terminal
}
```

**`RetryPolicy.classify`** — add the two new cases:
- `.unauthorized` → `.terminal`
- `.unexpectedStatus` → `.terminal`
The 5xx → `.server` → `.retry(nil)` path is unchanged.

### Public model (`CommentRelaySubmissionProblem.Category`, CRLBS-121)

`Category.init(_ error: CommentRelayError)` is currently an **exhaustive**
switch with no `default` arm — we get a compile error for free once the
error enum grows. Add two matching `Category` cases and arms:

```swift
case unauthorized, unexpectedStatus
…
case .unauthorized:     self = .unauthorized
case .unexpectedStatus: self = .unexpectedStatus
```

The `Category` is `RawRepresentable<String>`, persisted on disk via
`QueuedSubmission.errorCategory`. New raw values (`"unauthorized"`,
`"unexpectedStatus"`) cannot collide with pre-existing entries (the queue
held terminal entries as `.server` etc. before CRLBS-121 anyway, and any
legacy raw value that doesn't match `Category(rawValue:)` falls through to
`.unknown` via the existing `init(token:)`).

### UI (`CommentRelayUI`)

**New localized string** in en + es-419:
- `crl.error.unauthorized` → `"Your API key isn't authorized to send feedback."`
  (en) / `"Tu clave de API no está autorizada para enviar comentarios."`
  (es-419). Exact wording subject to a final polish pass; meaning fixed.

**`Strings.swift`**:
- Add `static var errorUnauthorized: String { string("crl.error.unauthorized") }`.
- `Strings.friendlyError(_:Category)` — switch is currently exhaustive over
  all 12 categories. Add arms for the two new ones:
  - `.unauthorized → errorUnauthorized`
  - `.unexpectedStatus → errorGeneric` (no dedicated message; the technical
    detail row in `ProblemRow` already shows the real status code from
    `lastError`).

**Caller-side error messages** in `CommentRelayView.message(for:)` — this
method maps `CommentRelayError` cases to display text. Currently:
```swift
case .paymentRequired: errorPaymentRequired
case .rateLimited:     errorRateLimited
case .uploadFailed:    errorUploadFailed
default:               errorGeneric
```
Add an explicit arm for `.unauthorized → errorUnauthorized`. Leave
`.unexpectedStatus` in the `default → errorGeneric` bucket (no dedicated
copy needed). Verified safe: `CommentRelayView`'s `progressFailed` path
already shows this and the user has Try-again / Remove available via the
CRLBS-121 problems section if they want recourse.

### Tests

**New `ErrorMapperTests`** — table-driven sweep over a representative status
matrix asserting the exact mapped case:

| status | expected error |
|---|---|
| 400 | `.badRequest` |
| 401 | `.unauthorized` |
| 402 | `.paymentRequired` |
| 403 | `.forbidden` |
| 404 | `.notFound` |
| 405 | `.unexpectedStatus(405, …)` |
| 409 | `.conflict` |
| 410 | `.unexpectedStatus(410, …)` |
| 415 | `.unexpectedStatus(415, …)` |
| 418 | `.unexpectedStatus(418, …)` |
| 422 | `.unexpectedStatus(422, …)` |
| 429 (with `Retry-After: 5`) | `.rateLimited(retryAfter: 5)` |
| 451 | `.unexpectedStatus(451, …)` |
| 500 | `.server` |
| 502 | `.server` |
| 503 | `.server` |
| 504 | `.server` |
| 599 | `.server` |
| 600 | `.unexpectedStatus(600, …)` *(edge — outside 5xx range)* |

Includes APIErrorEnvelope decoding test (existing behavior — covered if not
already).

**New `RetryPolicyClassificationTests`** — for each `CommentRelayError`
case, assert the exact `RetryDecision`. Covers existing cases (regression
guard) plus the two new ones (`.terminal` for both).

**Existing suites** — `swift test` must remain at 225/0 plus the new tests
green.

## Data flow

1. Server returns HTTP 401 → `APIClient.send` builds an `HTTPURLResponse`,
   hands it to `ErrorMapper.map` → `.unauthorized(message: …)`.
2. `CommentRelayClient.submit` catches `CommentRelayError`, calls
   `RetryPolicy.classify` → `.terminal` → `throw err`. The caller path is
   identical to the existing 400/404 terminal path.
3. (If the submission was already queued and is re-attempted by `flushQueue`:)
   the `.terminal` branch (CRLBS-121) marks the queue entry failed, writes
   `errorCategory = "unauthorized"`, retains it for the History UI.
4. `submissionProblems()` returns the entry with `Category.unauthorized`;
   `ProblemRow` renders `Strings.friendlyError(.unauthorized) →
   errorUnauthorized` as the friendly summary plus the raw lastError as
   technical detail.

For 5xx: unchanged from today (retry with backoff).

For unknown 4xx (e.g. a future server-side 422 from a new validation rule):
caller sees a terminal `.unexpectedStatus(422, "<message from server>")`;
problem row shows `errorGeneric` plus the status code in the technical
detail row.

## Sequencing / dependencies

- Branch: `feature/CRLBS-120-error-mapper-status-classification` off
  `develop` (HEAD `f6c55c1`, CRLBS-121 merge). Already created.
- No coordination needed with the API repo. The mapping change is purely
  client-side reclassification of statuses the API can already produce.
- Sample app's default key (`crk_test_sample`) likely 401s against prod
  today and queues silently — after this lands those become visible
  "Your API key isn't authorized" Problem rows. This is the intended
  effect; flagging so the change isn't surprising during smoke-testing.

## Open questions

None blocking. Wording of the en/es `crl.error.unauthorized` string is the
only item that may want a final polish pass; the meaning is fixed.
