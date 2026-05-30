# Powered-by Attribution (CRLBS-132) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a subtle "Powered by CommentRelay" link at the bottom of the iOS feedback widget for free-tier projects only, opening a backend-supplied tracked URL; hidden on paid tiers and when the backend sends no signal.

**Architecture:** The backend adds two top-level fields to `GET /sdk/v1/config` (`show_attribution`, `attribution_url`) — owned by sibling stories CRLBS-149/150. This SDK plan: decode those fields into a new public `CommentRelayAttribution` value, keep the latest copy as actor state on `CommentRelayClient` (so it stays fresh on every config response, independent of the forms hash), surface it to the UI, and render a `PoweredByFooter` under the submit button when (and only when) attribution is enabled and a URL is present. Default is hidden, so the SDK is forward-compatible and ships before the backend.

**Tech Stack:** Swift 5.9+, Swift Package Manager, SwiftUI (CommentRelayUI module), XCTest, `@testable import`, `MockURLProtocol` for transport tests.

---

## File Structure

**Create:**
- `Sources/CommentRelayCore/Public/Models/CommentRelayAttribution.swift` — public value type for the attribution signal + its gating rule.
- `Sources/CommentRelayUI/Components/PoweredByFooter.swift` — the footer view (renders or omits itself).
- `Tests/CommentRelayCoreTests/CommentRelayAttributionTests.swift` — gating-rule unit tests.
- `Tests/CommentRelayCoreTests/AttributionDecodingTests.swift` — config-envelope decode tests.
- `Tests/CommentRelayCoreTests/AttributionClientTests.swift` — client threads attribution from a config fetch.

**Modify:**
- `Sources/CommentRelayCore/Public/Models/CommentRelayForm.swift` — add the internal `DecodedConfigResponse` decoder (config + attribution in one decode).
- `Sources/CommentRelayCore/Public/CommentRelayClient.swift` — store `latestAttribution`, expose `attribution()`, decode `DecodedConfigResponse` in `fetchConfig`.
- `Sources/CommentRelayUI/Screens/FeedbackFormView.swift` — accept attribution, render `PoweredByFooter` under the submit button.
- `Sources/CommentRelayUI/Screens/CommentRelayView.swift` — load attribution after `fetchConfig`, pass it into `FeedbackFormView`.
- `Sources/CommentRelayUI/Shared/Strings.swift` — add `poweredBy` accessor.
- Localization resource(s) under `Sources/CommentRelayUI` — add the `crl.powered_by` string.
- `README.md` — document the free-tier attribution behavior.
- `CHANGELOG.md` (or create) — changelog entry.

---

## Task 1: `CommentRelayAttribution` value type + gating rule

**Files:**
- Create: `Sources/CommentRelayCore/Public/Models/CommentRelayAttribution.swift`
- Test: `Tests/CommentRelayCoreTests/CommentRelayAttributionTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/CommentRelayCoreTests/CommentRelayAttributionTests.swift`:

```swift
import XCTest
@testable import CommentRelayCore

final class CommentRelayAttributionTests: XCTestCase {
    private let url = URL(string: "https://api.commentrelay.com/r/powered-by?p=proj_1")!

    func test_resolvedLink_isURL_whenShowingAndURLPresent() {
        let a = CommentRelayAttribution(showAttribution: true, attributionURL: url)
        XCTAssertEqual(a.resolvedLink, url)
    }

    func test_resolvedLink_isNil_whenNotShowing() {
        let a = CommentRelayAttribution(showAttribution: false, attributionURL: url)
        XCTAssertNil(a.resolvedLink)
    }

    func test_resolvedLink_isNil_whenShowingButNoURL() {
        let a = CommentRelayAttribution(showAttribution: true, attributionURL: nil)
        XCTAssertNil(a.resolvedLink)
    }

    func test_hidden_isNotShowing() {
        XCTAssertNil(CommentRelayAttribution.hidden.resolvedLink)
        XCTAssertFalse(CommentRelayAttribution.hidden.showAttribution)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CommentRelayAttributionTests`
Expected: FAIL — `cannot find 'CommentRelayAttribution' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/CommentRelayCore/Public/Models/CommentRelayAttribution.swift`:

