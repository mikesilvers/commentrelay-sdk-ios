# CommentRelay iOS SDK

Drop‑in feedback collection for iOS & macOS apps. Present a ready‑made feedback
UI in one line, or drive the API directly. Submissions are delivered reliably —
including offline, with automatic retry.

**Requirements:** iOS 18+ / macOS 15+ · Xcode 16+ (Swift 6 tools) · SwiftPM

The package vends two libraries:

| Library | Use it for |
|---|---|
| `CommentRelayUI` | The drop‑in SwiftUI feedback experience (form picker → form → submit → history). Depends on Core. |
| `CommentRelayCore` | Configuration, the `CommentRelayClient` API actor, and models. Use directly for a custom UI or headless submission. |

---

## 1. Install (Swift Package Manager)

**Xcode:** File → Add Package Dependencies… → enter
`https://github.com/mikesilvers/commentrelay-sdk-ios.git` → Dependency Rule
**Up to Next Major Version** `1.0.0` → add the **CommentRelayUI** (and/or
**CommentRelayCore**) library to your app target.

**Package.swift:**

```swift
dependencies: [
    .package(url: "https://github.com/mikesilvers/commentrelay-sdk-ios.git", from: "1.0.0"),
],
targets: [
    .target(name: "YourApp", dependencies: [
        .product(name: "CommentRelayUI",  package: "commentrelay-sdk-ios"),
        // .product(name: "CommentRelayCore", package: "commentrelay-sdk-ios"), // headless only
    ]),
]
```

No binary signing/notarization applies — this is a source package; Xcode builds
it with your app.

---

## 2. Configure

Everything starts with a `CommentRelayConfiguration` (from `CommentRelayCore`).
Minimum: your API base URL and project API key.

```swift
import CommentRelayCore

let config = CommentRelayConfiguration(
    baseURL: URL(string: "https://your-commentrelay-api.example.com")!,
    apiKey: "crk_live_yourprojectkey",
    userIdentifier: currentUser?.id          // optional; enables history & per-user limits
)
```

Full options (all after `apiKey` have defaults):

| Parameter | Default | Purpose |
|---|---|---|
| `baseURL` | — | CommentRelay API root the SDK talks to. |
| `apiKey` | — | Project API key (`crk_…`). |
| `userIdentifier` | `nil` | App‑assigned stable user id. Enables submission history and per‑user response limits. Omit for anonymous. |
| `locale` | `nil` | BCP‑47 locale override sent with submissions. |
| `sdkVersionOverride` / `osVersionOverride` / `deviceModelOverride` / `appVersionOverride` | `nil` | Override the auto‑detected diagnostic context. |
| `offlineQueueingEnabled` | `true` | Persist & auto‑retry submissions made offline / on transient failure. |
| `maxQueuedSubmissions` | `50` | FIFO cap on the offline queue. |
| `maxQueueAge` | `30 days` | Queued entries older than this are pruned. |

> The SDK never hardcodes secrets — supply the API key from your own config/keychain.

---

## 3. Present feedback (drop‑in UI)

The simplest integration: add `.commentRelaySheet` to any view and toggle a
`Bool`. It loads the project's feedback forms, lets the user pick/fill/submit,
and shows their history.

```swift
import SwiftUI
import CommentRelayCore
import CommentRelayUI

struct SettingsView: View {
    @State private var showFeedback = false

    var body: some View {
        Button("Send feedback") { showFeedback = true }
            .commentRelaySheet(
                isPresented: $showFeedback,
                configuration: config            // the CommentRelayConfiguration from step 2
            )
    }
}
```

Jump straight to one form (skips the picker) with `formId:` or `formTitle:`:

```swift
.commentRelaySheet(isPresented: $showFeedback,
                    configuration: config,
                    formTitle: "Bug Report")
```

A form that is inactive or not marked “show in picker” is never surfaced —
including via `formId`/`formTitle` preselect.

Need to embed it yourself (custom presentation, navigation push, etc.) instead
of a sheet? Use the view directly:

```swift
CommentRelayView(configuration: config, formId: nil, formTitle: nil)
```

Theming: inject a `CommentRelayTheme` via the environment
(`.environment(\.commentRelayTheme, CommentRelayTheme(accentColor: .pink, cornerRadius: 12))`).

---

## 4. Headless API (no SDK UI)

