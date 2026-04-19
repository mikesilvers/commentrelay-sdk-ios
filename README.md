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