```swift
import Foundation

/// Project-level "Powered by CommentRelay" attribution state (CRLBS-132).
/// Delivered by the backend on every `GET /sdk/v1/config` response. The SDK
/// renders the attribution link only when `showAttribution` is true and a URL
/// is present; otherwise nothing is shown. Defaults to hidden so the SDK is
/// forward-compatible with backends that don't yet send the fields.
public struct CommentRelayAttribution: Sendable, Equatable {
    public let showAttribution: Bool
    public let attributionURL: URL?

    public init(showAttribution: Bool, attributionURL: URL?) {
        self.showAttribution = showAttribution
        self.attributionURL = attributionURL
    }

    /// Safe default: no attribution.
    public static let hidden = CommentRelayAttribution(showAttribution: false, attributionURL: nil)

    /// The link to present, or `nil` when attribution must be hidden. Single
    /// source of truth for the gating rule so the view and tests can't disagree.
    public var resolvedLink: URL? { showAttribution ? attributionURL : nil }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CommentRelayAttributionTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/CommentRelayCore/Public/Models/CommentRelayAttribution.swift Tests/CommentRelayCoreTests/CommentRelayAttributionTests.swift
git commit -m "feat(CRLBS-132): add CommentRelayAttribution value type"
```

---

## Task 2: Decode attribution from the config envelope

`fetchConfig` currently decodes straight to `CommentRelayConfigResponse`. We add an internal `DecodedConfigResponse` that decodes the forms response **and** the two attribution fields in one pass, so a single HTTP decode yields both. `attribution_url` is decoded as a String then mapped via `URL(string:)`, so a malformed URL yields `nil` (hidden) instead of throwing and breaking config loading.

**Files:**
- Modify: `Sources/CommentRelayCore/Public/Models/CommentRelayForm.swift` (append after the existing `CommentRelayConfigResponse` Decodable extension, end of file)
- Test: `Tests/CommentRelayCoreTests/AttributionDecodingTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/CommentRelayCoreTests/AttributionDecodingTests.swift`:

```swift
import XCTest
@testable import CommentRelayCore

final class AttributionDecodingTests: XCTestCase {
    private func decode(_ json: String) throws -> DecodedConfigResponse {
        try JSONDecoder().decode(DecodedConfigResponse.self, from: Data(json.utf8))
    }

    func test_updated_withAttribution_true_andURL() throws {
        let d = try decode(#"""
        {"current":false,"hash":"h1","forms":[],
         "show_attribution":true,
         "attribution_url":"https://api.commentrelay.com/r/powered-by?p=proj_1"}
        """#)
        XCTAssertEqual(d.response, .updated(hash: "h1", forms: []))
        XCTAssertTrue(d.attribution.showAttribution)
        XCTAssertEqual(d.attribution.attributionURL,
                       URL(string: "https://api.commentrelay.com/r/powered-by?p=proj_1"))
    }

    func test_attribution_false_hasNoLink() throws {
        let d = try decode(#"{"current":false,"hash":"h","forms":[],"show_attribution":false}"#)
        XCTAssertFalse(d.attribution.showAttribution)
        XCTAssertNil(d.attribution.resolvedLink)
    }

    func test_fieldsAbsent_defaultsToHidden() throws {
        let d = try decode(#"{"current":false,"hash":"h","forms":[]}"#)
        XCTAssertEqual(d.attribution, .hidden)
    }

    func test_current_response_stillCarriesAttribution() throws {
        let d = try decode(#"{"current":true,"show_attribution":true,
        "attribution_url":"https://api.commentrelay.com/r/powered-by?p=p2"}"#)
        XCTAssertEqual(d.response, .current)
        XCTAssertEqual(d.attribution.resolvedLink,
                       URL(string: "https://api.commentrelay.com/r/powered-by?p=p2"))
    }

    func test_malformedURL_yieldsNil_notThrow() throws {
        let d = try decode(#"{"current":false,"hash":"h","forms":[],
        "show_attribution":true,"attribution_url":""}"#)
        XCTAssertTrue(d.attribution.showAttribution)
        XCTAssertNil(d.attribution.attributionURL)
        XCTAssertNil(d.attribution.resolvedLink)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AttributionDecodingTests`
Expected: FAIL — `cannot find 'DecodedConfigResponse' in scope`.

- [ ] **Step 3: Write minimal implementation**

Append to `Sources/CommentRelayCore/Public/Models/CommentRelayForm.swift` (after the closing `}` of the existing `extension CommentRelayConfigResponse: Decodable`):

