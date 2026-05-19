# CommentRelay iOS SDK

Swift SDK for integrating with [CommentRelay](https://github.com/mikesilvers/commentrelay).

**Requirements:** iOS 17+, macOS 14+, Swift 5.9+

## Installation

Add the package to your project via Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/mikesilvers/commentrelay-sdk-ios.git", from: "0.0.1"),
]
```

Or in Xcode: **File → Add Package Dependencies…** and enter the repo URL.

## Usage

```swift
import CommentRelay

let client = CommentRelayClient() // defaults to http://localhost:3000
let ok = try await client.ping()
print("API reachable: \(ok)")
```

Point at a different API by passing `baseURL`:

```swift
let client = CommentRelayClient(baseURL: URL(string: "https://api.example.com")!)
```

## Sample app

A multiplatform SwiftUI sample lives in `Example/CommentRelaySample/`. Open `Example/CommentRelaySample/CommentRelaySample.xcodeproj`, select an iOS Simulator or My Mac, and Run. The sample references this package by local path, so edits in `Sources/` are picked up on the next build.

The macOS target enables App Sandbox with "Outgoing Connections (Client)". Xcode 26 stores this in `project.pbxproj` build settings (`ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES`) rather than a separate `.entitlements` file.

## Development

Run the test suite from the repo root:

```sh
swift test
```

## Privacy

Both library targets ship an Apple privacy manifest (`PrivacyInfo.xcprivacy`) as an SPM resource. The SDK does **not** track users (`NSPrivacyTracking = false`, no tracking domains) and uses no required-reason APIs. Collected data (feedback content, photo/video attachments, optional contact details — email address and phone number, an app-assigned user identifier, and other diagnostic context such as OS/app version and locale, declared under the catch-all data type) is declared as linked to the user and used only for App Functionality. Xcode aggregates these manifests into your app's privacy report automatically.

Source distribution via SPM requires no binary signature; XCFramework/binary signing and notarization are not applicable to this source package.

## Offline submissions

`submit(_:attachments:)` returns `SubmitOutcome`: `.submitted(receipt)` when delivered immediately, or `.queued(localId:)` when offline / on a transient failure (queueing is on by default — set `offlineQueueingEnabled: false` to opt out, in which case transient failures throw). Terminal errors (`400/402/403/404`/decoding) always throw and are never queued.

Queued submissions persist to disk (max `maxQueuedSubmissions`, default 50; max `maxQueueAge`, default 30 days; FIFO eviction) and are delivered automatically on connectivity-restored, SDK init, app foreground, or any `submit()`/`flushQueue()` call. Delivery is finalize-first so a crash after the server accepted a submission does not create a duplicate; presigned upload URLs are never cached (a resumed upload re-requests fresh URLs). Observe `pendingSubmissionCount` / `pendingSubmissionCountStream()`; `CommentRelayUI` shows a pending badge. Feedback forms render offline from cached config via `effectiveConfig()`.