Use `CommentRelayClient` (an `actor`) directly to build your own UI or submit
programmatically.

```swift
let client = CommentRelayClient(configuration: config)

// Reachability / health
let up = try await client.ping()

// Forms (offline-capable: returns cached forms when the network is down)
switch try await client.effectiveConfig() {
case .updated(let hash, let forms): render(forms)   // hash drives caching
case .current:                       break           // your cached forms are current
}

// Submit. submit() runs the full POST → upload → finalize flow for you.
let outcome = try await client.submit(submission, attachments: attachments)
switch outcome {
case .submitted(let receipt): // delivered now
case .queued(let localId):    // offline/transient — persisted, auto-retried later
}

// History (requires userIdentifier)
let history = try await client.fetchHistory()

// Drafts (auto-save in-progress feedback)
await client.saveDraft(formId: form.id, fieldValues: values)
let draft = await client.loadDraft(formId: form.id)
await client.deleteDraft(formId: form.id)
```

Observe the offline queue depth (`CommentRelayUI` shows a pending badge for
this). `CommentRelayClient` is an `actor`, so the stream accessor is `await`ed
at the call site:

```swift
let count = await client.pendingSubmissionCount          // one-shot
for await depth in await client.pendingSubmissionCountStream() {
    updateBadge(depth)                                    // live updates
}
```

Other surface: `flushQueue()` (manually trigger delivery), `resubmit(_:)`,
`finalize(_:)`, `uploadFiles(receipt:payloads:)` (used internally by `submit`),
and `reset()`.

### Error handling

`submit` throws `CommentRelayError` for **terminal** failures
(`badRequest` 400, `paymentRequired` 402, `forbidden` 403, `notFound` 404,
decoding) — these are never queued. A `403` also trips a circuit‑breaker:
the client disables until you call `await client.reset()`. Transient failures
(transport/offline, `429`, `5xx`) return `.queued` instead of throwing (when
`offlineQueueingEnabled`).

---

## 5. Offline behavior

`submit(_:attachments:)` returns `.submitted(receipt)` when delivered
immediately, or `.queued(localId:)` when offline or on a transient failure
(queueing on by default; `offlineQueueingEnabled: false` makes transient
failures throw instead).

Queued submissions persist to disk (FIFO; `maxQueuedSubmissions`,
`maxQueueAge`) and are delivered automatically on connectivity‑restored, SDK
init, app foreground, or any `submit()`/`flushQueue()` call. Delivery is
finalize‑first, so a crash/interruption after the server accepted a submission
does not create a duplicate; presigned upload URLs are never cached (a resumed
upload re‑requests fresh URLs). Feedback forms render offline from cached
config via `effectiveConfig()`.

---

## 6. App setup notes

- **macOS:** the feedback flow needs outgoing network. Enable App Sandbox →
  *Outgoing Connections (Client)* (`ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES`).
- **iOS / non‑HTTPS dev API:** App Transport Security blocks cleartext HTTP.
  Use HTTPS in production; for a local `http://` dev API add the appropriate ATS
  exception to your app’s Info.plist (development only).
- **Photo attachments:** if your forms accept photos, add the usual photo‑access
  usage description to your app’s Info.plist as required by the OS.

## 7. Privacy

Both libraries ship an Apple privacy manifest (`PrivacyInfo.xcprivacy`) as an
SPM resource, aggregated automatically into your app’s privacy report. The SDK
does **not** track users (`NSPrivacyTracking = false`, no tracking domains) and
uses no required‑reason APIs. Collected data — feedback content, photo/video
attachments, optional contact details (email, phone), an app‑assigned user
identifier, and diagnostic context (OS/app version, locale) — is declared as
linked to the user and used only for App Functionality.

---

## Sample app

A multiplatform SwiftUI sample lives in `Example/CommentRelaySample/`. Open
`Example/CommentRelaySample/CommentRelaySample.xcodeproj`, pick an iOS Simulator
or *My Mac*, and Run. It references this package by local path, so `Sources/`
edits are picked up on the next build.

## Contributing / development

`develop` is the integration branch; `main` is the release branch (consumers
pin a SemVer tag on `main`). Run the suite from the repo root:

```sh
swift test
```

Versioning is SemVer; the SDK reports its version to the API as `sdk_version`
(see `CommentRelay.version`).
