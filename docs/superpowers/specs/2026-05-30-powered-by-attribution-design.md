# Powered-by Attribution on Free-Tier Feedback Widget — Design

- **Ticket:** CRLBS-132 (Story) — "Add 'Powered by CommentRelay' link to free-tier feedback widget"
- **Epic:** CRLBS-131 — Marketing: 90-Day Zero-Budget Growth Plan
- **Date:** 2026-05-30
- **Status:** Approved (design); implementation pending plan
- **Scope of this spec:** iOS SDK only. Android/Web are tracked separately (CRLBS-151 / CRLBS-152).

## Goal

Render a subtle, themed "Powered by CommentRelay" link at the bottom of the iOS
feedback widget for **free-tier** projects only. Tapping it opens a backend
click-tracking redirect that 302s to commentrelay.com with UTM params, so
signups originating from the loop are attributable. The link is suppressed on
paid tiers.

Acceptance (from the ticket):
- Badge visible on Free tier, hidden on paid tiers.
- Click lands on commentrelay.com with a tracked source param.

## Key constraint that shapes the design

The SDK has **no tier signal today**. `CommentRelayConfigResponse` only models
`.current` / `.updated(hash:forms:)`, and `CommentRelayForm` carries no
plan/tier/branding field. The only SDK↔server channel relevant here is
`GET /sdk/v1/config`. Therefore the free-vs-paid decision **must** come from the
backend over the config endpoint. All tier logic and click tracking stay
server-side; the SDK stays "dumb."

## Backend contract (owned by sibling stories, not this spec)

These are **backend** changes, filed as separate CRLBS stories per the
shared-repo convention:

- **CRLBS-149** — add two fields to the `GET /sdk/v1/config` response.
- **CRLBS-150** — add the `/r/powered-by` click-tracking redirect endpoint.

The config response gains two fields at the **top level of the envelope**,
present on **both** the unchanged (`"current": true`) and the updated responses:

```jsonc
{
  "current": false,
  "hash": "…",
  "forms": [ … ],
  "show_attribution": true,                  // backend computes from tier; false on paid
  "attribution_url": "https://api.commentrelay.com/r/powered-by?p=<project>&utm_source=…"
}
```

- `show_attribution` (bool) — true for Free tier, false for paid.
- `attribution_url` (string, nullable) — the full redirect URL, already carrying
  the per-project source/UTM params. Null/omitted when `show_attribution` is false.

**Why top-level and on every response:** attribution state is project-level, not
form-level. If it rode only on `.updated` responses (keyed by the forms hash), a
project that upgrades to paid could keep showing the badge until its forms
happen to change. Putting both fields on every config response keeps attribution
state fresh and decoupled from the forms hash.

**Why the backend supplies the full `attribution_url`:** redirect host, campaign,
and per-project source params stay server-side and can be tuned by marketing
without shipping a new SDK. The SDK never constructs the URL.

## iOS SDK changes (this story)

### 1. Decode (CommentRelayCore)
Extend the config envelope decode in
`Sources/CommentRelayCore/Public/Models/CommentRelayForm.swift`
(where `CommentRelayConfigResponse` + its `Envelope` live):

- Add `showAttribution: Bool` and `attributionURL: URL?` to the decoded result.
- `Envelope` decodes `show_attribution` and `attribution_url`.
- **Defaults when absent:** `showAttribution = false`, `attributionURL = nil`
  (safe / forward-compatible — the SDK can ship before the backend and renders
  nothing until the flag arrives).
- These values must be carried on **both** the current and updated outcomes so a
  cache-hit (`.current`) response still conveys the latest attribution state.
  The exact shape (e.g. promoting the enum to carry an associated
  `Attribution` value, or returning attribution alongside the enum) is an
  implementation-plan decision; the requirement is that consumers can read
  `(showAttribution, attributionURL)` for any config response.

### 2. Thread (CommentRelayCore → CommentRelayUI)
Surface `(showAttribution, attributionURL)` from the client's config load
through to the screen that hosts the form (`CommentRelayView`), which already
owns form loading, and pass them into `FeedbackFormView`.

### 3. Render (CommentRelayUI)
- New view `PoweredByFooter` in `Sources/CommentRelayUI/`.
  - Caption-sized, secondary foreground, centered; matches existing styling and
    reads `@Environment(\.commentRelayTheme)` for accent.
  - Wrapped in a SwiftUI `Link` (or `@Environment(\.openURL)`) targeting
    `attributionURL`. This is the first URL-opening in the UI module.
  - Localized label via the existing `Strings` mechanism.
- Inserted in `FeedbackFormView.body` directly below the submit button, inside
  the existing `VStack`.
- **Gating:** rendered only when `showAttribution == true && attributionURL != nil`;
  otherwise nothing is added to the view tree.

## Data flow

```
GET /sdk/v1/config
  → Envelope decode (show_attribution, attribution_url)
  → client exposes (showAttribution, attributionURL)
  → CommentRelayView passes them into FeedbackFormView
  → PoweredByFooter renders (free) or is omitted (paid / absent)
  → tap → opens attributionURL → backend /r/powered-by logs + 302 → commentrelay.com
```

## Testing (TDD)

- **Decoding** (CommentRelayCoreTests):
  - envelope with `show_attribution: true` + valid `attribution_url` → `(true, url)`
  - envelope with `show_attribution: false` → `(false, nil)`
  - envelope with both fields absent → `(false, nil)` (default)
  - both `current` and `updated` responses convey the values
- **UI gating** (CommentRelayUITests):
  - footer present when `showAttribution && url != nil`
  - footer absent when `showAttribution == false`
  - footer absent when `showAttribution == true` but `url == nil`
  - footer link target equals `attributionURL`

## Out of scope / non-goals

- Backend tier→flag mapping and the redirect endpoint (CRLBS-149 / CRLBS-150).
- Android and Web widgets (CRLBS-151 / CRLBS-152).
- Client-side click analytics beyond opening the backend redirect URL.

## Docs

- README: note in the configuration/behavior section that free-tier widgets
  display a "Powered by CommentRelay" link.
- CHANGELOG entry under the next unreleased version.

## Dependencies & sequencing

The iOS SDK can be implemented and merged against this agreed contract before
the backend ships, because the safe default (hidden when absent) makes it inert
until `show_attribution`/`attribution_url` start arriving. End-to-end behavior
(badge visible on free tier, tracked clicks) requires CRLBS-149 and CRLBS-150.
