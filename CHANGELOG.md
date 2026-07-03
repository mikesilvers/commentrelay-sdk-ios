# Changelog

## Unreleased

## 1.2.4

- Feedback forms now prefill from a saved draft when opened via a preselected form id: context written by the host app through `CommentRelayClient.saveDraft(formId:fieldValues:)` is loaded into the form on open (previously the draft was written but never read into the UI). Draft values are keyed by field id and applied to text-backed fields; only non-empty values are applied. Pass the same `formId` string to `saveDraft` and to the sheet's `formId` (slug and UUID are distinct keys). The draft is host-owned — it is not auto-deleted after seeding, so persistent context re-applies on each open; call `deleteDraft(formId:)` to clear it.

## 1.2.3

- Internal design docs/specs removed from the public repository (now kept private). No API or behavior change.

## 1.1.0

- Free-tier feedback widgets now show a "Powered by CommentRelay" attribution link, suppressed on paid tiers (CRLBS-132).
