# CommentRelay iOS SDK — SPM package + sample app scaffolding

**Date:** 2026-04-19
**Status:** Approved
**Scope:** Initial repository scaffolding only. No production SDK features.

## Goal

Stand up the `commentrelay-sdk-ios` repository as a Swift Package Manager package that exposes a minimal public API, plus a sample Xcode app that exercises the package from source. The sample is the primary way we (and future integrators) run the SDK end-to-end during development.

## Constraints & choices (confirmed with user)

- **Platforms:** iOS 17+ and macOS 14+ (matching 2023 release cycle).
- **Swift tools version:** 5.9.
- **Sample app UI:** SwiftUI, single multiplatform target (iPhone, iPad, Mac).
- **Repo layout:** monorepo — SPM package at repo root, sample app under `Example/`, sample references the package via relative path.
- **No Xcode workspace.** Opening either `Package.swift` or the sample `.xcodeproj` works standalone.
- **No external dependencies.** Foundation + URLSession only.
- **Not in scope:** auth, retry, logging, real endpoints beyond `/health`, CI, CocoaPods/Carthage, separate iOS-only or macOS-only sample variants, code signing/distribution.

## Repository layout

```
commentrelay-sdk-ios/
├── Package.swift
├── README.md
├── .gitignore                         # Swift + Xcode
├── Sources/
│   └── CommentRelay/
│       ├── CommentRelay.swift
│       └── CommentRelayClient.swift
├── Tests/
│   └── CommentRelayTests/
│       └── CommentRelayClientTests.swift
├── Example/
│   ├── CommentRelaySample.xcodeproj
│   └── CommentRelaySample/
│       ├── CommentRelaySampleApp.swift
│       ├── ContentView.swift
│       ├── CommentRelaySample.entitlements
│       └── Assets.xcassets
└── docs/
    └── superpowers/specs/
        └── 2026-04-19-ios-sdk-spm-scaffolding-design.md   # this file
```

Module name is `CommentRelay` (so integrators write `import CommentRelay`). Sample bundle id: `com.commentrelay.sample`.

## SPM manifest

`Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CommentRelay",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "CommentRelay", targets: ["CommentRelay"]),
    ],
    targets: [
        .target(name: "CommentRelay"),
        .testTarget(name: "CommentRelayTests", dependencies: ["CommentRelay"]),
    ]
)
```

Single library product. No external dependencies. Future modules (e.g. a `CommentRelayUI`) are added as new products when the feature arrives, not preemptively.

## Public API (day 1)

### `Sources/CommentRelay/CommentRelay.swift`

```swift
public enum CommentRelay {
    public static let version = "0.0.1"
}
```

A namespace enum (uninstantiable) and a version string. Lets the sample prove "the SDK linked and I can read a value from it."

### `Sources/CommentRelay/CommentRelayClient.swift`

```swift
public struct CommentRelayClient: Sendable {
    public let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL = URL(string: "http://localhost:3000")!,
                session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    /// Hits `GET {baseURL}/health`. Returns true on HTTP 2xx.
    public func ping() async throws -> Bool {
        let url = baseURL.appendingPathComponent("health")
        let (_, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
    }

    public enum ClientError: Error {
        case invalidResponse
    }
}
```

**Rationale:**
- `baseURL` defaults to `http://localhost:3000` so the sample works against `../commentrelay/dev.sh` out of the box. Integrators override it.
- `session` is injectable so tests can swap in a mock via `URLProtocol` without touching the network.
- `Sendable` conformance keeps the type Swift 6 concurrency-clean from day 1.
- `ClientError` is declared but unused on day 1. Reserved as the home for real error cases once endpoints beyond `/health` land. If undesired, drop until needed.

**Verified against upstream:** the commentrelay-api exposes `GET /health` at `http://localhost:3000/health` (see `commentrelay-api/dev/server.ts` line 26).

## Sample app

Target type: multiplatform SwiftUI App. Destinations: iPhone, iPad, Mac. Links the SPM package via a local Swift Package reference to `../` (the repo root).

**`CommentRelaySampleApp.swift`** — `@main`, standard `WindowGroup { ContentView() }`.

**`ContentView.swift`** — one screen, approximately 60 lines:
- Label: `CommentRelay v{CommentRelay.version}`
- `TextField` for base URL, pre-filled with `http://localhost:3000`
- "Ping" button that calls `client.ping()` and displays:
  - ✓ connected (on success)
  - ✗ failed — *error description* (on error or HTTP non-2xx)

No platform-specific code required for this screen; no `#if os(...)` branches.

**Entitlements:** `CommentRelaySample.entitlements` grants `com.apple.security.network.client` so the macOS sandbox allows outgoing connections to localhost. iOS needs no special entitlement for HTTP to `localhost` on the simulator, but App Transport Security may require an exception for plain `http://` to arbitrary hosts — for localhost development this is permitted by default.

## Testing

`Tests/CommentRelayTests/CommentRelayClientTests.swift` uses a custom `URLProtocol` subclass to intercept `URLSession` requests — no real network, no test server.

Day-1 test cases:

1. `ping()` issues `GET` to `{baseURL}/health` (assert URL path and HTTP method).
2. `ping()` returns `true` when the stub responds HTTP 200.
3. `ping()` returns `false` when the stub responds HTTP 500.
4. `ping()` throws when the stub returns a transport error.

Run via `swift test` from the repo root, or `⌘U` in Xcode when `Package.swift` is opened.

## Developer workflow

- **Edit the SDK:** open `Package.swift` in Xcode. Or use `swift build` / `swift test` from the command line.
- **Run the sample:** open `Example/CommentRelaySample.xcodeproj`, pick a destination (iOS Simulator or My Mac), hit Run. The package is resolved from local path `../`, so edits in `Sources/` appear on next build — no tag, no version bump, no publish step.
- **Point at a non-localhost API:** edit the URL in the sample's text field, or pass a different `baseURL` to `CommentRelayClient(baseURL:)`.

## README

Short README covers:
- What the SDK is (one-line)
- Minimum versions (iOS 17, macOS 14)
- SPM install snippet (one block)
- How to run the sample (`open Example/CommentRelaySample.xcodeproj`)
- How to override the base URL

## Explicitly deferred

- Authentication, request signing, retry, logging, richer error types
- Endpoints beyond `/health`
- CI (GitHub Actions or otherwise)
- CocoaPods / Carthage / binary XCFramework distribution
- Separate iOS-only or macOS-only sample variants
- Code signing, provisioning, App Store distribution

Each of these gets its own spec when the need is real.