```swift

/// Full decode of `GET /sdk/v1/config` (CRLBS-132): the forms response plus
/// project-level attribution. Attribution rides the envelope top-level on every
/// response (both `current` and `updated`) so it stays fresh independent of the
/// forms hash. `attribution_url` is decoded leniently — a malformed value maps
/// to `nil` rather than failing the whole config decode.
struct DecodedConfigResponse: Decodable {
    let response: CommentRelayConfigResponse
    let attribution: CommentRelayAttribution

    private enum CodingKeys: String, CodingKey {
        case showAttribution = "show_attribution"
        case attributionURL = "attribution_url"
    }

    init(from decoder: Decoder) throws {
        response = try CommentRelayConfigResponse(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let show = try c.decodeIfPresent(Bool.self, forKey: .showAttribution) ?? false
        let urlString = try c.decodeIfPresent(String.self, forKey: .attributionURL)
        let url = urlString.flatMap(URL.init(string:))
        attribution = CommentRelayAttribution(showAttribution: show, attributionURL: url)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AttributionDecodingTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/CommentRelayCore/Public/Models/CommentRelayForm.swift Tests/CommentRelayCoreTests/AttributionDecodingTests.swift
git commit -m "feat(CRLBS-132): decode show_attribution/attribution_url from config"
```

---

## Task 3: Thread attribution through `CommentRelayClient`

