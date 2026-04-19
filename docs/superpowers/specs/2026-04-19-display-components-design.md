# CommentRelay iOS SDK — display components

**Date:** 2026-04-19
**Status:** Draft (pending user review)
**Scope:** Public component surface for rendering the full CommentRelay feedback flow on iOS/macOS, including the business-logic layer that backs it.

## Cross-platform note

The CommentRelay SDK will also be delivered for Android and web. This spec is iOS-first, but the module boundaries, component names, error taxonomy, and behavioral contracts are chosen to translate cleanly:

- `CommentRelayCore` → Kotlin module (Android), TypeScript package (web).
- `CommentRelayUI` → Jetpack Compose module (Android), React component package (web).
- Field renderers, draft persistence, and background upload behavior are platform-specific in implementation; the section headers below are intentionally reusable for the Android and web spec documents.

Platform-specific caveats are called out inline.

## Constraints & choices (confirmed with user)

- **Platforms:** iOS 18+ and macOS 15+ (bumped from the scaffolding spec's iOS 17 / macOS 14).
- **Swift tools version:** 5.9 (unchanged from scaffolding; open to bumping to 6.0 if strict concurrency is desired).
- **Scope:** Full feedback flow (category picker → form → upload progress → thank-you → history) plus launcher helpers.
- **Integration model:** Both a self-contained entry view and individually exposed screens for composition.
- **User identity:** Hybrid — host may supply a `userIdentifier`; otherwise the SDK persists an anonymous UUID in the Keychain.
- **Visual style:** Native-adaptive with a small `CommentRelayTheme` (4 tokens). Deeper customization (style protocols for views) is documented as future work, not shipped v1.
- **Launchers:** SwiftUI view modifier + pre-styled button. No floating overlay in v1.
- **Accessibility + localization:** Full accessibility (VoiceOver labels, Dynamic Type, sufficient contrast). Ship with English and Latin American Spanish (`es-419`). Expose `CommentRelayLocalization.register(locale:bundle:)` so integrators can add more locales.
- **Resilience:** Form drafts persist to disk; uploads run through a `URLSession` background configuration and survive sheet dismissal / app backgrounding.
- **Form layout:** Single scrollable screen per category in v1. A wizard container is future work.
- **Module layout:** Two SPM library products — `CommentRelayCore` (no SwiftUI) and `CommentRelayUI` (depends on Core).

## Architecture

```
commentrelay-sdk-ios/
├── Package.swift                      # two library products + two test targets
├── Sources/
│   ├── CommentRelayCore/
│   │   ├── Public/                    # CommentRelayClient, Configuration,
│   │   │                              # models, CommentRelayError, Localization
│   │   └── Internal/                  # APIClient, ConfigCache, SessionStore,
│   │                                  # DraftStore, BackgroundUploadManager,
│   │                                  # ErrorMapper, LocalizationBundle
│   └── CommentRelayUI/
│       ├── Launchers/                 # .commentRelaySheet, CommentRelayButton
│       ├── Screens/                   # CommentRelayView + composable screens
│       ├── Fields/                    # one view per field type + FieldRenderer
│       ├── Shared/                    # Theme, banner, empty state, loading
│       └── Resources/
│           ├── en.lproj/Localizable.strings
│           └── es-419.lproj/Localizable.strings
└── Tests/
    ├── CommentRelayCoreTests/         # unit, MockURLProtocol-driven
    └── CommentRelayUITests/           # snapshot + interaction + a11y audit
```

**Library boundary rationale.** The Core/UI split enforces the public/internal line at the target level (not by convention), lets integrators who build their own UI ship a smaller binary without SwiftUI, and mirrors the Android (core + compose) and web (core + React) product layouts that will follow.

**Dependencies.** Core: Foundation + URLSession + Security (Keychain). UI: Core + SwiftUI + PhotosUI. No third-party runtime dependencies. Test dependencies: [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) and [ViewInspector](https://github.com/nalexn/ViewInspector) on the UI test target only.

## Component inventory

### CommentRelayCore

**Public API.**

- `CommentRelayClient` — async facade. Methods:
  - `ping() async throws -> Bool` (existing)
  - `fetchConfig(cachedHash: String?) async throws -> CommentRelayConfigResult`
  - `submit(_ submission: CommentRelaySubmission) async throws -> CommentRelaySubmissionReceipt`
  - `finalize(submissionId: UUID) async throws`
  - `fetchHistory() async throws -> CommentRelayHistory`
  - `reset()` — clears degraded/403 state after an API-key rotation
  - `isEnabled: Bool` — `false` after a terminal 403 until `reset()` is called
- `CommentRelayConfiguration` — init-time settings: `baseURL`, `apiKey`, optional `userIdentifier`, optional `locale` override. App metadata (`os_version`, `device_model`, `app_version`, `sdk_version`) is auto-populated by Core from `UIDevice` / `ProcessInfo` / `Bundle.main` / `CommentRelay.version`; each value is individually overridable on the configuration if the host needs custom behavior.
- `CommentRelayLocalization` — `register(locale:bundle:)` for integrator-supplied locales.

**Public models.**

- `CommentRelayCategory`, `CommentRelayField`, `FieldType` (10 cases: `textbox`, `trueFalse`, `numeric`, `photo`, `attachment`, `informational`, `email`, `phone`, `smileyRating`, `colorScale`), `FieldOption`.
- `CommentRelaySubmission` (request), `CommentRelaySubmissionReceipt` (response with `submissionId` + presigned uploads), `CommentRelayHistory`, `CommentRelayHistoryEntry`, `DeveloperNote`.
- `ContactPreference` (`none`, `email`, `text`, `phoneCall`), `Platform` (fixed to `.ios` at build time for this package).
- `CommentRelayError` — see error handling section.

**Internal infrastructure.**

- `APIClient` — URLSession wrapper; injects `x-api-key` and `x-user-identifier`; decodes responses; maps HTTP errors through `ErrorMapper`.
- `ConfigCache` — serializes categories + hash to `Application Support/CommentRelay/config.json`. No TTL; the server-driven hash governs refresh.
- `SessionStore` — resolves effective identifier: host-supplied wins, otherwise a UUID persisted in the Keychain under `com.commentrelay.sdk.anonymousId`. Provides `reset()` to regenerate.
- `DraftStore` — JSON files under `Application Support/CommentRelay/drafts/<category-id>.json`, debounced 500 ms on write. Deleted on successful submit.
- `BackgroundUploadManager` — `URLSession` configured with `.background(withIdentifier:)`. Tracks per-file state in a small SQLite file (or a simple JSON state file — see open question). Finalizes the submission when all files reach `.complete`. Re-requests presigned URLs via `submit` if the resume delta exceeds the 15-minute window.
- `ErrorMapper` — HTTP status + body → `CommentRelayError` case.
- `LocalizationBundle` — string lookup order: integrator-registered bundle → host `Bundle.main` → `CommentRelayUI` module bundle.

### CommentRelayUI

**Launchers.**

- `View.commentRelaySheet(isPresented: Binding<Bool>, configuration: CommentRelayConfiguration)` — view modifier.
- `CommentRelayButton(configuration:) { /* label */ }` — pre-styled button that owns its own sheet state.

**Container.**

- `CommentRelayView(configuration:)` — drop-in default entry. Owns an internal `NavigationStack`: category picker → form → progress → thank-you. History reachable via a nav-bar history button. Dismisses itself via the host's environment presentation.

**Composable screens (public).**

- `CategoryPickerView` — filtered to `show_in_picker == true`.
- `FeedbackFormView` — single scrollable screen; iterates fields; renders each via the matching `FieldRenderer`. Owns draft save/restore and `ContactPreferenceSection`. Submit button gates on required fields.
- `SubmissionProgressView` — per-file upload progress with retry affordances on failure.
- `ThankYouView` — post-submission confirmation. Offers "View history" when not anonymous.
- `HistoryListView` — up to 50 past submissions, newest first, filtered to `status == complete`. Shows tailored empty states for anonymous users vs empty-but-identified users.
- `HistoryDetailView` — one submission with its `DeveloperNote[]` (only `visible_to_customer == true`).
- `DraftRestorePrompt` — modal shown on entering a form when a draft exists.

**Field renderers (public).**

One view per `FieldType`, all conforming to a `FieldRenderer` protocol that exposes a common `value` binding plus validation output:

- `TextboxFieldView` (max 10,000 chars, enforced via `TextEditor` + counter)
- `TrueFalseFieldView` (`Toggle`)
- `NumericFieldView` (`TextField` with `.number` keyboard type / decimal on macOS)
- `PhotoFieldView` — uses `PhotosPicker`; enforces max 3 files and `image/jpeg|png|heic|heif|webp`
- `AttachmentFieldView` — uses `.fileImporter`; enforces max 3 files and `application/pdf | text/plain`
- `InformationalFieldView` — read-only, rendered via `Text` with basic Markdown
- `EmailFieldView` (`TextField` with `.emailAddress` keyboard + regex validation)
- `PhoneFieldView` (`TextField` with `.phonePad` + format validation)
- `SmileyRatingFieldView` — renders the API-provided SVG per option (loaded via `SVGKit`-free path: `UIImage`/`NSImage` from SVG data is not native; v1 embeds a minimal SVG → `Image` helper that accepts the 5 well-formed SVGs the API returns)
- `ColorScaleFieldView` — 10 color swatches using admin-configured hex stops

`FieldRenderer` is a public protocol so integrators composing their own form can reach renderers directly or swap one.

**Shared UI.**

- `CommentRelayTheme` — v1 tokens: `accentColor`, `cornerRadius`, `primaryButtonStyle`, `destructiveButtonStyle`. Injected via SwiftUI `.environment(\.commentRelayTheme, ...)`. Defaults adapt to light/dark and system accent.
- `ContactPreferenceSection` — shared form block. Shows `contact_details` only when the preference is not `.none`.
- `ErrorBanner` — dismissible inline surface for recoverable errors.
- `EmptyStateView` — reusable for empty categories / empty history / disabled SDK.
- `LoadingView` — reusable spinner with optional label.

## Data flow

**Happy path:**

1. Host calls `fetchConfig(cachedHash:)` at app launch (or the UI triggers it lazily). `ConfigCache` supplies the prior hash.
2. Server returns `{current: true}` or a fresh payload; `ConfigCache` overwrites on change.
3. Host opens the feedback sheet via a launcher. `CommentRelayView` reads `ConfigCache` (shows `LoadingView` if empty on first run).
4. `CategoryPickerView` lists eligible categories; tap navigates to `FeedbackFormView`.
5. `FeedbackFormView` checks `DraftStore` for an existing draft on the category; if present, `DraftRestorePrompt` offers to resume.
6. Field changes debounce-save the draft. `ContactPreferenceSection` captures follow-up preferences.
7. Submit → `CommentRelayClient.submit` → receives `submissionId` + presigned upload URLs → `BackgroundUploadManager` takes over → navigate to `SubmissionProgressView`. Draft is deleted.
8. `BackgroundUploadManager` PUTs each file to its presigned URL. If a URL is past the 15-minute window on resume, the manager re-submits to fetch fresh URLs.
9. On all-complete, manager calls `finalize(submissionId:)`. `SubmissionProgressView` transitions to `ThankYouView`.
10. User may tap "View history" → `HistoryListView` → `HistoryDetailView`.

**Identifier resolution** happens once per `CommentRelayView` session. Host-supplied `userIdentifier` wins over the Keychain-persisted anonymous UUID.

**Config freshness.** The server drives refresh via the hash. Clients can call `fetchConfig(cachedHash:)` whenever they want; the response is cheap when the hash matches.

## Error handling

`CommentRelayError` is a public enum covering both the documented API error codes and SDK-local cases:

```swift
public enum CommentRelayError: Error {
    case badRequest(message: String)
    case paymentRequired(message: String)
    case forbidden(message: String)
    case notFound(message: String)
    case conflict(message: String)
    case rateLimited(retryAfter: TimeInterval?)
    case server(message: String)
    case transport(URLError)
    case decoding(Error)
    case uploadFailed(submissionId: UUID, fileName: String, underlying: Error)
    case uploadUrlExpired(submissionId: UUID)
}
```

**Per-surface behavior:**

| Error | Where surfaced | Behavior |
|---|---|---|
| `badRequest` | Submit / upload | Inline field error when `message` maps to a field; otherwise `ErrorBanner` with retry |
| `paymentRequired` | Submit | `ErrorBanner` with "Feedback is temporarily unavailable. Please try again later." No retry button |
| `forbidden` | Any call | `isEnabled` flips to `false`; all subsequent calls short-circuit; host can hide launchers. `reset()` restores after key rotation |
| `notFound` | Category selection | Remove category from cached config and retry; fall back to empty state if none remain |
| `conflict` (response limit) | Submit | Inline message on category row; category disabled for re-entry |
| `conflict` (already finalized) | Upload manager | Treated as idempotent success |
| `rateLimited` | Any call | Automatic exponential backoff honoring `retryAfter`, 3 attempts, before `ErrorBanner` |
| `server` | Any call | `ErrorBanner` with retry. Upload manager retries twice |
| `transport` | Any call | `ErrorBanner` with retry. Background uploads use `URLSession`'s native retry |
| `decoding` | Any call | `ErrorBanner` with generic "Something went wrong"; underlying error logged, not shown |
| `uploadFailed` | SubmissionProgressView | Per-file retry button; submission stays `pending` |
| `uploadUrlExpired` | Upload manager | Re-submit to refresh presigned URLs; transparent to the user unless the re-submit fails |

**Circuit-breaker for 403.** `isEnabled` stays `false` for the rest of the process lifetime until `reset()` is called.

**Logging.** Errors flow through a `CommentRelayLogger` protocol; default implementation uses `os.Logger` (subsystem `com.commentrelay.sdk`). Host apps can inject their own.

**Not in v1.** No retrying submissions after app kill (draft persistence covers the human side), no crash reporting, no `NSNotification` error stream.

## Testing

### CommentRelayCoreTests

Unit tests only, built on the existing `MockURLProtocol` helper.

- `APIClient` — header injection; each HTTP status → correct `CommentRelayError` case; `Retry-After` parsing for 429.
- `ConfigCache` — round-trip across process restarts (temporary directory), cache-hit skip, cache-miss overwrite.
- `SessionStore` — host-supplied wins over Keychain UUID; UUID stable across calls; `reset()` regenerates.
- `DraftStore` — save/load round-trip, 500 ms debounce coalescing, deletion on submit.
- `ErrorMapper` — full HTTP-status table.
- `BackgroundUploadManager` — tested via an `UploadTransport` protocol seam. Covers happy path, 15-min expiry → re-submit, partial-failure retention, single finalize.
- `CommentRelayClient` — facade-level coverage of `ping`, `fetchConfig` with and without cached hash, `submit` → `finalize`, `fetchHistory` for identified and anonymous users.

### CommentRelayUITests

- **Snapshot tests** per field renderer: 10 types × (light / dark) × (en / es-419) × 3 Dynamic Type sizes (`xSmall`, `large`, `accessibility3`) via `swift-snapshot-testing`. ~120 snapshots accepted as the cost of catching the SDK's most-changed surface.
- **Interaction tests** via `ViewInspector`:
  - Draft restore prompt appears iff a draft exists for the category.
  - Contact-preference details field visible only when preference ≠ `.none`.
  - Submit button disabled while required fields are empty.
  - `CategoryPickerView` filters to `show_in_picker == true`.
  - 403 flips `isEnabled` and hides launchers.
- **Localization tests** — `en` and `es-419` resolve from `Bundle.module`; registered bundle overrides SDK bundle; missing key falls back to the key string without crashing.
- **Accessibility audit** — each field renderer exposes a non-empty `accessibilityLabel`; ratings expose `accessibilityValue`; informational fields are marked `isStaticText`. Run via XCTest.

### Sample app coverage

The existing `CommentRelaySample` in `Example/` gains a second screen that walks the full flow against the local dev stack (`http://localhost:3000`). Manual check during PR review; not automated.

### Not in v1

No live-backend integration tests, no XCUITest suite, no performance benchmarks. The mock-based coverage is sufficient for the component surface.

## Explicitly deferred

- Style protocols / deep UI customization beyond the 4 theme tokens.
- Wizard-style multi-page form container (`FeedbackWizardContainer`).
- Floating trigger overlay (Instabug/Shake-style).
- Built-in translations beyond English and `es-419` (integrator-supplied via `register(locale:bundle:)` is supported).
- XCUITest, live-backend integration tests, crash reporting.
- Web of dependencies (SVGKit, Markdown libraries, analytics clients). v1 stays dependency-free at runtime.

## Cross-platform considerations (informational)

- **Android:** `CommentRelayCore` maps to a Kotlin/coroutines module (Retrofit or bare `OkHttp` + `kotlinx.serialization`); `CommentRelayUI` maps to a Jetpack Compose module. Background uploads use `WorkManager`. Keychain → `EncryptedSharedPreferences`. Draft store → app-private storage.
- **Web:** `CommentRelayCore` maps to a TypeScript package (fetch + zod); `CommentRelayUI` maps to a React component package. Background uploads are not portable — on tab close the in-flight upload queue is lost. Draft persistence uses `localStorage` or `IndexedDB`. Document the caveat.
- **Error taxonomy** is identical across platforms; each language expresses it in its idiomatic form (Swift enum, Kotlin sealed class, TypeScript tagged union).
- **Section headers in this spec** are intentionally reusable for the Android and web design documents that will follow.

## Client lifetime

v1 assumes one active `CommentRelayClient` per process, created from one `CommentRelayConfiguration` at host startup and reused everywhere (launchers, container, composable screens). All Core state — Keychain UUID, `ConfigCache`, `DraftStore`, `BackgroundUploadManager` — is keyed by the configuration's `apiKey`, so in principle multiple clients would partition cleanly, but no UI affordance explicitly supports it and it's not a v1 goal. Tests cover the single-client case only.

## Open questions

- **Swift tools version.** Stay at 5.9 or bump to 6.0 for strict concurrency? Bumping requires Xcode 16+, which is already implied by iOS 18 minimum but worth making explicit.
- **Background upload state store.** Small JSON file vs SQLite. JSON is simpler; SQLite scales better if a user ever has many queued uploads. Default proposal: JSON v1, revisit if needed.
- **SVG rendering for `smileyRating`.** The API returns SVG markup. Options: embed a tiny SVG renderer (adds a dep), rasterize offline and ship PNG assets keyed to position (loses admin flexibility), or render via `WKWebView`/HTML (heavy). Default proposal: parse the 5 known SVG shapes into SwiftUI `Shape` at build time; fall back to a generic circle on unknown markup.
