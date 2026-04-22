# History detail — show submitted field values

**Status:** notes, deferred. Pick up when prioritised.

## Gap

`HistoryDetailView` today renders only the form title, submission date, and developer notes. The user's actual answers (textbox values, true_false toggles, ratings, uploaded files) are not displayed — because they aren't returned by the API.

`/sdk/v1/history` currently returns metadata only:

- `commentrelay-api/src/feedback/sdk-history.ts:12-22` — query selects `s.id, s.form_id, s.status, s.created_at, fc.title`. No field values.
- `commentrelay-api/docs/openapi.yaml:555-587` — `HistorySubmission` schema: `id`, `form_id`, `form_title`, `status`, `created_at`, `notes[]`. No submission field data.

The iOS SDK can only render what's on the wire.

## Options

### 1. Fatten the list response
Add `fields: [{ label, value, field_type, attachments? }]` (shape TBD) to each `HistorySubmission` in the `/sdk/v1/history` response.

- ➕ One endpoint, one iOS call, minimal plumbing.
- ➖ Every list fetch carries every submission's full body — including file URLs — even for users viewing only the list. Fine today (50-item cap) but scales poorly as the cap grows or as file uploads get common.

### 2. Add a detail endpoint (recommended)
New `GET /sdk/v1/history/{submissionId}` returning the full submission:

- All fields with labels and values.
- Presigned GET URLs for any uploaded photo/attachment files (needs the API to mint fresh ones — original upload URLs are write-only and expire).
- Same auth as existing SDK endpoints (`x-api-key` + `x-user-identifier`, project-scoped, user-scoped).

iOS flow: list view uses existing `fetchHistory()`; tapping a row calls `fetchHistoryDetail(submissionId:)` which lazy-loads the detail view.

- ➕ List stays lean; detail costs one extra round-trip only when opened.
- ➕ Matches REST conventions and the web dashboard's likely pattern.
- ➖ One more endpoint + handler + OpenAPI entry on the API side.

## Recommendation

**Option 2.** Clean separation and scales.

## Cross-repo sequence when we pick this up

1. **commentrelay-api**
   - Design the detail response shape (spec in `docs/superpowers/specs/`): per-field `{ field_id, label, field_type, value }`, with attachments as an array of `{ field_id, file_name, content_type, size, download_url (presigned GET) }`.
   - Add `GET /sdk/v1/history/{submissionId}` handler (auth: same custom authorizer as other SDK routes; reject with 404 if submission's `project_id != context.projectId` or `user_identifier != x-user-identifier`).
   - Update `openapi.yaml` with new path + `HistorySubmissionDetail` schema.
   - Update `userGuides/sdk-integration-guide.md` and `docs/sdk-use.md`.
   - PR + merge on API develop.
2. **commentrelay-sdk-ios**
   - Add `CommentRelayHistoryDetail` model (or extend `CommentRelayHistoryEntry` depending on chosen shape).
   - Add `CommentRelayClient.fetchHistoryDetail(submissionId:)`.
   - Teach `HistoryDetailView` to lazy-load and render each field by type:
     - text-ish fields (`textbox`, `email`, `phone`, `numeric`) → label + value.
     - `true_false` → label + Yes/No.
     - `smiley_rating` / `color_scale` → label + the selected position (reuse the existing `SmileyShape` / `ColorScale` renderers if we want the visual, otherwise a plain "3 / 5" works).
     - `photo` / `attachment` → label + thumbnail grid fetching the presigned download URLs. Fall back to a filename + download link if inline image load fails.
     - `informational` → skip (no user value).
   - Honour the same `parent_field_id` conditional-display rule so hidden children don't render with blank values.
3. **commentrelay-sdk-android** / **-web** — mirror with equivalent changes once iOS is green. (Not iOS's problem, just noting the ripple.)

## Open questions for later

- Does the API include answers for fields that were hidden at submit time (parent `true_false` toggled off)? Probably not worth sending — they weren't captured. Confirm with API team.
- Photo/attachment URLs: TTL on the presigned GET. 60s is too short if a user scrolls; 24h is probably right. API team call.
- Do we surface `form_id` or a form-version pointer so the detail view can handle the case where the form definition has been edited after the submission? Low priority — for v1, render only what's in the submission payload; don't reconcile with live form.

## Related references

- API handler: `commentrelay-api/src/feedback/sdk-history.ts`
- API schema: `commentrelay-api/docs/openapi.yaml` (`HistorySubmission` at line 555)
- iOS detail view: `Sources/CommentRelayUI/Screens/HistoryDetailView.swift`
- iOS model: `Sources/CommentRelayCore/Public/Models/CommentRelayHistory.swift`
