# formId deep-link by client_form_id slug, opening hidden-from-picker forms (CRLBS-127)

**Date:** 2026-05-23
**Ticket:** CRLBS-127
**Status:** Design — awaiting user review before implementation plan.
**Repo:** `commentrelay-sdk-ios` (SDK only — no API change).

## Problem

A production integrator presented feedback with `formId: "check-how-they-feel"`
— a `client_form_id` **slug** — for a project, and **nothing displayed**. The
form is configured hidden from the picker (`show_in_picker: false`). Expected:
passing that identifier opens that one form directly.

Two independent SDK defects combine to cause this:

1. **The slug is never matched.** `CommentRelayForm` does not decode the API's
   `client_form_id` field at all, and `FormPreselect.match` compares the
   supplied `formId` only against the form's UUID (`$0.id == id`). A slug can
   never equal a UUID, so preselect always misses and falls through to the
   picker.
2. **Hidden forms are excluded from preselect.** `FormPreselect.match` filters
   to picker-visible forms (`isPickerVisible == isActive && showInPicker`)
   *before* matching, so a form hidden from the picker can't be opened even when
   targeted explicitly by id. This was the deliberate behavior of **CRLBS-115**.

Because the form is the only one referenced and it's hidden, the picker
fallback is empty — the user sees nothing.

The API side is healthy: `GET /sdk/v1/config` returns `200`, includes
`client_form_id` for every form, and only returns **active** forms
(`is_active = TRUE`). Verified in code (`src/config/sdk-config.ts`) and prod
CloudWatch. **No API change is needed.**

## Goals

- `formId:` accepts the **`client_form_id` slug** as well as the UUID, and opens
  the matching form.
- An explicit `formId` (UUID or slug) opens that exact form **even when it is
  hidden from the picker** (`show_in_picker: false`) — a deep link. This is the
  intent of CRLBS-14 ("set the identifier that allows the SDK access to that
  form only").

## Non-goals

- **No change to `formTitle` preselect.** A title match is fuzzy and must not
  surface a hidden form — it keeps the picker-visible-only rule from CRLBS-115.
- **No change to the picker list.** `FormPickerView` still shows only
  picker-visible forms.
- **Inactive forms are never surfaced.** The API doesn't return them, and the
  matcher additionally guards on `isActive`.
- No API change. No new endpoint, no fetch-by-slug request parameter — the SDK
  already receives all forms (with their slugs) via `getConfig`.

## Relationship to CRLBS-115 (explicit partial reversal)

CRLBS-115 deliberately restricted **all** preselect (id and title) to
picker-visible forms, to stop a preselect from surfacing a hidden/inactive form.
This spec **partially reverses that for the id path only**: an explicit
`formId`/slug is an intentional, unambiguous request for one specific form, so
the anti-"accidental surfacing" concern does not apply. The title path — which
can fuzzily match — retains CRLBS-115's rule unchanged.

## Architecture

### Model — `Sources/CommentRelayCore/Public/Models/CommentRelayForm.swift`

Add an optional slug property and its coding key:

```swift
public let clientFormId: String?
// ...
enum CodingKeys: String, CodingKey {
    case id, title
    case clientFormId = "client_form_id"
    // ...existing keys...
}
```

`clientFormId` is `String?`, so Swift's synthesized `Decodable` treats a missing
`client_form_id` key as `nil` — older/sample config payloads that omit it still
decode. `isPickerVisible` is unchanged (still `isActive && showInPicker`); it
remains the source of truth for the picker list and the title-preselect path.

### Matcher — `Sources/CommentRelayUI/Shared/FormPreselect.swift`

Split the two cases so id and title have different visibility rules:

```swift
func match(in forms: [CommentRelayForm]) -> CommentRelayForm? {
    switch self {
    case .id(let id):
        // CRLBS-127: an explicit formId is a deep link — match the form's UUID
        // OR its client_form_id slug, and open it even when hidden from the
        // picker. Still never surface an inactive form. Partially reverses
        // CRLBS-115 for the id path only.
        return forms.first { $0.isActive && ($0.id == id || $0.clientFormId == id) }
    case .title(let title):
        // CRLBS-115 preserved: a fuzzy title must not surface a hidden form.
        let needle = title.lowercased()
        return forms.filter { $0.isPickerVisible }.first { $0.title.lowercased() == needle }
    }
}
```

The `CommentRelayView.loadForms` flow is unchanged: a non-match still logs the
existing `"requested form not found in config; falling back to picker"` warning
and shows the picker. After this change, a slug/UUID hit no longer mis-falls to
the picker.

### Docs — `README.md`

Update the preselect note. Replace the blanket statement that a not-in-picker
form is never surfaced via `formId`/`formTitle`. New wording:

- `formId:` accepts the form's UUID **or** its `client_form_id` slug, and opens
  that exact form **even if it is hidden from the picker** (deep link).
- `formTitle:` only matches a form that is shown in the picker.
- An **inactive** form is never surfaced by either.

## Data flow

`app passes formId (slug or UUID) → CommentRelayView → fetchConfig → GET
/sdk/v1/config (200, active forms incl. client_form_id) → FormPreselect.match
finds the active form by id-or-slug regardless of show_in_picker → form opens.`

## Error handling

Unchanged. No match → warning + picker fallback. Network/decode errors →
existing `progressFailed` path.

## Testing

- **`FormPreselectTests`** (extend the suite added in CRLBS-115):
  - `formId` equal to a form's `client_form_id` slug → returns that form.
  - `formId` equal to a UUID → still returns that form (regression).
  - `formId` (slug or UUID) for an active form with `show_in_picker: false` →
    returns it (the new deep-link behavior).
  - `formId` for an **inactive** form → returns `nil` (never surfaced).
  - `formTitle` for a `show_in_picker: false` form → returns `nil` (CRLBS-115
    preserved).
  - A hidden same-title form does not shadow a visible one (CRLBS-115
    regression).
- **`CommentRelayForm` decoding:** decodes `client_form_id` when present; yields
  `nil` when the key is absent.
- Full SDK suite green (`swift test`, and `xcodebuild test` for the iOS
  destination).

## Sequencing / dependencies

- Branch `feature/CRLBS-127-formid-slug-deeplink` off `develop` (created).
- SDK-only. No API or web change. No new dependencies.
- Independent of CRLBS-118 (release prep). Ships on its own `develop` PR.

## Open questions

None. The one design decision (deep-link visibility scope) is resolved:
reverse CRLBS-115 for `formId`/slug only; `formTitle` unchanged.
