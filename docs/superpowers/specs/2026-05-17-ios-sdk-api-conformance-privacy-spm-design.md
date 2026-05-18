# iOS SDK — API conformance, macOS platform, Apple privacy manifest & SPM packaging

**Date:** 2026-05-17
**Status:** Approved (design)
**Sub-project:** SP1 of 2. SP2 = offline storage & retry (separate spec).
**Primary repo:** `commentrelay-sdk-ios`. Contains a delineated prerequisite workstream in `commentrelay-api`.

## Goal

Bring the iOS SDK into verified conformance with the CommentRelay SDK API, make macOS a first-class reported platform, and satisfy Apple's third-party-SDK privacy requirements for SPM source distribution.

## Audit basis (verified against API source, not assumed)

- **C1 — NOT a defect.** `CommentRelaySubmissionReceipt` uses plain camelCase properties with no `CodingKeys`. The documented submissions/finalize response IS camelCase (`submissionId`, `hasUploads`, `uploadUrls`, `fieldId`, `fileName`, `uploadUrl`). Default `Codable` matches. No change.
- **C2 — NOT an SDK defect.** SDK uses `response_limit_window_minutes`. API source emits `_minutes` (89×) vs `_days` (30×); the SDK matches API code. The API *docs* (`openapi.yaml`, `docs/sdk-use.md`) are stale → fixed in the API workstream, not the SDK.
- **C3 — GENUINE defect.** Rating fields submit `{"position":N}`; the contract requires `{"position":N,"label":"<label>"}`.
- **Platform defect — GENUINE.** `CommentRelayView.swift:56` and `:105` hardcode `platform: .ios`; macOS apps misreport as `ios`. API enum has no `macos`.
- **Privacy — GAP.** No `PrivacyInfo.xcprivacy` anywhere. Verified: SDK uses **no** required-reason APIs (no file-timestamp, disk-space, system-boot-time, UserDefaults; Keychain `SecItem*` is not a required-reason category).

## Decisions (confirmed with user)

1. **Approach A** — one SP1 spec, two sequenced workstreams.
2. **macOS platform:** add `macos` to the API enum **first** (deploy gate), then SDK sends `.macos`.
3. **API-side scope:** add `macos` to the platform enum AND fix the stale docs (`openapi.yaml`, `docs/sdk-use.md`) from `response_limit_window_days` → `response_limit_window_minutes`, sweeping those two docs for the same drift.
4. **Privacy stance:** data is **linked to the user's identity** and **NOT used for tracking**; purpose **App Functionality**.
5. **Per-target manifests:** `CommentRelayCore` and `CommentRelayUI` each get their own `PrivacyInfo.xcprivacy` (the products are independently adoptable).
6. **Spec location:** this single file in `commentrelay-sdk-ios`; the API workstream is a prerequisite section here, no separate API-repo spec.

## Workstream API — `commentrelay-api` (prerequisite; must merge + deploy before SDK §B platform switch)

- Add `macos` to the SDK submission `platform` enum/validator (accepted set becomes `ios|android|web|server|other|macos`).
- Fix docs to match emitted code: in `docs/openapi.yaml` and `docs/sdk-use.md`, replace `response_limit_window_days` with `response_limit_window_minutes`; sweep both files for any other field-name drift the SDK depends on and correct to match API code.
- Extend/Add a validator unit test asserting `macos` is accepted. Existing API unit + integration suites stay green.

## Workstream SDK — `commentrelay-sdk-ios`

### A. Conformance fix (C3 — rating payload)
- File: `Sources/CommentRelayUI/Screens/FeedbackFormViewModel.swift` (~line 67).
- For `.smileyRating` / `.colorScale`: resolve the selected option from `field.options` by `position`; encode `{"position":N,"label":"<label>"}` using `JSONEncoder` (not string interpolation, for correct escaping). If no matching option/label exists, fall back to position-only (defensive, logged).

### B. Platform detection (gated on Workstream API deploy)
- `Sources/CommentRelayCore/Public/Models/Platform.swift`: add `case macos`.
- Add `Platform.current`: `#if os(iOS)` → `.ios`; `#elseif os(macOS)` → `.macos`; `#else` → `.other`. (iPadOS resolves to `.ios`, correct.)
- `Sources/CommentRelayUI/Screens/CommentRelayView.swift:56` and `:105`: replace literal `.ios` with `Platform.current`.

### C. Apple privacy manifests (per target)
Two `PrivacyInfo.xcprivacy` plists. Both: `NSPrivacyTracking=false`, `NSPrivacyTrackingDomains=[]`, `NSPrivacyAccessedAPITypes=[]` (verified none used). `NSPrivacyCollectedDataTypes` — every entry linked to user, not tracking, purpose App Functionality:

- **`Sources/CommentRelayCore/PrivacyInfo.xcprivacy`** (Core transmits data to the API):
  - User ID (`user_identifier`)
  - Other Data (device model, OS version, app version, locale, `session_id`)
  - Other User Content (feedback field values transmitted in submissions)
  - Email Address, Phone Number (only when `contact_details` provided)
- **`Sources/CommentRelayUI/PrivacyInfo.xcprivacy`** (UI collects user input):
  - Other User Content (feedback text the user types)
  - Photos or Videos (photo/attachment field captures)
  - Email Address, Phone Number (contact capture fields)

### D. SPM packaging (manifest must ship as a resource)
- `Package.swift`: `CommentRelayCore` target — add `resources: [.copy("PrivacyInfo.xcprivacy")]` (target currently declares no resources).
- `Package.swift`: `CommentRelayUI` target — add `.copy("PrivacyInfo.xcprivacy")` to its existing `resources` array (keep it `.copy`, NOT inside `.process("Resources")`, so the plist is not transformed).
- README: document the privacy manifest's presence and that source SPM distribution needs no binary signature (record that XCFramework/binary signing & notarization are N/A for source SPM).

### E. Testing
- New unit tests: rating payload encoding (label present; label-absent fallback); `Platform.current` value per compiled OS.
- Full SDK suite stays green on macOS host (`swift build` + `swift test`, currently 148 passing — must remain ≥148, 0 failures).
- Manual/CI check: built `.bundle`s contain `PrivacyInfo.xcprivacy` for each target.

## Explicitly out of scope (so they are NOT "fixed")
- C1 (camelCase receipt is correct — do not add CodingKeys).
- Changing the API-emitted `_minutes` value (correct; only API *docs* change).
- Mac Catalyst-specific platform nuance (native macOS → `.macos`; Catalyst falls under `os(iOS)` → `.ios`, accepted).
- SP2: offline storage & retry — separate spec/plan/implementation.
- Any UI redesign, new endpoints, auth changes, retry/backoff (SP2).

## Success criteria
- API: `macos` accepted by the submission validator; `openapi.yaml` + `sdk-use.md` say `response_limit_window_minutes`; API suites green.
- SDK: rating submissions include `position`+`label`; macOS builds report `platform=macos` (post API deploy); both targets ship a valid `PrivacyInfo.xcprivacy` as an SPM resource; suite ≥148 green on macOS.
- No regression to conforming areas (paths, auth headers, error mapping, field-type enum, history/anonymous handling, file upload).

## Sequencing & dependency
SDK §A, §C, §D, §E and the `Platform` enum/`Platform.current` addition (§B code) can proceed immediately. The two `CommentRelayView` call-site switches to emit `.macos` must not ship until Workstream API is merged AND deployed (otherwise macOS submissions 400). Plan must encode this gate.
