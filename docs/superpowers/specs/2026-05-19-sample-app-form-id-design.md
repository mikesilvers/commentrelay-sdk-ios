# Sample app: optional Form ID to show a single form

## Problem
The sample app always opens the feedback sheet on the form picker. The SDK
already supports jumping straight to one form via
`commentRelaySheet(...formId:formTitle:)` → `FormPreselect`, but the sample
never passes it, so the single-form path can't be exercised.

## Fix (sample app only — no SDK change)
In `Example/.../ContentView.swift`:
- Add `@State private var formIdentifier = ""`.
- Add an optional input row: "Form ID (optional — shows only that form)".
- Pass `formId: formIdentifier.isEmpty ? nil : formIdentifier` to
  `.commentRelaySheet(...)`.

When set to a picker-visible form's id, the sheet opens directly on that form;
empty preserves today's picker behavior; an unknown/hidden id falls back to the
picker (existing `FormPreselect` semantics).

## Verification
`swift build`; run the sample, enter a known form id, tap Send feedback,
confirm it opens that single form and skips the picker; clear it and confirm
the picker returns.