Store the latest attribution as actor state, expose an accessor, and update it from `fetchConfig`. On transport failure (offline) the last known attribution is retained (we simply don't overwrite it).

**Files:**
- Modify: `Sources/CommentRelayCore/Public/CommentRelayClient.swift`
  - add stored property (after line 13, near `isEnabled`)
  - add accessor + change `fetchConfig` (lines 143-170)
- Test: `Tests/CommentRelayCoreTests/AttributionClientTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/CommentRelayCoreTests/AttributionClientTests.swift`. This mirrors the hermetic-client pattern (test init with `cacheDirectory`/`keychainService`) and `MockURLProtocol` used elsewhere in this test target.

```swift
import XCTest
@testable import CommentRelayCore

final class AttributionClientTests: XCTestCase {
    private var session: URLSession!
    private var tmp: URL!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: cfg)
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("crl-attr-\(UUID().uuidString)")
    }

    override func tearDown() {
        MockURLProtocol.reset()
        try? FileManager.default.removeItem(at: tmp)
        session = nil; tmp = nil
        super.tearDown()
    }

    private func makeClient() -> CommentRelayClient {
        let config = CommentRelayConfiguration(apiKey: "crk_test_abc",
                                               baseURL: URL(string: "https://api.example.com")!)
        return CommentRelayClient(configuration: config, session: session,
                                  cacheDirectory: tmp,
                                  keychainService: "test.attr.\(UUID().uuidString)")
    }

    func test_fetchConfig_surfacesAttribution_whenPresent() async throws {
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = Data(#"""
            {"current":false,"hash":"h","forms":[],
             "show_attribution":true,
             "attribution_url":"https://api.example.com/r/powered-by?p=proj_1"}
            """#.utf8)
            return (resp, body)
        }
        let client = makeClient()
        _ = try await client.fetchConfig(cachedHash: nil)
        let attr = await client.attribution()
        XCTAssertTrue(attr.showAttribution)
        XCTAssertEqual(attr.resolvedLink,
                       URL(string: "https://api.example.com/r/powered-by?p=proj_1"))
    }

    func test_attribution_defaultsHidden_whenFieldsAbsent() async throws {
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data(#"{"current":false,"hash":"h","forms":[]}"#.utf8))
        }
        let client = makeClient()
        _ = try await client.fetchConfig(cachedHash: nil)
        let attr = await client.attribution()
        XCTAssertEqual(attr, .hidden)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AttributionClientTests`
Expected: FAIL — `value of type 'CommentRelayClient' has no member 'attribution'`.

- [ ] **Step 3a: Add the stored property**

In `Sources/CommentRelayCore/Public/CommentRelayClient.swift`, immediately after line 13 (`private(set) public var isEnabled: Bool = true`) add:

```swift

    /// Latest project-level attribution from the most recent successful config
    /// fetch (CRLBS-132). Defaults to hidden; retained across transport failures.
    private var latestAttribution: CommentRelayAttribution = .hidden
```

- [ ] **Step 3b: Add the accessor**

In the same file, directly after the `fetchConfig(...)` method's closing brace (after line 170) add:

```swift

    /// The latest "Powered by CommentRelay" attribution state (CRLBS-132).
    /// Reflects the most recent config fetch; hidden until one succeeds.
    public func attribution() -> CommentRelayAttribution { latestAttribution }
```

- [ ] **Step 3c: Decode attribution in `fetchConfig`**

In `fetchConfig` (lines 149-152), replace:

```swift
            let response: CommentRelayConfigResponse = try await api.send(
                method: "GET", path: basePath, queryItems: queryItems,
                decodingAs: CommentRelayConfigResponse.self)
```

with:

```swift
            let decoded: DecodedConfigResponse = try await api.send(
                method: "GET", path: basePath, queryItems: queryItems,
                decodingAs: DecodedConfigResponse.self)
            let response = decoded.response
            latestAttribution = decoded.attribution
```

Leave the rest of `fetchConfig` (cache write, `.current` handling, transport-catch) unchanged — `response` keeps the same type and meaning.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AttributionClientTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/CommentRelayCore/Public/CommentRelayClient.swift Tests/CommentRelayCoreTests/AttributionClientTests.swift
git commit -m "feat(CRLBS-132): surface attribution from CommentRelayClient.fetchConfig"
```

---

## Task 4: `PoweredByFooter` view + localized string

**Files:**
- Create: `Sources/CommentRelayUI/Components/PoweredByFooter.swift`
- Modify: `Sources/CommentRelayUI/Shared/Strings.swift` (add accessor after line 35, near the other form/thanks strings)
- Modify: localization resource(s) — add `crl.powered_by`

- [ ] **Step 1: Add the Strings accessor**

In `Sources/CommentRelayUI/Shared/Strings.swift`, after line 35 (`static var thanksDone: String { string("crl.thanks.done") }`) add:

```swift
    static var poweredBy: String { string("crl.powered_by") }
```

- [ ] **Step 2: Add the localized value**

Find the localization resource files used by the UI module (they back keys like `crl.form.submit`):

Run: `grep -rl "crl.form.submit" Sources/CommentRelayUI`

For each `*.strings` file returned (e.g. `Sources/CommentRelayUI/Resources/en.lproj/Localizable.strings`), add this line:

```
"crl.powered_by" = "Powered by CommentRelay";
```

If the resource is an `.xcstrings` (JSON) catalog instead, add a string entry whose key is `crl.powered_by` with the English value `Powered by CommentRelay` (mirror the structure of the existing `crl.form.submit` entry). "Powered by CommentRelay" is a brand name and is left untranslated for non-English locales (matches it being the product name).

- [ ] **Step 3: Create the view**

Create `Sources/CommentRelayUI/Components/PoweredByFooter.swift`:

```swift
import SwiftUI
import CommentRelayCore

/// CRLBS-132: subtle "Powered by CommentRelay" attribution shown at the bottom
/// of the feedback widget for free-tier projects. Renders nothing unless the
/// backend config enabled attribution and supplied a link.
struct PoweredByFooter: View {
    let attribution: CommentRelayAttribution
    @Environment(\.commentRelayTheme) private var theme

    var body: some View {
        if let url = attribution.resolvedLink {
            Link(destination: url) {
                Text(Strings.poweredBy)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .underline()
            }
            .tint(theme.accentColor)
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityIdentifier("crl.powered_by")
        }
    }
}
```

- [ ] **Step 4: Build to verify it compiles**

Run: `swift build`
Expected: builds without errors (the view is not yet referenced; that's fine).

- [ ] **Step 5: Commit**

```bash
git add Sources/CommentRelayUI/Components/PoweredByFooter.swift Sources/CommentRelayUI/Shared/Strings.swift Sources/CommentRelayUI/Resources
git commit -m "feat(CRLBS-132): add PoweredByFooter view and powered-by string"
```

---

## Task 5: Wire the footer into the form

`FeedbackFormView` gains a defaulted `attribution` parameter (so existing callers/tests still compile), renders `PoweredByFooter` under the submit button, and `CommentRelayView` loads attribution after `fetchConfig` and passes it in.

**Files:**
- Modify: `Sources/CommentRelayUI/Screens/FeedbackFormView.swift` (init lines 8-13; body lines 35-40)
- Modify: `Sources/CommentRelayUI/Screens/CommentRelayView.swift` (state ~line 12; `loadForms` lines 148-169; call site line 110)
- Test: `Tests/CommentRelayUITests/ScreenTests/FeedbackFormViewTests.swift` (extend)

- [ ] **Step 1: Write the failing test**

Append to `Tests/CommentRelayUITests/ScreenTests/FeedbackFormViewTests.swift` (inside the existing `final class FeedbackFormViewTests` — keep existing imports/helpers). This verifies the view constructs with attribution and that the gating value it would use is correct; it does not require ViewInspector.

```swift
    func test_view_constructsWithAttribution_andExposesResolvedLink() {
        let url = URL(string: "https://api.commentrelay.com/r/powered-by?p=p1")!
        let form = CommentRelayForm(
            id: "f1", title: "T", clientFormId: nil, showInPicker: true,
            responseLimitCount: nil, responseLimitType: nil, responseLimitWindowMinutes: nil,
            moreFeedbackPrompt: nil, isActive: true, sortOrder: 0, fields: [])
        let vm = FeedbackFormViewModel(form: form, userIdentifier: "u",
                                       platform: .iOS, sdkVersion: "1.0.0")
        let shown = CommentRelayAttribution(showAttribution: true, attributionURL: url)
        let view = FeedbackFormView(viewModel: vm, attribution: shown) { _ in }
        XCTAssertEqual(view.attribution.resolvedLink, url)

        // Default omits attribution (back-compat for existing callers).
        let plain = FeedbackFormView(viewModel: vm) { _ in }
        XCTAssertNil(plain.attribution.resolvedLink)
    }
```

> Note: confirm `Platform.iOS` is the correct case name; if the enum uses a different spelling, match it (the existing `FeedbackFormViewModelTests` show the canonical case). If `CommentRelayForm`'s member-wise initializer differs, copy the exact initializer call used by a neighboring test in this file.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter FeedbackFormViewTests/test_view_constructsWithAttribution_andExposesResolvedLink`
Expected: FAIL — `extra argument 'attribution' in call` / `value ... has no member 'attribution'`.

- [ ] **Step 3a: Add the attribution property + init param to `FeedbackFormView`**

In `Sources/CommentRelayUI/Screens/FeedbackFormView.swift`, replace lines 6-13:

```swift
    @State public var viewModel: FeedbackFormViewModel
    // Not @Sendable: main-actor SwiftUI action closure — mutates main-actor state.
    public let onSubmit: (CommentRelaySubmission) -> Void

    public init(viewModel: FeedbackFormViewModel, onSubmit: @escaping (CommentRelaySubmission) -> Void) {
        self._viewModel = State(initialValue: viewModel)
        self.onSubmit = onSubmit
    }
```

with:

```swift
    @State public var viewModel: FeedbackFormViewModel
    /// CRLBS-132: free-tier attribution to render under the submit button.
    public let attribution: CommentRelayAttribution
    // Not @Sendable: main-actor SwiftUI action closure — mutates main-actor state.
    public let onSubmit: (CommentRelaySubmission) -> Void

    public init(viewModel: FeedbackFormViewModel,
                attribution: CommentRelayAttribution = .hidden,
                onSubmit: @escaping (CommentRelaySubmission) -> Void) {
        self._viewModel = State(initialValue: viewModel)
        self.attribution = attribution
        self.onSubmit = onSubmit
    }
```

- [ ] **Step 3b: Render the footer under the submit button**

In the same file, replace the submit `Button` block (lines 35-40):

```swift
                Button(Strings.formSubmit) {
                    onSubmit(viewModel.buildSubmission())
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(!viewModel.isSubmittable)
```

with:

```swift
                Button(Strings.formSubmit) {
                    onSubmit(viewModel.buildSubmission())
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(!viewModel.isSubmittable)

                PoweredByFooter(attribution: attribution)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter FeedbackFormViewTests/test_view_constructsWithAttribution_andExposesResolvedLink`
Expected: PASS.

- [ ] **Step 5a: Add attribution state to `CommentRelayView`**

In `Sources/CommentRelayUI/Screens/CommentRelayView.swift`, after line 12 (`@State private var pendingCount = 0`) add:

```swift
    @State private var attribution: CommentRelayAttribution = .hidden
```

- [ ] **Step 5b: Load attribution after config in `loadForms`**

In `loadForms()` replace the line (148-150):

```swift
    private func loadForms() async {
        do {
            switch try await client.fetchConfig(cachedHash: nil) {
```

with:

```swift
    private func loadForms() async {
        do {
            let configResult = try await client.fetchConfig(cachedHash: nil)
            attribution = await client.attribution()
            switch configResult {
```

(The `case .current:` / `case .updated(...)` branches below stay exactly as they are.)

- [ ] **Step 5c: Pass attribution into `FeedbackFormView`**

In the `.form` route (lines 108-112), replace:

```swift
        case .form:
            if let vm = activeViewModel {
                FeedbackFormView(viewModel: vm) { submission in
                    Task { @MainActor in await submitWithViewModel(submission) }
                }
```

with:

```swift
        case .form:
            if let vm = activeViewModel {
                FeedbackFormView(viewModel: vm, attribution: attribution) { submission in
                    Task { @MainActor in await submitWithViewModel(submission) }
                }
```

- [ ] **Step 6: Run the full UI test target to verify nothing regressed**

Run: `swift test --filter CommentRelayUITests`
Expected: PASS (existing screen tests + the new one).

- [ ] **Step 7: Commit**

```bash
git add Sources/CommentRelayUI/Screens/FeedbackFormView.swift Sources/CommentRelayUI/Screens/CommentRelayView.swift Tests/CommentRelayUITests/ScreenTests/FeedbackFormViewTests.swift
git commit -m "feat(CRLBS-132): render PoweredByFooter in the feedback widget"
```

---

## Task 6: Documentation

**Files:**
- Modify: `README.md`
- Modify/Create: `CHANGELOG.md`

- [ ] **Step 1: README note**

In `README.md`, in the configuration/behavior area (after the config options table around lines 60-73), add a short subsection:

```markdown
### Attribution (free tier)

Projects on the Free tier show a subtle "Powered by CommentRelay" link at the
bottom of the feedback widget. It is controlled entirely by the server (the SDK
shows it only when the config endpoint enables it) and is automatically hidden
on paid tiers. No client configuration is required.
```

- [ ] **Step 2: CHANGELOG entry**

Run: `ls CHANGELOG.md` to check if it exists.

If it exists, add under the top "Unreleased" section:

```markdown
- Free-tier feedback widgets now show a "Powered by CommentRelay" attribution link, suppressed on paid tiers (CRLBS-132).
```

If it does **not** exist, create `CHANGELOG.md`:

```markdown
# Changelog

## Unreleased

- Free-tier feedback widgets now show a "Powered by CommentRelay" attribution link, suppressed on paid tiers (CRLBS-132).
```

- [ ] **Step 3: Commit**

```bash
git add README.md CHANGELOG.md
git commit -m "docs(CRLBS-132): document free-tier attribution behavior"
```

---

## Task 7: Full verification

- [ ] **Step 1: Build the whole package**

Run: `swift build`
Expected: build succeeds, no warnings introduced by these changes.

- [ ] **Step 2: Run the entire test suite**

Run: `swift test`
Expected: all tests pass (new: `CommentRelayAttributionTests`, `AttributionDecodingTests`, `AttributionClientTests`, extended `FeedbackFormViewTests`; plus all pre-existing tests green).

- [ ] **Step 3: Push the branch**

```bash
git push
```

Expected: branch `feature/CRLBS-132-powered-by-attribution` updated on origin (Bitbucket).

---

## Self-Review (completed during planning)

- **Spec coverage:**
  - "Badge visible on Free tier, hidden on paid" → Tasks 1 (`resolvedLink` gate), 3 (client surfaces flag), 5 (render). ✓
  - "Click lands on commentrelay.com with a tracked source param" → backend-supplied `attribution_url` opened by `PoweredByFooter` (Task 4); backend redirect/UTM is CRLBS-150. ✓
  - "Top-level fields on every (current & updated) response" → Task 2 decode + `test_current_response_stillCarriesAttribution`; Task 3 sets `latestAttribution` on every fetch. ✓
  - "Default hidden when absent" → Tasks 1 (`.hidden`), 2 (`?? false`), 3 (default state). ✓
  - Decode + UI-gating + link-target tests → Tasks 1-3, 5. ✓
  - README/CHANGELOG → Task 6. ✓
- **Placeholder scan:** none. The localization step gives exact key/value plus a `grep` to locate the file; the `Platform`/`CommentRelayForm` initializer note tells the engineer to match the neighboring test's exact form (these are real APIs in the repo, not invented).
- **Type consistency:** `CommentRelayAttribution(showAttribution:attributionURL:)`, `.hidden`, `resolvedLink`, `DecodedConfigResponse.response`/`.attribution`, `CommentRelayClient.attribution()`, `FeedbackFormView(viewModel:attribution:onSubmit:)`, `PoweredByFooter(attribution:)`, `Strings.poweredBy` — names are used identically across all tasks.
</content>
</invoke>
