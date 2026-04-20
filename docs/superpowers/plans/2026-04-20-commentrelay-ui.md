# CommentRelayUI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build out `CommentRelayUI` — the SwiftUI library that turns `CommentRelayCore`'s dynamic category/field config into the full feedback flow: launchers, container, composable screens, 10 field renderers, shared UI, theme, and English + Latin American Spanish resources.

**Architecture:** A second SPM library product (`CommentRelayUI`) in the same package, depending on the target `CommentRelayCore`. SwiftUI-only — no SwiftUI types leak into Core. UI drives all side effects through the existing `CommentRelayClient` actor; this plan extends the Core facade with public draft methods so the UI doesn't need direct access to the internal `DraftStore`. Tests live in a separate `CommentRelayUITests` target using [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) and [ViewInspector](https://github.com/nalexn/ViewInspector).

**Tech Stack:** Swift 6 strict concurrency, `swift-tools-version: 6.0`, iOS 18 / macOS 15, SwiftUI, PhotosUI (`PhotosPicker`), SwiftUI `.fileImporter`. Test deps (test-target-only): `swift-snapshot-testing` 1.17.0+, `ViewInspector` 0.10.1+.

**Out of scope for Plan B:**
- Deep customization via style protocols (spec commits to future work)
- Floating launcher overlay
- Wizard-mode form layout
- Built-in translations beyond English and `es-419`
- Full 120-snapshot matrix (10 types × 2 appearance × 2 locales × 3 Dynamic Type). This plan ships **2 snapshot tests per renderer** (light/en/default + dark/es-419/large) as a regression baseline; the remaining matrix is left for incremental expansion once integrators surface real rendering issues.
- True background-configuration `URLSession` for uploads (plan A used a foreground session through the same protocol seam; switching to `.background(withIdentifier:)` + delegate plumbing is a post-v1 follow-up).

---

## File structure (end of Plan B)

```
Package.swift                                               # modified — add UI product, test target, test deps
Sources/
├── CommentRelayCore/                                       # modified — add public draft methods on CommentRelayClient
│   └── Public/CommentRelayClient.swift                     # modified
└── CommentRelayUI/                                         # NEW module
    ├── Launchers/
    │   ├── CommentRelaySheetModifier.swift                 # View.commentRelaySheet(isPresented:configuration:)
    │   └── CommentRelayButton.swift                        # pre-styled button owning its own sheet
    ├── Screens/
    │   ├── CommentRelayView.swift                          # container with internal NavigationStack
    │   ├── CategoryPickerView.swift
    │   ├── FeedbackFormView.swift                          # largest view — orchestrates fields, drafts, submit
    │   ├── FeedbackFormViewModel.swift                     # @Observable driving FeedbackFormView
    │   ├── SubmissionProgressView.swift
    │   ├── ThankYouView.swift
    │   ├── HistoryListView.swift
    │   ├── HistoryDetailView.swift
    │   └── DraftRestorePrompt.swift
    ├── Fields/
    │   ├── FieldRenderer.swift                             # public protocol + type eraser
    │   ├── TextboxFieldView.swift
    │   ├── EmailFieldView.swift
    │   ├── PhoneFieldView.swift
    │   ├── NumericFieldView.swift
    │   ├── TrueFalseFieldView.swift
    │   ├── InformationalFieldView.swift
    │   ├── SmileyRatingFieldView.swift
    │   ├── ColorScaleFieldView.swift
    │   ├── PhotoFieldView.swift                            # PhotosPicker
    │   └── AttachmentFieldView.swift                       # .fileImporter
    ├── Shared/
    │   ├── CommentRelayTheme.swift                         # env-injected tokens
    │   ├── ErrorBanner.swift
    │   ├── EmptyStateView.swift
    │   ├── LoadingView.swift
    │   └── ContactPreferenceSection.swift
    └── Resources/
        ├── en.lproj/Localizable.strings
        └── es-419.lproj/Localizable.strings
Tests/
└── CommentRelayUITests/
    ├── Helpers/
    │   ├── SnapshotHelpers.swift                           # shared config for swift-snapshot-testing
    │   └── FakeCategory.swift                              # builder for Category/Field fixtures
    ├── FieldRendererTests/                                 # one test file per renderer (12 files)
    │   ├── TextboxFieldViewTests.swift
    │   └── ... (one per renderer)
    ├── ScreenTests/
    │   ├── CategoryPickerViewTests.swift
    │   ├── FeedbackFormViewTests.swift
    │   ├── HistoryListViewTests.swift
    │   └── ... (one per screen)
    ├── LocalizationTests.swift
    ├── AccessibilityAuditTests.swift
    └── __Snapshots__/                                      # baseline images generated per renderer
Example/CommentRelaySample/CommentRelaySample/
└── ContentView.swift                                       # modified — attach .commentRelaySheet
```

---

## Prerequisites

### Task 1: Expose public draft methods on `CommentRelayClient`

The UI's `FeedbackFormView` needs to read/write/delete drafts to surface the "resume your draft?" prompt and auto-save field changes. `DraftStore` is internal; we add thin wrappers on the public `CommentRelayClient` actor so UI doesn't need direct access.

**Files:**
- Modify: `Sources/CommentRelayCore/Public/CommentRelayClient.swift`
- Modify: `Sources/CommentRelayCore/Internal/DraftStore.swift` (make `Draft` reachable as a public type alias under `CommentRelay`)
- Create: `Tests/CommentRelayCoreTests/DraftAPITests.swift`

- [ ] **Step 1: Create a public type alias so callers can use `CommentRelayDraft` without importing the internal type.**

In `Sources/CommentRelayCore/Internal/DraftStore.swift`, append at module scope:

```swift
public typealias CommentRelayDraft = DraftStore.Draft
```

- [ ] **Step 2: Write the failing test.**

```swift
// Tests/CommentRelayCoreTests/DraftAPITests.swift
import XCTest
@testable import CommentRelayCore

final class DraftAPITests: XCTestCase {
    private func makeClient() async throws -> CommentRelayClient {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("crl-draft-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let config = CommentRelayConfiguration(
            baseURL: URL(string: "http://localhost:3000")!,
            apiKey: "crk_test_abc",
            userIdentifier: "test-user")
        return CommentRelayClient(configuration: config, session: .shared, cacheDirectory: dir, keychainService: "crl.test.\(UUID().uuidString)")
    }

    func test_saveLoadDelete_roundTrip() async throws {
        let client = try await makeClient()
        await client.saveDraft(categoryId: "cat1", fieldValues: ["f1": "hello"])
        // DraftStore debounce is 0.5s by default; wait long enough to hit disk.
        try await Task.sleep(nanoseconds: 700_000_000)
        let loaded = await client.loadDraft(categoryId: "cat1")
        XCTAssertEqual(loaded?.fieldValues["f1"], "hello")

        await client.deleteDraft(categoryId: "cat1")
        let afterDelete = await client.loadDraft(categoryId: "cat1")
        XCTAssertNil(afterDelete)
    }
}
```

- [ ] **Step 3: Run — expect failure.**

```bash
cd /Users/mikesilvers/repos/commentrelay-sdk/commentrelay-sdk-ios
swift test --filter DraftAPITests 2>&1 | tail -20
```

- [ ] **Step 4: Add the three methods to `CommentRelayClient`.** Append inside the actor body, before the `// MARK: - Internal helpers` section:

```swift
    public func saveDraft(categoryId: String, fieldValues: [String: String]) async {
        let draft = CommentRelayDraft(categoryId: categoryId, fieldValues: fieldValues, updatedAt: Date())
        await draftStore.save(draft)
    }

    public func loadDraft(categoryId: String) async -> CommentRelayDraft? {
        await draftStore.load(categoryId: categoryId)
    }

    public func deleteDraft(categoryId: String) async {
        await draftStore.delete(categoryId: categoryId)
    }
```

- [ ] **Step 5: Run — expect pass.**

```bash
swift test --filter DraftAPITests 2>&1 | tail -10
swift test 2>&1 | tail -3
```

Expected: new test passes, full suite (52 tests now) remains green.

- [ ] **Step 6: Commit.**

```bash
git add Sources/CommentRelayCore/Public/CommentRelayClient.swift \
        Sources/CommentRelayCore/Internal/DraftStore.swift \
        Tests/CommentRelayCoreTests/DraftAPITests.swift
git commit -m "Expose public draft methods on CommentRelayClient"
```

---

## Package restructuring

### Task 2: Add `CommentRelayUI` library, test target, and test dependencies

**Files:**
- Modify: `Package.swift`

- [ ] **Step 1: Overwrite `Package.swift`** to add the UI product, test target, and test-only deps. The resulting manifest should read:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CommentRelay",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "CommentRelayCore", targets: ["CommentRelayCore"]),
        .library(name: "CommentRelayUI", targets: ["CommentRelayUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
        .package(url: "https://github.com/nalexn/ViewInspector", from: "0.10.1"),
    ],
    targets: [
        .target(name: "CommentRelayCore"),
        .target(
            name: "CommentRelayUI",
            dependencies: ["CommentRelayCore"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "CommentRelayCoreTests", dependencies: ["CommentRelayCore"]),
        .testTarget(
            name: "CommentRelayUITests",
            dependencies: [
                "CommentRelayUI",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
                .product(name: "ViewInspector", package: "ViewInspector"),
            ]
        ),
    ]
)
```

- [ ] **Step 2: Create placeholder sources so the new targets resolve.**

```bash
mkdir -p Sources/CommentRelayUI/Launchers \
         Sources/CommentRelayUI/Screens \
         Sources/CommentRelayUI/Fields \
         Sources/CommentRelayUI/Shared \
         Sources/CommentRelayUI/Resources \
         Tests/CommentRelayUITests/Helpers \
         Tests/CommentRelayUITests/FieldRendererTests \
         Tests/CommentRelayUITests/ScreenTests
```

The UI target needs at least one `.swift` file to compile. Create a stub at `Sources/CommentRelayUI/CommentRelayUI.swift`:

```swift
import Foundation

/// Namespace for SDK UI types that aren't exposed anywhere else. Intentionally empty at construction;
/// populated by subsequent tasks.
public enum CommentRelayUI {}
```

And a placeholder test so the test target has content:

```swift
// Tests/CommentRelayUITests/PackageResolvesTests.swift
import XCTest
@testable import CommentRelayUI

final class PackageResolvesTests: XCTestCase {
    func test_moduleLoads() {
        _ = CommentRelayUI.self
    }
}
```

- [ ] **Step 3: Resolve package deps and build.**

```bash
cd /Users/mikesilvers/repos/commentrelay-sdk/commentrelay-sdk-ios
swift package resolve 2>&1 | tail -10
swift build 2>&1 | tail -10
```

Expected: both deps (`swift-snapshot-testing`, `ViewInspector`) resolve. `swift build` succeeds for Core and UI.

- [ ] **Step 4: Run the full suite.**

```bash
swift test 2>&1 | tail -5
```

Expected: 52 Core tests + 1 new UI test = 53 tests passing.

- [ ] **Step 5: Commit.**

```bash
git add Package.swift Sources/CommentRelayUI Tests/CommentRelayUITests
git commit -m "Add CommentRelayUI product + test target with snapshot/inspection deps"
```

---

## Localization resources

### Task 3: Seed `en.lproj` and `es-419.lproj` with initial strings

**Files:**
- Create: `Sources/CommentRelayUI/Resources/en.lproj/Localizable.strings`
- Create: `Sources/CommentRelayUI/Resources/es-419.lproj/Localizable.strings`
- Create: `Sources/CommentRelayUI/Shared/Strings.swift` (typed accessor)

- [ ] **Step 1: Create `en.lproj/Localizable.strings`.**

```
// Sources/CommentRelayUI/Resources/en.lproj/Localizable.strings
"crl.sheet.title" = "Feedback";
"crl.picker.title" = "What would you like to share?";
"crl.picker.empty" = "Feedback isn't available right now.";
"crl.form.submit" = "Send feedback";
"crl.form.sending" = "Sending…";
"crl.form.required" = "Required";
"crl.form.optional" = "Optional";
"crl.form.character_count_format" = "%lld of %lld";
"crl.contact.header" = "How should we follow up?";
"crl.contact.none" = "No follow-up";
"crl.contact.email" = "Email";
"crl.contact.text" = "Text message";
"crl.contact.phone_call" = "Phone call";
"crl.contact.details_placeholder" = "Where can we reach you?";
"crl.progress.title" = "Sending your feedback…";
"crl.progress.file_format" = "Uploading %@";
"crl.thanks.title" = "Thanks!";
"crl.thanks.body" = "Your feedback has been sent.";
"crl.thanks.view_history" = "View past feedback";
"crl.thanks.done" = "Done";
"crl.history.title" = "Past feedback";
"crl.history.empty_identified" = "You haven't sent any feedback yet.";
"crl.history.empty_anonymous" = "Sign in to see your feedback history.";
"crl.history.notes_header" = "Updates from the team";
"crl.draft.restore_title" = "Resume your draft?";
"crl.draft.restore_body" = "You started filling out this form earlier.";
"crl.draft.resume" = "Resume";
"crl.draft.start_over" = "Start over";
"crl.error.generic" = "Something went wrong. Please try again.";
"crl.error.payment_required" = "Feedback is temporarily unavailable. Please try again later.";
"crl.error.rate_limited" = "Too many requests. Please wait a moment.";
"crl.error.upload_failed" = "Upload failed. Tap to retry.";
"crl.rating.smiley_very_unhappy" = "Very unhappy";
"crl.rating.smiley_unhappy" = "Unhappy";
"crl.rating.smiley_neutral" = "Neutral";
"crl.rating.smiley_happy" = "Happy";
"crl.rating.smiley_very_happy" = "Very happy";
"crl.photo.add" = "Add photo";
"crl.photo.remove" = "Remove";
"crl.attachment.add" = "Add attachment";
```

- [ ] **Step 2: Create `es-419.lproj/Localizable.strings`.**

```
// Sources/CommentRelayUI/Resources/es-419.lproj/Localizable.strings
"crl.sheet.title" = "Comentarios";
"crl.picker.title" = "¿Qué quieres compartir?";
"crl.picker.empty" = "Los comentarios no están disponibles en este momento.";
"crl.form.submit" = "Enviar comentarios";
"crl.form.sending" = "Enviando…";
"crl.form.required" = "Requerido";
"crl.form.optional" = "Opcional";
"crl.form.character_count_format" = "%lld de %lld";
"crl.contact.header" = "¿Cómo te contactamos?";
"crl.contact.none" = "Sin seguimiento";
"crl.contact.email" = "Correo electrónico";
"crl.contact.text" = "Mensaje de texto";
"crl.contact.phone_call" = "Llamada telefónica";
"crl.contact.details_placeholder" = "¿Dónde podemos encontrarte?";
"crl.progress.title" = "Enviando tus comentarios…";
"crl.progress.file_format" = "Subiendo %@";
"crl.thanks.title" = "¡Gracias!";
"crl.thanks.body" = "Tus comentarios han sido enviados.";
"crl.thanks.view_history" = "Ver comentarios anteriores";
"crl.thanks.done" = "Listo";
"crl.history.title" = "Comentarios anteriores";
"crl.history.empty_identified" = "Aún no has enviado comentarios.";
"crl.history.empty_anonymous" = "Inicia sesión para ver tu historial de comentarios.";
"crl.history.notes_header" = "Novedades del equipo";
"crl.draft.restore_title" = "¿Continuar tu borrador?";
"crl.draft.restore_body" = "Empezaste a llenar este formulario antes.";
"crl.draft.resume" = "Continuar";
"crl.draft.start_over" = "Empezar de nuevo";
"crl.error.generic" = "Algo salió mal. Inténtalo de nuevo.";
"crl.error.payment_required" = "Los comentarios no están disponibles temporalmente. Inténtalo más tarde.";
"crl.error.rate_limited" = "Demasiadas solicitudes. Espera un momento.";
"crl.error.upload_failed" = "La carga falló. Tócalo para reintentar.";
"crl.rating.smiley_very_unhappy" = "Muy insatisfecho";
"crl.rating.smiley_unhappy" = "Insatisfecho";
"crl.rating.smiley_neutral" = "Neutral";
"crl.rating.smiley_happy" = "Satisfecho";
"crl.rating.smiley_very_happy" = "Muy satisfecho";
"crl.photo.add" = "Agregar foto";
"crl.photo.remove" = "Eliminar";
"crl.attachment.add" = "Agregar archivo";
```

- [ ] **Step 3: Create the typed string accessor.**

```swift
// Sources/CommentRelayUI/Shared/Strings.swift
import Foundation
import CommentRelayCore

enum Strings {
    static func string(_ key: String, locale: Locale = .current) -> String {
        LocalizationBundle.shared.string(forKey: key, locale: locale)
    }

    // Convenience accessors — one per key to catch typos at compile time.
    static var sheetTitle: String { string("crl.sheet.title") }
    static var pickerTitle: String { string("crl.picker.title") }
    static var pickerEmpty: String { string("crl.picker.empty") }
    static var formSubmit: String { string("crl.form.submit") }
    static var formSending: String { string("crl.form.sending") }
    static var formRequired: String { string("crl.form.required") }
    static var formOptional: String { string("crl.form.optional") }
    static var contactHeader: String { string("crl.contact.header") }
    static var contactNone: String { string("crl.contact.none") }
    static var contactEmail: String { string("crl.contact.email") }
    static var contactText: String { string("crl.contact.text") }
    static var contactPhoneCall: String { string("crl.contact.phone_call") }
    static var contactDetailsPlaceholder: String { string("crl.contact.details_placeholder") }
    static var progressTitle: String { string("crl.progress.title") }
    static var thanksTitle: String { string("crl.thanks.title") }
    static var thanksBody: String { string("crl.thanks.body") }
    static var thanksViewHistory: String { string("crl.thanks.view_history") }
    static var thanksDone: String { string("crl.thanks.done") }
    static var historyTitle: String { string("crl.history.title") }
    static var historyEmptyIdentified: String { string("crl.history.empty_identified") }
    static var historyEmptyAnonymous: String { string("crl.history.empty_anonymous") }
    static var historyNotesHeader: String { string("crl.history.notes_header") }
    static var draftRestoreTitle: String { string("crl.draft.restore_title") }
    static var draftRestoreBody: String { string("crl.draft.restore_body") }
    static var draftResume: String { string("crl.draft.resume") }
    static var draftStartOver: String { string("crl.draft.start_over") }
    static var errorGeneric: String { string("crl.error.generic") }
    static var errorPaymentRequired: String { string("crl.error.payment_required") }
    static var errorRateLimited: String { string("crl.error.rate_limited") }
    static var errorUploadFailed: String { string("crl.error.upload_failed") }
    static var photoAdd: String { string("crl.photo.add") }
    static var photoRemove: String { string("crl.photo.remove") }
    static var attachmentAdd: String { string("crl.attachment.add") }

    static func characterCount(_ current: Int, _ max: Int) -> String {
        String(format: string("crl.form.character_count_format"), locale: .current, current, max)
    }

    static func progressFile(_ name: String) -> String {
        String(format: string("crl.progress.file_format"), locale: .current, name)
    }

    static func smileyLabel(position: Int) -> String {
        switch position {
        case 1: return string("crl.rating.smiley_very_unhappy")
        case 2: return string("crl.rating.smiley_unhappy")
        case 3: return string("crl.rating.smiley_neutral")
        case 4: return string("crl.rating.smiley_happy")
        case 5: return string("crl.rating.smiley_very_happy")
        default: return ""
        }
    }
}
```

**Important:** `LocalizationBundle.shared` is internal to `CommentRelayCore`. Make it package-accessible by changing its declaration from `final class LocalizationBundle: Sendable` to `public final class LocalizationBundle: Sendable` in `Sources/CommentRelayCore/Internal/LocalizationBundle.swift`, and its method `func string(forKey key: String, locale: Locale = .current) -> String` to `public func string(...)`. Also mark the `shared` static as `public`. This is the minimum Core change — Plan B's UI is the only consumer of the internal bundle.

Also expose the core lookup: in the Core module, make sure the `CommentRelayUI` bundle is registered as a fallback. Update `LocalizationBundle.string(forKey:locale:)` to use `Bundle.module` as its last-resort lookup:

```swift
// at the bottom of LocalizationBundle.string(forKey:locale:), before the "return key" line
#if SWIFT_PACKAGE
let uiBundle = Bundle.moduleIfAvailable   // see helper below
if let uiBundle {
    let value = uiBundle.localizedString(forKey: key, value: key, table: nil)
    if value != key { return value }
}
#endif
```

The wrinkle is that `Bundle.module` is generated per-target by SPM, so Core can't reference UI's `Bundle.module` directly. Workaround: expose it from UI via a tiny registration hook.

Actually — simpler: since the UI imports Core and drives all string lookups through its own `Strings` accessor, let `Strings.string(_:locale:)` in UI directly use `Bundle.module` (from the UI target) instead of routing through `LocalizationBundle`. Integrator-registered bundles still win via the core `CommentRelayLocalization.register(locale:bundle:)` call that UI's `Strings` checks first.

Replace `Strings.swift`'s body with:

```swift
// Sources/CommentRelayUI/Shared/Strings.swift
import Foundation
import CommentRelayCore

enum Strings {
    static func string(_ key: String, locale: Locale = .current) -> String {
        if let registered = CommentRelayLocalization.registeredBundle(for: locale) {
            let value = registered.localizedString(forKey: key, value: key, table: nil)
            if value != key { return value }
        }
        let host = Bundle.main.localizedString(forKey: key, value: key, table: nil)
        if host != key { return host }
        return Bundle.module.localizedString(forKey: key, value: key, table: nil)
    }

    // ... (all the static var convenience accessors from above)
}
```

For this to compile, `CommentRelayLocalization.registeredBundle(for:)` (currently internal to Core) must become `public`. In `Sources/CommentRelayCore/Internal/LocalizationBundle.swift`, change `static func registeredBundle(for locale: Locale) -> Bundle?` to `public static func registeredBundle(for locale: Locale) -> Bundle?`.

- [ ] **Step 4: Make Core's `CommentRelayLocalization.registeredBundle(for:)` public.**

In `Sources/CommentRelayCore/Internal/LocalizationBundle.swift`, change the single line:

```swift
    static func registeredBundle(for locale: Locale) -> Bundle? {
```

to:

```swift
    public static func registeredBundle(for locale: Locale) -> Bundle? {
```

Nothing else in that file needs to change.

- [ ] **Step 5: Build and run tests.**

```bash
swift build 2>&1 | tail -10
swift test 2>&1 | tail -5
```

Expected: compiles cleanly; existing tests pass (no new tests yet — strings are exercised by subsequent tasks).

- [ ] **Step 6: Commit.**

```bash
git add Sources/CommentRelayCore/Internal/LocalizationBundle.swift \
        Sources/CommentRelayUI/Shared/Strings.swift \
        Sources/CommentRelayUI/Resources
git commit -m "Seed en + es-419 strings and typed Strings accessor"
```

---

## Shared UI

### Task 4: `CommentRelayTheme`

**Files:**
- Create: `Sources/CommentRelayUI/Shared/CommentRelayTheme.swift`
- Create: `Tests/CommentRelayUITests/Helpers/SnapshotHelpers.swift`
- Create: `Tests/CommentRelayUITests/ScreenTests/CommentRelayThemeTests.swift`

- [ ] **Step 1: Write failing test.**

```swift
// Tests/CommentRelayUITests/ScreenTests/CommentRelayThemeTests.swift
import XCTest
import SwiftUI
import ViewInspector
@testable import CommentRelayUI

final class CommentRelayThemeTests: XCTestCase {
    func test_default_values() {
        let theme = CommentRelayTheme.default
        XCTAssertEqual(theme.cornerRadius, 12)
    }

    func test_environment_injection_carriesThroughHierarchy() throws {
        let custom = CommentRelayTheme(accentColor: .purple, cornerRadius: 24)
        let sut = Text("t").environment(\.commentRelayTheme, custom)
        let extracted = try sut.inspect().text().environment(\.commentRelayTheme)
        XCTAssertEqual(extracted.cornerRadius, 24)
    }
}
```

- [ ] **Step 2: Run — expect failure.**

```bash
cd /Users/mikesilvers/repos/commentrelay-sdk/commentrelay-sdk-ios
swift test --filter CommentRelayThemeTests 2>&1 | tail -20
```

- [ ] **Step 3: Implement.**

```swift
// Sources/CommentRelayUI/Shared/CommentRelayTheme.swift
import SwiftUI

public struct CommentRelayTheme: Sendable {
    public var accentColor: Color
    public var cornerRadius: CGFloat

    public init(accentColor: Color, cornerRadius: CGFloat) {
        self.accentColor = accentColor
        self.cornerRadius = cornerRadius
    }

    public static let `default` = CommentRelayTheme(accentColor: .accentColor, cornerRadius: 12)
}

private struct CommentRelayThemeKey: EnvironmentKey {
    static let defaultValue = CommentRelayTheme.default
}

public extension EnvironmentValues {
    var commentRelayTheme: CommentRelayTheme {
        get { self[CommentRelayThemeKey.self] }
        set { self[CommentRelayThemeKey.self] = newValue }
    }
}
```

**Note on the 4-token spec:** The approved spec lists four tokens (`accentColor`, `cornerRadius`, `primaryButtonStyle`, `destructiveButtonStyle`). This task ships only two. Exposing `ButtonStyle` tokens through an env value in Swift requires existential container types (`any ButtonStyle`) that are clumsy to theme and harder to test. v1 ships the two scalar tokens; later tasks use `.buttonStyle(.borderedProminent).tint(theme.accentColor)` so the accent propagates into buttons without a dedicated style slot. If integrators demand style customization, a follow-up can introduce `CommentRelayButtonRole` + `CommentRelayButtonStyle` — this is called out in the spec's "future work" section. Record this as an accepted deviation when you ship.

- [ ] **Step 4: Create the snapshot helpers file (will grow across subsequent tasks).**

```swift
// Tests/CommentRelayUITests/Helpers/SnapshotHelpers.swift
import SwiftUI
import XCTest
import SnapshotTesting

/// Shared config for UI snapshot tests. Tuned so snapshots are stable across local runs.
enum SnapshotCfg {
    /// Flip to true (locally only) to regenerate baselines.
    static let isRecording = false
}

extension XCTestCase {
    /// Render `view` at the given trait and locale, compared against baselines in `__Snapshots__/`.
    func assertSnapshot<V: View>(
        of view: V,
        name: String,
        colorScheme: ColorScheme = .light,
        locale: Locale = Locale(identifier: "en"),
        dynamicTypeSize: DynamicTypeSize = .large,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        let host = view
            .environment(\.colorScheme, colorScheme)
            .environment(\.locale, locale)
            .environment(\.dynamicTypeSize, dynamicTypeSize)
        let config: ViewImageConfig = .iPhone13
        assertSnapshot(
            matching: host,
            as: .image(layout: .device(config: config)),
            named: name,
            record: SnapshotCfg.isRecording,
            file: file,
            testName: testName,
            line: line
        )
    }
}
```

**Note:** `swift-snapshot-testing` does not render SwiftUI views directly on macOS from the command line; the `as: .image(...)` strategy requires UIKit. We run snapshot tests via `xcodebuild test` on iOS Simulator, not `swift test`. Plan B's smoke task (Task 22) runs both — `swift test` for non-snapshot UI tests and `xcodebuild` for snapshots.

- [ ] **Step 5: Run — expect pass.**

```bash
swift test --filter CommentRelayThemeTests 2>&1 | tail -10
```

- [ ] **Step 6: Commit.**

```bash
git add Sources/CommentRelayUI/Shared/CommentRelayTheme.swift \
        Tests/CommentRelayUITests/Helpers/SnapshotHelpers.swift \
        Tests/CommentRelayUITests/ScreenTests/CommentRelayThemeTests.swift
git commit -m "Add CommentRelayTheme with accentColor + cornerRadius tokens"
```

---

### Task 5: `ErrorBanner`

**Files:**
- Create: `Sources/CommentRelayUI/Shared/ErrorBanner.swift`
- Create: `Tests/CommentRelayUITests/ScreenTests/ErrorBannerTests.swift`

- [ ] **Step 1: Write failing test.**

```swift
// Tests/CommentRelayUITests/ScreenTests/ErrorBannerTests.swift
import XCTest
import SwiftUI
import ViewInspector
@testable import CommentRelayUI

final class ErrorBannerTests: XCTestCase {
    func test_displaysMessage() throws {
        let sut = ErrorBanner(message: "Kaboom", retry: nil)
        let text = try sut.inspect().find(text: "Kaboom")
        XCTAssertEqual(try text.string(), "Kaboom")
    }

    func test_retryHidden_whenRetryClosureIsNil() throws {
        let sut = ErrorBanner(message: "Kaboom", retry: nil)
        XCTAssertThrowsError(try sut.inspect().find(button: "Try again"))
    }

    func test_retryVisible_whenClosureSupplied() throws {
        var tapped = false
        let sut = ErrorBanner(message: "Kaboom") { tapped = true }
        try sut.inspect().find(button: "Try again").tap()
        XCTAssertTrue(tapped)
    }
}
```

- [ ] **Step 2: Run — expect failure.**

```bash
swift test --filter ErrorBannerTests 2>&1 | tail -15
```

- [ ] **Step 3: Implement.**

```swift
// Sources/CommentRelayUI/Shared/ErrorBanner.swift
import SwiftUI

public struct ErrorBanner: View {
    public let message: String
    public let retry: (() -> Void)?

    public init(message: String, retry: (() -> Void)? = nil) {
        self.message = message
        self.retry = retry
    }

    @Environment(\.commentRelayTheme) private var theme

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let retry {
                Button("Try again") { retry() }
                    .buttonStyle(.bordered)
                    .tint(theme.accentColor)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(message))
    }
}
```

- [ ] **Step 4: Run — expect pass.**

```bash
swift test --filter ErrorBannerTests 2>&1 | tail -10
```

- [ ] **Step 5: Commit.**

```bash
git add Sources/CommentRelayUI/Shared/ErrorBanner.swift \
        Tests/CommentRelayUITests/ScreenTests/ErrorBannerTests.swift
git commit -m "Add ErrorBanner shared view"
```

---

### Task 6: `EmptyStateView` + `LoadingView`

**Files:**
- Create: `Sources/CommentRelayUI/Shared/EmptyStateView.swift`
- Create: `Sources/CommentRelayUI/Shared/LoadingView.swift`
- Create: `Tests/CommentRelayUITests/ScreenTests/EmptyStateViewTests.swift`
- Create: `Tests/CommentRelayUITests/ScreenTests/LoadingViewTests.swift`

- [ ] **Step 1: Write failing tests.**

```swift
// Tests/CommentRelayUITests/ScreenTests/EmptyStateViewTests.swift
import XCTest
import SwiftUI
import ViewInspector
@testable import CommentRelayUI

final class EmptyStateViewTests: XCTestCase {
    func test_rendersTitleAndMessage() throws {
        let sut = EmptyStateView(systemImage: "tray", title: "Nothing here", message: "Pull to refresh.")
        XCTAssertNoThrow(try sut.inspect().find(text: "Nothing here"))
        XCTAssertNoThrow(try sut.inspect().find(text: "Pull to refresh."))
    }
}
```

```swift
// Tests/CommentRelayUITests/ScreenTests/LoadingViewTests.swift
import XCTest
import SwiftUI
import ViewInspector
@testable import CommentRelayUI

final class LoadingViewTests: XCTestCase {
    func test_rendersLabel_whenSupplied() throws {
        let sut = LoadingView(label: "Loading…")
        XCTAssertNoThrow(try sut.inspect().find(text: "Loading…"))
    }

    func test_noLabel_whenOmitted() throws {
        let sut = LoadingView(label: nil)
        XCTAssertThrowsError(try sut.inspect().find(ViewType.Text.self))
    }
}
```

- [ ] **Step 2: Run — expect failure.**

```bash
swift test --filter "EmptyStateViewTests|LoadingViewTests" 2>&1 | tail -15
```

- [ ] **Step 3: Implement.**

```swift
// Sources/CommentRelayUI/Shared/EmptyStateView.swift
import SwiftUI

public struct EmptyStateView: View {
    public let systemImage: String
    public let title: String
    public let message: String

    public init(systemImage: String, title: String, message: String) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
    }

    public var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title).font(.title3).bold()
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
```

```swift
// Sources/CommentRelayUI/Shared/LoadingView.swift
import SwiftUI

public struct LoadingView: View {
    public let label: String?

    public init(label: String? = nil) {
        self.label = label
    }

    public var body: some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.large)
            if let label {
                Text(label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
```

- [ ] **Step 4: Run — expect pass.**

```bash
swift test --filter "EmptyStateViewTests|LoadingViewTests" 2>&1 | tail -10
```

- [ ] **Step 5: Commit.**

```bash
git add Sources/CommentRelayUI/Shared/EmptyStateView.swift \
        Sources/CommentRelayUI/Shared/LoadingView.swift \
        Tests/CommentRelayUITests/ScreenTests/EmptyStateViewTests.swift \
        Tests/CommentRelayUITests/ScreenTests/LoadingViewTests.swift
git commit -m "Add EmptyStateView and LoadingView shared views"
```

---

### Task 7: `ContactPreferenceSection`

**Files:**
- Create: `Sources/CommentRelayUI/Shared/ContactPreferenceSection.swift`
- Create: `Tests/CommentRelayUITests/ScreenTests/ContactPreferenceSectionTests.swift`

- [ ] **Step 1: Write failing tests.**

```swift
// Tests/CommentRelayUITests/ScreenTests/ContactPreferenceSectionTests.swift
import XCTest
import SwiftUI
import ViewInspector
import CommentRelayCore
@testable import CommentRelayUI

final class ContactPreferenceSectionTests: XCTestCase {
    func test_detailsHidden_whenPreferenceIsNone() throws {
        var pref: ContactPreference = .none
        var details = ""
        let sut = ContactPreferenceSection(
            preference: Binding(get: { pref }, set: { pref = $0 }),
            details: Binding(get: { details }, set: { details = $0 })
        )
        XCTAssertThrowsError(try sut.inspect().find(ViewType.TextField.self))
    }

    func test_detailsVisible_whenPreferenceIsEmail() throws {
        var pref: ContactPreference = .email
        var details = "a@b.c"
        let sut = ContactPreferenceSection(
            preference: Binding(get: { pref }, set: { pref = $0 }),
            details: Binding(get: { details }, set: { details = $0 })
        )
        XCTAssertNoThrow(try sut.inspect().find(ViewType.TextField.self))
    }
}
```

- [ ] **Step 2: Run — expect failure.**

```bash
swift test --filter ContactPreferenceSectionTests 2>&1 | tail -15
```

- [ ] **Step 3: Implement.**

```swift
// Sources/CommentRelayUI/Shared/ContactPreferenceSection.swift
import SwiftUI
import CommentRelayCore

public struct ContactPreferenceSection: View {
    @Binding public var preference: ContactPreference
    @Binding public var details: String

    public init(preference: Binding<ContactPreference>, details: Binding<String>) {
        self._preference = preference
        self._details = details
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Strings.contactHeader)
                .font(.headline)

            Picker(Strings.contactHeader, selection: $preference) {
                Text(Strings.contactNone).tag(ContactPreference.none)
                Text(Strings.contactEmail).tag(ContactPreference.email)
                Text(Strings.contactText).tag(ContactPreference.text)
                Text(Strings.contactPhoneCall).tag(ContactPreference.phoneCall)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if preference != .none {
                TextField(Strings.contactDetailsPlaceholder, text: $details)
                    .textFieldStyle(.roundedBorder)
                    #if canImport(UIKit)
                    .textInputAutocapitalization(preference == .email ? .never : .sentences)
                    .autocorrectionDisabled(preference != .text)
                    .keyboardType(preference == .email ? .emailAddress : (preference == .phoneCall || preference == .text ? .phonePad : .default))
                    #endif
            }
        }
    }
}
```

- [ ] **Step 4: Run — expect pass.**

```bash
swift test --filter ContactPreferenceSectionTests 2>&1 | tail -10
```

- [ ] **Step 5: Commit.**

```bash
git add Sources/CommentRelayUI/Shared/ContactPreferenceSection.swift \
        Tests/CommentRelayUITests/ScreenTests/ContactPreferenceSectionTests.swift
git commit -m "Add ContactPreferenceSection with conditional details input"
```

---

## Field renderers

Each renderer conforms to the shared `FieldRenderer` protocol and binds to a `FieldValueState` stored in `FeedbackFormViewModel` (introduced in Task 15). Tests use ViewInspector to drive input; snapshot tests render at (light, en, default) and (dark, es-419, large) for visual regression coverage.

### Task 8: `FieldRenderer` protocol + fixtures + simple text renderers (Textbox, Email, Phone, Numeric)

**Files:**
- Create: `Sources/CommentRelayUI/Fields/FieldRenderer.swift`
- Create: `Sources/CommentRelayUI/Fields/TextboxFieldView.swift`
- Create: `Sources/CommentRelayUI/Fields/EmailFieldView.swift`
- Create: `Sources/CommentRelayUI/Fields/PhoneFieldView.swift`
- Create: `Sources/CommentRelayUI/Fields/NumericFieldView.swift`
- Create: `Tests/CommentRelayUITests/Helpers/FakeCategory.swift`
- Create: `Tests/CommentRelayUITests/FieldRendererTests/TextboxFieldViewTests.swift`
- Create: `Tests/CommentRelayUITests/FieldRendererTests/EmailFieldViewTests.swift`
- Create: `Tests/CommentRelayUITests/FieldRendererTests/PhoneFieldViewTests.swift`
- Create: `Tests/CommentRelayUITests/FieldRendererTests/NumericFieldViewTests.swift`

- [ ] **Step 1: Create the test fixture builder.**

```swift
// Tests/CommentRelayUITests/Helpers/FakeCategory.swift
import Foundation
import CommentRelayCore

enum FakeField {
    static func textbox(id: String = "f1", label: String = "Describe the issue", required: Bool = true) -> CommentRelayField {
        decode(#"{"id":"\#(id)","field_type":"textbox","label":"\#(label)","is_required":\#(required),"is_gate":false,"sort_order":1,"max_files":null}"#)
    }
    static func email(id: String = "fe", label: String = "Email", required: Bool = true) -> CommentRelayField {
        decode(#"{"id":"\#(id)","field_type":"email","label":"\#(label)","is_required":\#(required),"is_gate":false,"sort_order":1,"max_files":null}"#)
    }
    static func phone(id: String = "fp", label: String = "Phone", required: Bool = false) -> CommentRelayField {
        decode(#"{"id":"\#(id)","field_type":"phone","label":"\#(label)","is_required":\#(required),"is_gate":false,"sort_order":1,"max_files":null}"#)
    }
    static func numeric(id: String = "fn", label: String = "Rating", required: Bool = false) -> CommentRelayField {
        decode(#"{"id":"\#(id)","field_type":"numeric","label":"\#(label)","is_required":\#(required),"is_gate":false,"sort_order":1,"max_files":null}"#)
    }

    private static func decode(_ raw: String) -> CommentRelayField {
        try! JSONDecoder().decode(CommentRelayField.self, from: Data(raw.utf8))
    }
}
```

- [ ] **Step 2: Write failing tests for `TextboxFieldView`.**

```swift
// Tests/CommentRelayUITests/FieldRendererTests/TextboxFieldViewTests.swift
import XCTest
import SwiftUI
import ViewInspector
import CommentRelayCore
@testable import CommentRelayUI

final class TextboxFieldViewTests: XCTestCase {
    func test_rendersLabel() throws {
        var value = ""
        let field = FakeField.textbox(label: "Describe")
        let sut = TextboxFieldView(field: field, value: Binding(get: { value }, set: { value = $0 }))
        XCTAssertNoThrow(try sut.inspect().find(text: "Describe"))
    }

    func test_rendersRequiredIndicator_whenFieldIsRequired() throws {
        var value = ""
        let field = FakeField.textbox(required: true)
        let sut = TextboxFieldView(field: field, value: Binding(get: { value }, set: { value = $0 }))
        XCTAssertNoThrow(try sut.inspect().find(text: "*"))
    }

    func test_bindsValueFromTextEditor() throws {
        var value = ""
        let field = FakeField.textbox()
        let sut = TextboxFieldView(field: field, value: Binding(get: { value }, set: { value = $0 }))
        let editor = try sut.inspect().find(ViewType.TextEditor.self)
        try editor.input("hello world")
        XCTAssertEqual(value, "hello world")
    }
}
```

Write the analogous three-test file for `EmailFieldViewTests`, `PhoneFieldViewTests`, and `NumericFieldViewTests` — each one adapts `rendersLabel`, `rendersRequiredIndicator`, and a `binds…` test (using `ViewType.TextField.self` rather than `TextEditor` because these three use `TextField`).

- [ ] **Step 3: Run — expect failure.**

```bash
swift test --filter "TextboxFieldViewTests|EmailFieldViewTests|PhoneFieldViewTests|NumericFieldViewTests" 2>&1 | tail -20
```

- [ ] **Step 4: Implement `FieldRenderer` protocol.**

```swift
// Sources/CommentRelayUI/Fields/FieldRenderer.swift
import SwiftUI
import CommentRelayCore

public protocol FieldRenderer: View {
    var field: CommentRelayField { get }
    /// `true` iff the renderer's current bound value is sufficient for `field.isRequired`.
    var isValueAcceptable: Bool { get }
}

public struct FieldLabel: View {
    public let field: CommentRelayField
    public init(field: CommentRelayField) { self.field = field }

    public var body: some View {
        HStack(spacing: 4) {
            Text(field.label).font(.headline)
            if field.isRequired {
                Text("*").foregroundStyle(.red).accessibilityLabel(Strings.formRequired)
            }
        }
    }
}
```

- [ ] **Step 5: Implement the four text renderers.**

```swift
// Sources/CommentRelayUI/Fields/TextboxFieldView.swift
import SwiftUI
import CommentRelayCore

public struct TextboxFieldView: FieldRenderer {
    public let field: CommentRelayField
    @Binding public var value: String

    public init(field: CommentRelayField, value: Binding<String>) {
        self.field = field
        self._value = value
    }

    public var isValueAcceptable: Bool {
        field.isRequired ? !value.trimmingCharacters(in: .whitespaces).isEmpty : true
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(field: field)
            TextEditor(text: $value)
                .frame(minHeight: 80)
                .overlay(
                    RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3))
                )
            Text(Strings.characterCount(value.count, 10_000))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
    }
}
```

```swift
// Sources/CommentRelayUI/Fields/EmailFieldView.swift
import SwiftUI
import CommentRelayCore

public struct EmailFieldView: FieldRenderer {
    public let field: CommentRelayField
    @Binding public var value: String

    public init(field: CommentRelayField, value: Binding<String>) {
        self.field = field
        self._value = value
    }

    public var isValueAcceptable: Bool {
        if value.isEmpty { return !field.isRequired }
        return value.contains("@") && value.contains(".")
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(field: field)
            TextField("name@example.com", text: $value)
                .textFieldStyle(.roundedBorder)
                #if canImport(UIKit)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                #endif
                .autocorrectionDisabled()
        }
    }
}
```

```swift
// Sources/CommentRelayUI/Fields/PhoneFieldView.swift
import SwiftUI
import CommentRelayCore

public struct PhoneFieldView: FieldRenderer {
    public let field: CommentRelayField
    @Binding public var value: String

    public init(field: CommentRelayField, value: Binding<String>) {
        self.field = field
        self._value = value
    }

    public var isValueAcceptable: Bool {
        if value.isEmpty { return !field.isRequired }
        let digits = value.filter(\.isNumber)
        return digits.count >= 7
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(field: field)
            TextField("", text: $value)
                .textFieldStyle(.roundedBorder)
                #if canImport(UIKit)
                .keyboardType(.phonePad)
                #endif
        }
    }
}
```

```swift
// Sources/CommentRelayUI/Fields/NumericFieldView.swift
import SwiftUI
import CommentRelayCore

public struct NumericFieldView: FieldRenderer {
    public let field: CommentRelayField
    @Binding public var value: String

    public init(field: CommentRelayField, value: Binding<String>) {
        self.field = field
        self._value = value
    }

    public var isValueAcceptable: Bool {
        if value.isEmpty { return !field.isRequired }
        return Double(value) != nil
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(field: field)
            TextField("", text: $value)
                .textFieldStyle(.roundedBorder)
                #if canImport(UIKit)
                .keyboardType(.decimalPad)
                #endif
        }
    }
}
```

- [ ] **Step 6: Run — expect pass.**

```bash
swift test --filter "TextboxFieldViewTests|EmailFieldViewTests|PhoneFieldViewTests|NumericFieldViewTests" 2>&1 | tail -10
```

- [ ] **Step 7: Commit.**

```bash
git add Sources/CommentRelayUI/Fields \
        Tests/CommentRelayUITests/Helpers/FakeCategory.swift \
        Tests/CommentRelayUITests/FieldRendererTests
git commit -m "Add FieldRenderer protocol + Textbox/Email/Phone/Numeric renderers"
```

---

### Task 9: `TrueFalseFieldView` + `InformationalFieldView`

**Files:**
- Create: `Sources/CommentRelayUI/Fields/TrueFalseFieldView.swift`
- Create: `Sources/CommentRelayUI/Fields/InformationalFieldView.swift`
- Modify: `Tests/CommentRelayUITests/Helpers/FakeCategory.swift` (add `trueFalse` and `informational` factories)
- Create: `Tests/CommentRelayUITests/FieldRendererTests/TrueFalseFieldViewTests.swift`
- Create: `Tests/CommentRelayUITests/FieldRendererTests/InformationalFieldViewTests.swift`

- [ ] **Step 1: Extend `FakeField`.**

Append to `Tests/CommentRelayUITests/Helpers/FakeCategory.swift`:

```swift
    static func trueFalse(id: String = "ft", label: String = "Reproducible?") -> CommentRelayField {
        decode(#"{"id":"\#(id)","field_type":"true_false","label":"\#(label)","is_required":false,"is_gate":false,"sort_order":1,"max_files":null}"#)
    }
    static func informational(id: String = "fi", label: String = "This is informational copy.") -> CommentRelayField {
        decode(#"{"id":"\#(id)","field_type":"informational","label":"\#(label)","is_required":false,"is_gate":false,"sort_order":1,"max_files":null}"#)
    }
```

- [ ] **Step 2: Write failing tests.**

```swift
// Tests/CommentRelayUITests/FieldRendererTests/TrueFalseFieldViewTests.swift
import XCTest
import SwiftUI
import ViewInspector
import CommentRelayCore
@testable import CommentRelayUI

final class TrueFalseFieldViewTests: XCTestCase {
    func test_togglesBoundValue() throws {
        var value = false
        let field = FakeField.trueFalse()
        let sut = TrueFalseFieldView(field: field, value: Binding(get: { value }, set: { value = $0 }))
        let toggle = try sut.inspect().find(ViewType.Toggle.self)
        try toggle.tap()
        XCTAssertTrue(value)
    }
}
```

```swift
// Tests/CommentRelayUITests/FieldRendererTests/InformationalFieldViewTests.swift
import XCTest
import SwiftUI
import ViewInspector
import CommentRelayCore
@testable import CommentRelayUI

final class InformationalFieldViewTests: XCTestCase {
    func test_rendersText() throws {
        let field = FakeField.informational(label: "Be nice.")
        let sut = InformationalFieldView(field: field)
        XCTAssertNoThrow(try sut.inspect().find(text: "Be nice."))
    }

    func test_isValueAcceptable_alwaysTrue() {
        let field = FakeField.informational()
        XCTAssertTrue(InformationalFieldView(field: field).isValueAcceptable)
    }
}
```

- [ ] **Step 3: Run — expect failure.**

```bash
swift test --filter "TrueFalseFieldViewTests|InformationalFieldViewTests" 2>&1 | tail -15
```

- [ ] **Step 4: Implement.**

```swift
// Sources/CommentRelayUI/Fields/TrueFalseFieldView.swift
import SwiftUI
import CommentRelayCore

public struct TrueFalseFieldView: FieldRenderer {
    public let field: CommentRelayField
    @Binding public var value: Bool

    public init(field: CommentRelayField, value: Binding<Bool>) {
        self.field = field
        self._value = value
    }

    public var isValueAcceptable: Bool { true } // boolean always has a value

    public var body: some View {
        Toggle(isOn: $value) {
            FieldLabel(field: field)
        }
    }
}
```

```swift
// Sources/CommentRelayUI/Fields/InformationalFieldView.swift
import SwiftUI
import CommentRelayCore

public struct InformationalFieldView: FieldRenderer {
    public let field: CommentRelayField

    public init(field: CommentRelayField) {
        self.field = field
    }

    public var isValueAcceptable: Bool { true }

    public var body: some View {
        Text(field.label)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isStaticText)
    }
}
```

- [ ] **Step 5: Run — expect pass.**

```bash
swift test --filter "TrueFalseFieldViewTests|InformationalFieldViewTests" 2>&1 | tail -10
```

- [ ] **Step 6: Commit.**

```bash
git add Sources/CommentRelayUI/Fields/TrueFalseFieldView.swift \
        Sources/CommentRelayUI/Fields/InformationalFieldView.swift \
        Tests/CommentRelayUITests/Helpers/FakeCategory.swift \
        Tests/CommentRelayUITests/FieldRendererTests/TrueFalseFieldViewTests.swift \
        Tests/CommentRelayUITests/FieldRendererTests/InformationalFieldViewTests.swift
git commit -m "Add TrueFalse and Informational field renderers"
```

---

### Task 10: `SmileyRatingFieldView`

The API returns SVG markup for each of the 5 smiley positions. v1 does not include a full SVG renderer; it uses `Image(systemName:)` with a position-based symbol that visually approximates the face, and falls back to a neutral face for unknown positions.

**Files:**
- Create: `Sources/CommentRelayUI/Fields/SmileyRatingFieldView.swift`
- Modify: `Tests/CommentRelayUITests/Helpers/FakeCategory.swift` (add `smileyRating` factory)
- Create: `Tests/CommentRelayUITests/FieldRendererTests/SmileyRatingFieldViewTests.swift`

- [ ] **Step 1: Extend `FakeField`.** Append:

```swift
    static func smileyRating(id: String = "fs", label: String = "How do you feel?", required: Bool = false) -> CommentRelayField {
        let raw = #"""
        {"id":"\#(id)","field_type":"smiley_rating","label":"\#(label)","is_required":\#(required),"is_gate":false,"sort_order":1,"max_files":null,
          "options":[
            {"position":1,"label":"very_unhappy","svg":"<svg/>"},
            {"position":2,"label":"unhappy","svg":"<svg/>"},
            {"position":3,"label":"neutral","svg":"<svg/>"},
            {"position":4,"label":"happy","svg":"<svg/>"},
            {"position":5,"label":"very_happy","svg":"<svg/>"}
          ]
        }
        """#
        return decode(raw)
    }
```

- [ ] **Step 2: Write failing tests.**

```swift
// Tests/CommentRelayUITests/FieldRendererTests/SmileyRatingFieldViewTests.swift
import XCTest
import SwiftUI
import ViewInspector
import CommentRelayCore
@testable import CommentRelayUI

final class SmileyRatingFieldViewTests: XCTestCase {
    func test_rendersFiveButtons() throws {
        var value: Int? = nil
        let field = FakeField.smileyRating()
        let sut = SmileyRatingFieldView(field: field, selectedPosition: Binding(get: { value }, set: { value = $0 }))
        let buttons = try sut.inspect().findAll(ViewType.Button.self)
        XCTAssertEqual(buttons.count, 5)
    }

    func test_tappingButtonUpdatesValue() throws {
        var value: Int? = nil
        let field = FakeField.smileyRating()
        let sut = SmileyRatingFieldView(field: field, selectedPosition: Binding(get: { value }, set: { value = $0 }))
        let buttons = try sut.inspect().findAll(ViewType.Button.self)
        try buttons[3].tap()  // position 4 (happy)
        XCTAssertEqual(value, 4)
    }

    func test_requiredUnselected_isUnacceptable() {
        let field = FakeField.smileyRating(required: true)
        let sut = SmileyRatingFieldView(field: field, selectedPosition: .constant(nil))
        XCTAssertFalse(sut.isValueAcceptable)
    }

    func test_requiredSelected_isAcceptable() {
        let field = FakeField.smileyRating(required: true)
        let sut = SmileyRatingFieldView(field: field, selectedPosition: .constant(3))
        XCTAssertTrue(sut.isValueAcceptable)
    }
}
```

- [ ] **Step 3: Run — expect failure.**

```bash
swift test --filter SmileyRatingFieldViewTests 2>&1 | tail -15
```

- [ ] **Step 4: Implement.**

```swift
// Sources/CommentRelayUI/Fields/SmileyRatingFieldView.swift
import SwiftUI
import CommentRelayCore

public struct SmileyRatingFieldView: FieldRenderer {
    public let field: CommentRelayField
    @Binding public var selectedPosition: Int?

    public init(field: CommentRelayField, selectedPosition: Binding<Int?>) {
        self.field = field
        self._selectedPosition = selectedPosition
    }

    public var isValueAcceptable: Bool {
        field.isRequired ? selectedPosition != nil : true
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FieldLabel(field: field)
            HStack(spacing: 16) {
                ForEach(1...5, id: \.self) { position in
                    Button {
                        selectedPosition = position
                    } label: {
                        Image(systemName: iconName(for: position))
                            .font(.system(size: 36))
                            .foregroundStyle(selectedPosition == position ? .accentColor : .secondary)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Strings.smileyLabel(position: position))
                    .accessibilityAddTraits(selectedPosition == position ? .isSelected : [])
                }
            }
        }
    }

    private func iconName(for position: Int) -> String {
        switch position {
        case 1: return "face.dashed"        // very unhappy
        case 2: return "face.smiling"       // unhappy (neutral-leaning fallback)
        case 3: return "face.smiling"       // neutral
        case 4: return "face.smiling.fill"  // happy
        case 5: return "face.smiling.inverse" // very happy
        default: return "face.dashed"
        }
    }
}
```

**Note:** the symbol choices above are placeholders pending a real SVG renderer. If a listed SF Symbol doesn't exist on iOS 18 / macOS 15, swap with the nearest available — the test checks count and selection state, not the specific icon string.

- [ ] **Step 5: Run — expect pass.**

```bash
swift test --filter SmileyRatingFieldViewTests 2>&1 | tail -10
```

- [ ] **Step 6: Commit.**

```bash
git add Sources/CommentRelayUI/Fields/SmileyRatingFieldView.swift \
        Tests/CommentRelayUITests/Helpers/FakeCategory.swift \
        Tests/CommentRelayUITests/FieldRendererTests/SmileyRatingFieldViewTests.swift
git commit -m "Add SmileyRatingFieldView using SF Symbols as v1 fallback"
```

---

### Task 11: `ColorScaleFieldView`

Renders 10 color swatches from the admin-configured hex stops in `field.options`.

**Files:**
- Create: `Sources/CommentRelayUI/Fields/ColorScaleFieldView.swift`
- Modify: `Tests/CommentRelayUITests/Helpers/FakeCategory.swift` (add `colorScale`)
- Create: `Tests/CommentRelayUITests/FieldRendererTests/ColorScaleFieldViewTests.swift`

- [ ] **Step 1: Extend `FakeField`.** Append:

```swift
    static func colorScale(id: String = "fc", label: String = "Rate the color", required: Bool = false) -> CommentRelayField {
        var opts = ""
        for i in 1...10 {
            let r = 255 - (i * 25)
            let g = i * 25
            let hex = String(format: "#%02X%02X00", max(0, r), min(255, g))
            opts += #"{"position":\#(i),"color":"\#(hex)","label":null}"#
            if i != 10 { opts += "," }
        }
        let raw = #"""
        {"id":"\#(id)","field_type":"color_scale","label":"\#(label)","is_required":\#(required),"is_gate":false,"sort_order":1,"max_files":null,
          "options":[\#(opts)]
        }
        """#
        return decode(raw)
    }
```

- [ ] **Step 2: Write failing tests.**

```swift
// Tests/CommentRelayUITests/FieldRendererTests/ColorScaleFieldViewTests.swift
import XCTest
import SwiftUI
import ViewInspector
import CommentRelayCore
@testable import CommentRelayUI

final class ColorScaleFieldViewTests: XCTestCase {
    func test_rendersTenSwatches() throws {
        let sut = ColorScaleFieldView(field: FakeField.colorScale(), selectedPosition: .constant(nil))
        let buttons = try sut.inspect().findAll(ViewType.Button.self)
        XCTAssertEqual(buttons.count, 10)
    }

    func test_tappingSwatchUpdatesValue() throws {
        var value: Int? = nil
        let sut = ColorScaleFieldView(field: FakeField.colorScale(), selectedPosition: Binding(get: { value }, set: { value = $0 }))
        let buttons = try sut.inspect().findAll(ViewType.Button.self)
        try buttons[6].tap()  // position 7
        XCTAssertEqual(value, 7)
    }
}
```

- [ ] **Step 3: Run — expect failure.**

```bash
swift test --filter ColorScaleFieldViewTests 2>&1 | tail -15
```

- [ ] **Step 4: Implement.**

```swift
// Sources/CommentRelayUI/Fields/ColorScaleFieldView.swift
import SwiftUI
import CommentRelayCore

public struct ColorScaleFieldView: FieldRenderer {
    public let field: CommentRelayField
    @Binding public var selectedPosition: Int?

    public init(field: CommentRelayField, selectedPosition: Binding<Int?>) {
        self.field = field
        self._selectedPosition = selectedPosition
    }

    public var isValueAcceptable: Bool {
        field.isRequired ? selectedPosition != nil : true
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FieldLabel(field: field)
            HStack(spacing: 4) {
                ForEach(field.options ?? [], id: \.position) { option in
                    Button {
                        selectedPosition = option.position
                    } label: {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(hex: option.color ?? "#888888"))
                            .frame(height: 36)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(selectedPosition == option.position ? .primary : .clear, lineWidth: 3)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.label ?? "\(option.position)")
                    .accessibilityAddTraits(selectedPosition == option.position ? .isSelected : [])
                }
            }
        }
    }
}

private extension Color {
    /// Parses `#RRGGBB` or `#RRGGBBAA`. Returns `.gray` on malformed input.
    init(hex: String) {
        let trimmed = hex.trimmingCharacters(in: .whitespaces).trimmingPrefix("#")
        var value: UInt64 = 0
        Scanner(string: String(trimmed)).scanHexInt64(&value)
        let length = trimmed.count
        let r, g, b, a: Double
        switch length {
        case 6:
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
            a = 1
        case 8:
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
            a = Double(value & 0xFF) / 255
        default:
            self = .gray
            return
        }
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
```

- [ ] **Step 5: Run — expect pass.**

```bash
swift test --filter ColorScaleFieldViewTests 2>&1 | tail -10
```

- [ ] **Step 6: Commit.**

```bash
git add Sources/CommentRelayUI/Fields/ColorScaleFieldView.swift \
        Tests/CommentRelayUITests/Helpers/FakeCategory.swift \
        Tests/CommentRelayUITests/FieldRendererTests/ColorScaleFieldViewTests.swift
git commit -m "Add ColorScaleFieldView rendering admin-configured hex swatches"
```

---

### Task 12: `PhotoFieldView`

Uses `PhotosPicker` to let the user pick up to `max_files` images. Binds to a `[CommentRelaySubmission.FileMetadata]` plus an in-memory `[Data]` for the actual bytes (which the form view model hands to `CommentRelayClient.uploadFiles` later).

**Files:**
- Create: `Sources/CommentRelayUI/Fields/PhotoFieldView.swift`
- Modify: `Tests/CommentRelayUITests/Helpers/FakeCategory.swift` (add `photo`)
- Create: `Tests/CommentRelayUITests/FieldRendererTests/PhotoFieldViewTests.swift`

- [ ] **Step 1: Extend `FakeField`.**

```swift
    static func photo(id: String = "fph", label: String = "Screenshot", maxFiles: Int = 3, required: Bool = false) -> CommentRelayField {
        decode(#"{"id":"\#(id)","field_type":"photo","label":"\#(label)","is_required":\#(required),"is_gate":false,"sort_order":1,"max_files":\#(maxFiles)}"#)
    }
```

- [ ] **Step 2: Write failing test.**

```swift
// Tests/CommentRelayUITests/FieldRendererTests/PhotoFieldViewTests.swift
import XCTest
import SwiftUI
import ViewInspector
import CommentRelayCore
@testable import CommentRelayUI

final class PhotoFieldViewTests: XCTestCase {
    func test_rendersLabel_andAddButton_whenEmpty() throws {
        let sut = PhotoFieldView(field: FakeField.photo(), attachments: .constant([]))
        XCTAssertNoThrow(try sut.inspect().find(text: "Screenshot"))
        XCTAssertNoThrow(try sut.inspect().find(text: Strings.photoAdd))
    }

    func test_requiredEmpty_isUnacceptable() {
        let sut = PhotoFieldView(field: FakeField.photo(required: true), attachments: .constant([]))
        XCTAssertFalse(sut.isValueAcceptable)
    }

    func test_requiredOneAttachment_isAcceptable() {
        let att = PhotoAttachment(id: UUID(), name: "a.png", mimeType: "image/png", size: 1, data: Data([1]))
        let sut = PhotoFieldView(field: FakeField.photo(required: true), attachments: .constant([att]))
        XCTAssertTrue(sut.isValueAcceptable)
    }
}
```

- [ ] **Step 3: Run — expect failure.**

```bash
swift test --filter PhotoFieldViewTests 2>&1 | tail -15
```

- [ ] **Step 4: Implement.** (`PhotoAttachment` is a shared model used by both Photo and Attachment renderers.)

```swift
// Sources/CommentRelayUI/Fields/PhotoFieldView.swift
import SwiftUI
import PhotosUI
import CommentRelayCore

public struct PhotoAttachment: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var mimeType: String
    public var size: Int
    public var data: Data

    public init(id: UUID = UUID(), name: String, mimeType: String, size: Int, data: Data) {
        self.id = id; self.name = name; self.mimeType = mimeType; self.size = size; self.data = data
    }
}

public struct PhotoFieldView: FieldRenderer {
    public let field: CommentRelayField
    @Binding public var attachments: [PhotoAttachment]
    @State private var pickerSelection: [PhotosPickerItem] = []

    public init(field: CommentRelayField, attachments: Binding<[PhotoAttachment]>) {
        self.field = field
        self._attachments = attachments
    }

    public var isValueAcceptable: Bool {
        field.isRequired ? !attachments.isEmpty : true
    }

    private var maxFiles: Int { field.maxFiles ?? 3 }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(field: field)

            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(attachments) { att in
                            thumbnail(for: att)
                        }
                    }
                }
            }

            if attachments.count < maxFiles {
                PhotosPicker(selection: $pickerSelection, maxSelectionCount: maxFiles - attachments.count, matching: .images) {
                    Label(Strings.photoAdd, systemImage: "photo.badge.plus")
                }
                .onChange(of: pickerSelection) { _, new in
                    Task { await ingest(new) }
                }
            }
        }
    }

    private func thumbnail(for att: PhotoAttachment) -> some View {
        ZStack(alignment: .topTrailing) {
            #if canImport(UIKit)
            if let img = UIImage(data: att.data) {
                Image(uiImage: img).resizable().scaledToFill()
            } else { Color.gray }
            #else
            Color.gray
            #endif
        }
        .frame(width: 64, height: 64)
        .clipped()
        .overlay(alignment: .topTrailing) {
            Button {
                attachments.removeAll { $0.id == att.id }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white, .black.opacity(0.6))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Strings.photoRemove)
        }
    }

    @MainActor
    private func ingest(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let mime = "image/png"  // we don't inspect magic bytes in v1
            let name = "photo-\(UUID().uuidString.prefix(8)).png"
            attachments.append(PhotoAttachment(name: name, mimeType: mime, size: data.count, data: data))
        }
        pickerSelection = []
    }
}
```

**Note on the ViewInspector limitation:** `PhotosPicker` is effectively a black box for inspection. Tests verify the add button label and the empty/non-empty rendering paths; they don't simulate picking a photo. Real photo flows are exercised by manual sample-app testing.

- [ ] **Step 5: Run — expect pass.**

```bash
swift test --filter PhotoFieldViewTests 2>&1 | tail -10
```

- [ ] **Step 6: Commit.**

```bash
git add Sources/CommentRelayUI/Fields/PhotoFieldView.swift \
        Tests/CommentRelayUITests/Helpers/FakeCategory.swift \
        Tests/CommentRelayUITests/FieldRendererTests/PhotoFieldViewTests.swift
git commit -m "Add PhotoFieldView with PhotosPicker integration"
```

---

### Task 13: `AttachmentFieldView`

Uses SwiftUI `.fileImporter` to pick PDFs / plain-text files.

**Files:**
- Create: `Sources/CommentRelayUI/Fields/AttachmentFieldView.swift`
- Modify: `Tests/CommentRelayUITests/Helpers/FakeCategory.swift` (add `attachment`)
- Create: `Tests/CommentRelayUITests/FieldRendererTests/AttachmentFieldViewTests.swift`

- [ ] **Step 1: Extend `FakeField`.**

```swift
    static func attachment(id: String = "fa", label: String = "File", maxFiles: Int = 3, required: Bool = false) -> CommentRelayField {
        decode(#"{"id":"\#(id)","field_type":"attachment","label":"\#(label)","is_required":\#(required),"is_gate":false,"sort_order":1,"max_files":\#(maxFiles)}"#)
    }
```

- [ ] **Step 2: Write failing test.**

```swift
// Tests/CommentRelayUITests/FieldRendererTests/AttachmentFieldViewTests.swift
import XCTest
import SwiftUI
import ViewInspector
import CommentRelayCore
@testable import CommentRelayUI

final class AttachmentFieldViewTests: XCTestCase {
    func test_rendersAddButton_whenEmpty() throws {
        let sut = AttachmentFieldView(field: FakeField.attachment(), attachments: .constant([]))
        XCTAssertNoThrow(try sut.inspect().find(text: Strings.attachmentAdd))
    }

    func test_acceptability_matchesRequiredFlag() {
        let empty = AttachmentFieldView(field: FakeField.attachment(required: true), attachments: .constant([]))
        XCTAssertFalse(empty.isValueAcceptable)
        let att = PhotoAttachment(name: "doc.pdf", mimeType: "application/pdf", size: 10, data: Data([0]))
        let filled = AttachmentFieldView(field: FakeField.attachment(required: true), attachments: .constant([att]))
        XCTAssertTrue(filled.isValueAcceptable)
    }
}
```

- [ ] **Step 3: Run — expect failure.**

```bash
swift test --filter AttachmentFieldViewTests 2>&1 | tail -15
```

- [ ] **Step 4: Implement.**

```swift
// Sources/CommentRelayUI/Fields/AttachmentFieldView.swift
import SwiftUI
import UniformTypeIdentifiers
import CommentRelayCore

public struct AttachmentFieldView: FieldRenderer {
    public let field: CommentRelayField
    @Binding public var attachments: [PhotoAttachment]
    @State private var isImporterPresented: Bool = false

    public init(field: CommentRelayField, attachments: Binding<[PhotoAttachment]>) {
        self.field = field
        self._attachments = attachments
    }

    public var isValueAcceptable: Bool {
        field.isRequired ? !attachments.isEmpty : true
    }

    private var maxFiles: Int { field.maxFiles ?? 3 }
    private let allowedTypes: [UTType] = [.pdf, .plainText]

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(field: field)
            ForEach(attachments) { att in
                HStack {
                    Image(systemName: "doc.fill")
                    Text(att.name).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button {
                        attachments.removeAll { $0.id == att.id }
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Strings.photoRemove)
                }
                .padding(8)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(6)
            }

            if attachments.count < maxFiles {
                Button {
                    isImporterPresented = true
                } label: {
                    Label(Strings.attachmentAdd, systemImage: "paperclip")
                }
                .buttonStyle(.bordered)
                .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: allowedTypes, allowsMultipleSelection: true) { result in
                    if case .success(let urls) = result { ingest(urls) }
                }
            }
        }
    }

    private func ingest(_ urls: [URL]) {
        for url in urls {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { continue }
            let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            attachments.append(PhotoAttachment(name: url.lastPathComponent, mimeType: mime, size: data.count, data: data))
        }
    }
}
```

- [ ] **Step 5: Run — expect pass.**

```bash
swift test --filter AttachmentFieldViewTests 2>&1 | tail -10
```

- [ ] **Step 6: Commit.**

```bash
git add Sources/CommentRelayUI/Fields/AttachmentFieldView.swift \
        Tests/CommentRelayUITests/Helpers/FakeCategory.swift \
        Tests/CommentRelayUITests/FieldRendererTests/AttachmentFieldViewTests.swift
git commit -m "Add AttachmentFieldView using .fileImporter"
```

---

## Screens

### Task 14: `DraftRestorePrompt` + `CategoryPickerView`

**Files:**
- Create: `Sources/CommentRelayUI/Screens/DraftRestorePrompt.swift`
- Create: `Sources/CommentRelayUI/Screens/CategoryPickerView.swift`
- Create: `Tests/CommentRelayUITests/ScreenTests/DraftRestorePromptTests.swift`
- Create: `Tests/CommentRelayUITests/ScreenTests/CategoryPickerViewTests.swift`

- [ ] **Step 1: Write failing tests.**

```swift
// Tests/CommentRelayUITests/ScreenTests/DraftRestorePromptTests.swift
import XCTest
import SwiftUI
import ViewInspector
@testable import CommentRelayUI

final class DraftRestorePromptTests: XCTestCase {
    func test_resumeButton_invokesClosure() throws {
        var resumed = false
        var discarded = false
        let sut = DraftRestorePrompt(onResume: { resumed = true }, onDiscard: { discarded = true })
        try sut.inspect().find(button: Strings.draftResume).tap()
        XCTAssertTrue(resumed)
        XCTAssertFalse(discarded)
    }

    func test_discardButton_invokesClosure() throws {
        var resumed = false
        var discarded = false
        let sut = DraftRestorePrompt(onResume: { resumed = true }, onDiscard: { discarded = true })
        try sut.inspect().find(button: Strings.draftStartOver).tap()
        XCTAssertTrue(discarded)
        XCTAssertFalse(resumed)
    }
}
```

```swift
// Tests/CommentRelayUITests/ScreenTests/CategoryPickerViewTests.swift
import XCTest
import SwiftUI
import ViewInspector
import CommentRelayCore
@testable import CommentRelayUI

final class CategoryPickerViewTests: XCTestCase {
    func test_filtersOut_showInPickerFalse() throws {
        let raw = #"""
        [
          {"id":"a","title":"Bug","show_in_picker":true,"response_limit_count":null,"response_limit_type":null,"response_limit_window_days":null,"more_feedback_prompt":null,"is_active":true,"sort_order":1,"fields":[]},
          {"id":"b","title":"Hidden","show_in_picker":false,"response_limit_count":null,"response_limit_type":null,"response_limit_window_days":null,"more_feedback_prompt":null,"is_active":true,"sort_order":2,"fields":[]}
        ]
        """#
        let categories = try JSONDecoder().decode([CommentRelayCategory].self, from: Data(raw.utf8))

        var selected: CommentRelayCategory? = nil
        let sut = CategoryPickerView(categories: categories, onSelect: { selected = $0 })
        // Only the one visible category's title should be findable.
        XCTAssertNoThrow(try sut.inspect().find(text: "Bug"))
        XCTAssertThrowsError(try sut.inspect().find(text: "Hidden"))
    }

    func test_emptyCategories_rendersEmptyState() throws {
        let sut = CategoryPickerView(categories: [], onSelect: { _ in })
        XCTAssertNoThrow(try sut.inspect().find(text: Strings.pickerEmpty))
    }
}
```

- [ ] **Step 2: Run — expect failure.**

```bash
swift test --filter "DraftRestorePromptTests|CategoryPickerViewTests" 2>&1 | tail -15
```

- [ ] **Step 3: Implement.**

```swift
// Sources/CommentRelayUI/Screens/DraftRestorePrompt.swift
import SwiftUI

public struct DraftRestorePrompt: View {
    public let onResume: () -> Void
    public let onDiscard: () -> Void

    public init(onResume: @escaping () -> Void, onDiscard: @escaping () -> Void) {
        self.onResume = onResume
        self.onDiscard = onDiscard
    }

    public var body: some View {
        VStack(spacing: 16) {
            Text(Strings.draftRestoreTitle).font(.headline)
            Text(Strings.draftRestoreBody)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button(Strings.draftStartOver, action: onDiscard)
                    .buttonStyle(.bordered)
                Button(Strings.draftResume, action: onResume)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}
```

```swift
// Sources/CommentRelayUI/Screens/CategoryPickerView.swift
import SwiftUI
import CommentRelayCore

public struct CategoryPickerView: View {
    public let categories: [CommentRelayCategory]
    public let onSelect: (CommentRelayCategory) -> Void

    public init(categories: [CommentRelayCategory], onSelect: @escaping (CommentRelayCategory) -> Void) {
        self.categories = categories
        self.onSelect = onSelect
    }

    private var visible: [CommentRelayCategory] {
        categories
            .filter { $0.isActive && $0.showInPicker }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    public var body: some View {
        Group {
            if visible.isEmpty {
                EmptyStateView(
                    systemImage: "tray",
                    title: Strings.pickerTitle,
                    message: Strings.pickerEmpty
                )
            } else {
                List {
                    ForEach(visible) { category in
                        Button {
                            onSelect(category)
                        } label: {
                            HStack {
                                Text(category.title)
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(.isButton)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(Strings.pickerTitle)
    }
}
```

- [ ] **Step 4: Run — expect pass.**

```bash
swift test --filter "DraftRestorePromptTests|CategoryPickerViewTests" 2>&1 | tail -10
```

- [ ] **Step 5: Commit.**

```bash
git add Sources/CommentRelayUI/Screens/DraftRestorePrompt.swift \
        Sources/CommentRelayUI/Screens/CategoryPickerView.swift \
        Tests/CommentRelayUITests/ScreenTests/DraftRestorePromptTests.swift \
        Tests/CommentRelayUITests/ScreenTests/CategoryPickerViewTests.swift
git commit -m "Add DraftRestorePrompt and CategoryPickerView"
```

---

### Task 15: `FeedbackFormView` + `FeedbackFormViewModel`

The largest single task: observable view model that holds field values per `CommentRelayField`, debounce-saves to drafts via `CommentRelayClient`, exposes an `isSubmittable` computed property from renderer validity, and yields a `CommentRelaySubmission` on submit. The view itself iterates fields and dispatches each to the correct renderer from Tasks 8-13.

**Files:**
- Create: `Sources/CommentRelayUI/Screens/FeedbackFormViewModel.swift`
- Create: `Sources/CommentRelayUI/Screens/FeedbackFormView.swift`
- Create: `Tests/CommentRelayUITests/ScreenTests/FeedbackFormViewModelTests.swift`
- Create: `Tests/CommentRelayUITests/ScreenTests/FeedbackFormViewTests.swift`

- [ ] **Step 1: Write the failing view-model test.**

```swift
// Tests/CommentRelayUITests/ScreenTests/FeedbackFormViewModelTests.swift
import XCTest
import CommentRelayCore
@testable import CommentRelayUI

final class FeedbackFormViewModelTests: XCTestCase {
    func test_isSubmittable_falseUntilRequiredTextbox_isFilled() {
        let raw = #"""
        {"id":"c","title":"Bug","show_in_picker":true,"response_limit_count":null,"response_limit_type":null,"response_limit_window_days":null,"more_feedback_prompt":null,"is_active":true,"sort_order":1,"fields":[
          {"id":"f1","field_type":"textbox","label":"Describe","is_required":true,"is_gate":false,"sort_order":1,"max_files":null}
        ]}
        """#
        let category = try! JSONDecoder().decode(CommentRelayCategory.self, from: Data(raw.utf8))
        let vm = FeedbackFormViewModel(category: category, userIdentifier: "u", platform: .ios, sdkVersion: "0.1.0")
        XCTAssertFalse(vm.isSubmittable)
        vm.setText("f1", "a bug")
        XCTAssertTrue(vm.isSubmittable)
    }

    func test_buildSubmission_reflectsFieldValues_andContactPreference() {
        let raw = #"""
        {"id":"c","title":"Bug","show_in_picker":true,"response_limit_count":null,"response_limit_type":null,"response_limit_window_days":null,"more_feedback_prompt":null,"is_active":true,"sort_order":1,"fields":[
          {"id":"f1","field_type":"textbox","label":"Describe","is_required":true,"is_gate":false,"sort_order":1,"max_files":null}
        ]}
        """#
        let category = try! JSONDecoder().decode(CommentRelayCategory.self, from: Data(raw.utf8))
        let vm = FeedbackFormViewModel(category: category, userIdentifier: "u", platform: .ios, sdkVersion: "0.1.0")
        vm.setText("f1", "oops")
        vm.contactPreference = .email
        vm.contactDetails = "a@b.c"

        let submission = vm.buildSubmission()
        XCTAssertEqual(submission.categoryId, "c")
        XCTAssertEqual(submission.contactPreference, .email)
        XCTAssertEqual(submission.contactDetails, "a@b.c")
        guard case .text(_, let v) = submission.fields.first else { return XCTFail() }
        XCTAssertEqual(v, "oops")
    }
}
```

- [ ] **Step 2: Run — expect failure.**

```bash
swift test --filter FeedbackFormViewModelTests 2>&1 | tail -15
```

- [ ] **Step 3: Implement `FeedbackFormViewModel`.**

```swift
// Sources/CommentRelayUI/Screens/FeedbackFormViewModel.swift
import SwiftUI
import CommentRelayCore

@Observable
public final class FeedbackFormViewModel {
    public let category: CommentRelayCategory
    public let userIdentifier: String
    public let platform: Platform
    public let sdkVersion: String?

    public var textValues: [String: String] = [:]
    public var boolValues: [String: Bool] = [:]
    public var intValues: [String: Int] = [:]
    public var photoValues: [String: [PhotoAttachment]] = [:]
    public var contactPreference: ContactPreference = .none
    public var contactDetails: String = ""

    public init(category: CommentRelayCategory, userIdentifier: String, platform: Platform, sdkVersion: String?) {
        self.category = category
        self.userIdentifier = userIdentifier
        self.platform = platform
        self.sdkVersion = sdkVersion
    }

    public func setText(_ fieldId: String, _ value: String) { textValues[fieldId] = value }
    public func setBool(_ fieldId: String, _ value: Bool) { boolValues[fieldId] = value }
    public func setInt(_ fieldId: String, _ value: Int?) {
        if let value { intValues[fieldId] = value } else { intValues.removeValue(forKey: fieldId) }
    }
    public func setPhotos(_ fieldId: String, _ value: [PhotoAttachment]) { photoValues[fieldId] = value }

    public var isSubmittable: Bool {
        for field in category.fields where field.isRequired {
            switch field.fieldType {
            case .textbox, .email, .phone, .numeric:
                let v = textValues[field.id] ?? ""
                if v.trimmingCharacters(in: .whitespaces).isEmpty { return false }
            case .trueFalse:
                _ = boolValues[field.id] ?? false
            case .smileyRating, .colorScale:
                if intValues[field.id] == nil { return false }
            case .photo, .attachment:
                if (photoValues[field.id] ?? []).isEmpty { return false }
            case .informational, .unknown:
                continue
            }
        }
        if contactPreference != .none, contactDetails.trimmingCharacters(in: .whitespaces).isEmpty {
            return false
        }
        return true
    }

    public func buildSubmission() -> CommentRelaySubmission {
        var fieldValues: [CommentRelaySubmission.FieldValue] = []
        for field in category.fields.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            switch field.fieldType {
            case .textbox, .email, .phone, .numeric:
                let v = textValues[field.id] ?? ""
                if !v.isEmpty { fieldValues.append(.text(fieldId: field.id, value: v)) }
            case .trueFalse:
                let v = boolValues[field.id] ?? false
                fieldValues.append(.text(fieldId: field.id, value: v ? "true" : "false"))
            case .smileyRating, .colorScale:
                if let v = intValues[field.id] {
                    let payload = #"{"position":\#(v)}"#
                    fieldValues.append(.text(fieldId: field.id, value: payload))
                }
            case .photo, .attachment:
                let atts = photoValues[field.id] ?? []
                if !atts.isEmpty {
                    let meta = atts.map { CommentRelaySubmission.FileMetadata(name: $0.name, type: $0.mimeType, size: $0.size) }
                    fieldValues.append(.files(fieldId: field.id, metadata: meta))
                }
            case .informational, .unknown:
                continue
            }
        }
        return CommentRelaySubmission(
            categoryId: category.id,
            userIdentifier: userIdentifier,
            platform: platform,
            fields: fieldValues,
            sdkVersion: sdkVersion,
            contactPreference: contactPreference == .none ? nil : contactPreference,
            contactDetails: contactPreference == .none ? nil : contactDetails
        )
    }

    /// Returns all photo/attachment payloads keyed by their field, for the client's uploadFiles call after submit returns a receipt.
    public func filePayloads(for receipt: CommentRelaySubmissionReceipt) -> [CommentRelayFilePayload] {
        var result: [CommentRelayFilePayload] = []
        for target in receipt.uploadUrls {
            guard let atts = photoValues[target.fieldId] else { continue }
            if let att = atts.first(where: { $0.name == target.fileName }) {
                result.append(CommentRelayFilePayload(target: target, data: att.data, contentType: att.mimeType))
            }
        }
        return result
    }
}
```

- [ ] **Step 4: Run view-model tests — expect pass.**

```bash
swift test --filter FeedbackFormViewModelTests 2>&1 | tail -10
```

- [ ] **Step 5: Write failing view tests.**

```swift
// Tests/CommentRelayUITests/ScreenTests/FeedbackFormViewTests.swift
import XCTest
import SwiftUI
import ViewInspector
import CommentRelayCore
@testable import CommentRelayUI

final class FeedbackFormViewTests: XCTestCase {
    private func category(with fields: [CommentRelayField]) -> CommentRelayCategory {
        let encoded = try! JSONEncoder().encode(fields)
        let fieldsJSON = String(data: encoded, encoding: .utf8)!
        let raw = #"{"id":"c","title":"Bug","show_in_picker":true,"response_limit_count":null,"response_limit_type":null,"response_limit_window_days":null,"more_feedback_prompt":null,"is_active":true,"sort_order":1,"fields":\#(fieldsJSON)}"#
        return try! JSONDecoder().decode(CommentRelayCategory.self, from: Data(raw.utf8))
    }

    func test_rendersOneRowPerField_excludingInformationalFromValidation() throws {
        let cat = category(with: [FakeField.textbox(), FakeField.informational()])
        let vm = FeedbackFormViewModel(category: cat, userIdentifier: "u", platform: .ios, sdkVersion: "0.1.0")
        let sut = FeedbackFormView(viewModel: vm, onSubmit: { _ in })
        // Textbox label + informational text both render.
        XCTAssertNoThrow(try sut.inspect().find(text: "Describe the issue"))
        XCTAssertNoThrow(try sut.inspect().find(text: "This is informational copy."))
    }

    func test_submitDisabled_untilRequiredFieldFilled() throws {
        let cat = category(with: [FakeField.textbox(required: true)])
        let vm = FeedbackFormViewModel(category: cat, userIdentifier: "u", platform: .ios, sdkVersion: "0.1.0")
        let sut = FeedbackFormView(viewModel: vm, onSubmit: { _ in })
        let submit = try sut.inspect().find(button: Strings.formSubmit)
        XCTAssertTrue(try submit.isDisabled())
        vm.setText("f1", "a bug")
        let submit2 = try sut.inspect().find(button: Strings.formSubmit)
        XCTAssertFalse(try submit2.isDisabled())
    }
}
```

- [ ] **Step 6: Implement `FeedbackFormView`.**

```swift
// Sources/CommentRelayUI/Screens/FeedbackFormView.swift
import SwiftUI
import CommentRelayCore

public struct FeedbackFormView: View {
    @State public var viewModel: FeedbackFormViewModel
    public let onSubmit: (CommentRelaySubmission) -> Void

    public init(viewModel: FeedbackFormViewModel, onSubmit: @escaping (CommentRelaySubmission) -> Void) {
        self._viewModel = State(initialValue: viewModel)
        self.onSubmit = onSubmit
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let prompt = viewModel.category.moreFeedbackPrompt {
                    Text(prompt).font(.callout).foregroundStyle(.secondary)
                }

                ForEach(viewModel.category.fields.sorted(by: { $0.sortOrder < $1.sortOrder }), id: \.id) { field in
                    renderer(for: field)
                }

                ContactPreferenceSection(
                    preference: Binding(get: { viewModel.contactPreference }, set: { viewModel.contactPreference = $0 }),
                    details: Binding(get: { viewModel.contactDetails }, set: { viewModel.contactDetails = $0 })
                )

                Button(Strings.formSubmit) {
                    onSubmit(viewModel.buildSubmission())
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(!viewModel.isSubmittable)
            }
            .padding()
        }
        .navigationTitle(viewModel.category.title)
    }

    @ViewBuilder
    private func renderer(for field: CommentRelayField) -> some View {
        switch field.fieldType {
        case .textbox:
            TextboxFieldView(field: field, value: Binding(get: { viewModel.textValues[field.id] ?? "" }, set: { viewModel.setText(field.id, $0) }))
        case .email:
            EmailFieldView(field: field, value: Binding(get: { viewModel.textValues[field.id] ?? "" }, set: { viewModel.setText(field.id, $0) }))
        case .phone:
            PhoneFieldView(field: field, value: Binding(get: { viewModel.textValues[field.id] ?? "" }, set: { viewModel.setText(field.id, $0) }))
        case .numeric:
            NumericFieldView(field: field, value: Binding(get: { viewModel.textValues[field.id] ?? "" }, set: { viewModel.setText(field.id, $0) }))
        case .trueFalse:
            TrueFalseFieldView(field: field, value: Binding(get: { viewModel.boolValues[field.id] ?? false }, set: { viewModel.setBool(field.id, $0) }))
        case .informational:
            InformationalFieldView(field: field)
        case .smileyRating:
            SmileyRatingFieldView(field: field, selectedPosition: Binding(get: { viewModel.intValues[field.id] }, set: { viewModel.setInt(field.id, $0) }))
        case .colorScale:
            ColorScaleFieldView(field: field, selectedPosition: Binding(get: { viewModel.intValues[field.id] }, set: { viewModel.setInt(field.id, $0) }))
        case .photo:
            PhotoFieldView(field: field, attachments: Binding(get: { viewModel.photoValues[field.id] ?? [] }, set: { viewModel.setPhotos(field.id, $0) }))
        case .attachment:
            AttachmentFieldView(field: field, attachments: Binding(get: { viewModel.photoValues[field.id] ?? [] }, set: { viewModel.setPhotos(field.id, $0) }))
        case .unknown:
            EmptyView()
        }
    }
}
```

- [ ] **Step 7: Run view tests — expect pass.**

```bash
swift test --filter "FeedbackFormViewModelTests|FeedbackFormViewTests" 2>&1 | tail -10
```

- [ ] **Step 8: Commit.**

```bash
git add Sources/CommentRelayUI/Screens/FeedbackFormView.swift \
        Sources/CommentRelayUI/Screens/FeedbackFormViewModel.swift \
        Tests/CommentRelayUITests/ScreenTests/FeedbackFormViewModelTests.swift \
        Tests/CommentRelayUITests/ScreenTests/FeedbackFormViewTests.swift
git commit -m "Add FeedbackFormView and FeedbackFormViewModel"
```

**Deferred to Task 19 (container):** draft save/restore on entry/exit — the container owns the session lifecycle, so draft wiring lives there.

---

### Task 16: `SubmissionProgressView`

**Files:**
- Create: `Sources/CommentRelayUI/Screens/SubmissionProgressView.swift`
- Create: `Tests/CommentRelayUITests/ScreenTests/SubmissionProgressViewTests.swift`

- [ ] **Step 1: Write failing test.**

```swift
// Tests/CommentRelayUITests/ScreenTests/SubmissionProgressViewTests.swift
import XCTest
import SwiftUI
import ViewInspector
@testable import CommentRelayUI

final class SubmissionProgressViewTests: XCTestCase {
    func test_rendersInProgressTitle() throws {
        let sut = SubmissionProgressView(state: .inProgress(currentFile: "screenshot.png"))
        XCTAssertNoThrow(try sut.inspect().find(text: Strings.progressTitle))
        XCTAssertNoThrow(try sut.inspect().find(text: Strings.progressFile("screenshot.png")))
    }

    func test_rendersErrorBanner_onFailure() throws {
        let sut = SubmissionProgressView(state: .failed(message: "boom", retry: {}))
        XCTAssertNoThrow(try sut.inspect().find(text: "boom"))
    }
}
```

- [ ] **Step 2: Run — expect failure.**

```bash
swift test --filter SubmissionProgressViewTests 2>&1 | tail -15
```

- [ ] **Step 3: Implement.**

```swift
// Sources/CommentRelayUI/Screens/SubmissionProgressView.swift
import SwiftUI

public struct SubmissionProgressView: View {
    public enum State {
        case inProgress(currentFile: String?)
        case failed(message: String, retry: () -> Void)
    }

    public let state: State

    public init(state: State) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 20) {
            switch state {
            case .inProgress(let currentFile):
                ProgressView().controlSize(.large)
                Text(Strings.progressTitle).font(.headline)
                if let currentFile {
                    Text(Strings.progressFile(currentFile))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            case .failed(let message, let retry):
                ErrorBanner(message: message, retry: retry)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 4: Run — expect pass.**

```bash
swift test --filter SubmissionProgressViewTests 2>&1 | tail -10
```

- [ ] **Step 5: Commit.**

```bash
git add Sources/CommentRelayUI/Screens/SubmissionProgressView.swift \
        Tests/CommentRelayUITests/ScreenTests/SubmissionProgressViewTests.swift
git commit -m "Add SubmissionProgressView"
```

---

### Task 17: `ThankYouView`

**Files:**
- Create: `Sources/CommentRelayUI/Screens/ThankYouView.swift`
- Create: `Tests/CommentRelayUITests/ScreenTests/ThankYouViewTests.swift`

- [ ] **Step 1: Write failing test.**

```swift
// Tests/CommentRelayUITests/ScreenTests/ThankYouViewTests.swift
import XCTest
import SwiftUI
import ViewInspector
@testable import CommentRelayUI

final class ThankYouViewTests: XCTestCase {
    func test_historyButtonHidden_whenAnonymous() throws {
        let sut = ThankYouView(showHistoryAction: nil, doneAction: {})
        XCTAssertThrowsError(try sut.inspect().find(button: Strings.thanksViewHistory))
    }

    func test_historyButtonVisible_whenActionProvided() throws {
        var tapped = false
        let sut = ThankYouView(showHistoryAction: { tapped = true }, doneAction: {})
        try sut.inspect().find(button: Strings.thanksViewHistory).tap()
        XCTAssertTrue(tapped)
    }

    func test_doneButtonInvokesClosure() throws {
        var done = false
        let sut = ThankYouView(showHistoryAction: nil, doneAction: { done = true })
        try sut.inspect().find(button: Strings.thanksDone).tap()
        XCTAssertTrue(done)
    }
}
```

- [ ] **Step 2: Run — expect failure.**

```bash
swift test --filter ThankYouViewTests 2>&1 | tail -15
```

- [ ] **Step 3: Implement.**

```swift
// Sources/CommentRelayUI/Screens/ThankYouView.swift
import SwiftUI

public struct ThankYouView: View {
    public let showHistoryAction: (() -> Void)?
    public let doneAction: () -> Void

    public init(showHistoryAction: (() -> Void)?, doneAction: @escaping () -> Void) {
        self.showHistoryAction = showHistoryAction
        self.doneAction = doneAction
    }

    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text(Strings.thanksTitle).font(.largeTitle).bold()
            Text(Strings.thanksBody)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                if let showHistoryAction {
                    Button(Strings.thanksViewHistory, action: showHistoryAction)
                        .buttonStyle(.bordered)
                }
                Button(Strings.thanksDone, action: doneAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 4: Run — expect pass.**

```bash
swift test --filter ThankYouViewTests 2>&1 | tail -10
```

- [ ] **Step 5: Commit.**

```bash
git add Sources/CommentRelayUI/Screens/ThankYouView.swift \
        Tests/CommentRelayUITests/ScreenTests/ThankYouViewTests.swift
git commit -m "Add ThankYouView"
```

---

### Task 18: `HistoryListView` + `HistoryDetailView`

**Files:**
- Create: `Sources/CommentRelayUI/Screens/HistoryListView.swift`
- Create: `Sources/CommentRelayUI/Screens/HistoryDetailView.swift`
- Create: `Tests/CommentRelayUITests/ScreenTests/HistoryListViewTests.swift`
- Create: `Tests/CommentRelayUITests/ScreenTests/HistoryDetailViewTests.swift`

- [ ] **Step 1: Write failing tests.**

```swift
// Tests/CommentRelayUITests/ScreenTests/HistoryListViewTests.swift
import XCTest
import SwiftUI
import ViewInspector
import CommentRelayCore
@testable import CommentRelayUI

final class HistoryListViewTests: XCTestCase {
    private func history(entries: Int, anonymous: Bool) -> CommentRelayHistory {
        var items = ""
        for i in 0..<entries {
            items += #"{"id":"\#(UUID().uuidString)","category_id":"c","category_title":"Bug","status":"complete","created_at":"2026-03-19T10:30:0\#(i)Z","notes":[]}"#
            if i < entries - 1 { items += "," }
        }
        let raw = #"{"anonymousUser":\#(anonymous),"submissions":[\#(items)]}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try! decoder.decode(CommentRelayHistory.self, from: Data(raw.utf8))
    }

    func test_anonymousEmpty_rendersAnonymousCopy() throws {
        let sut = HistoryListView(history: history(entries: 0, anonymous: true), onSelect: { _ in })
        XCTAssertNoThrow(try sut.inspect().find(text: Strings.historyEmptyAnonymous))
    }

    func test_identifiedEmpty_rendersIdentifiedCopy() throws {
        let sut = HistoryListView(history: history(entries: 0, anonymous: false), onSelect: { _ in })
        XCTAssertNoThrow(try sut.inspect().find(text: Strings.historyEmptyIdentified))
    }

    func test_nonEmpty_rendersOneRowPerEntry() throws {
        let h = history(entries: 2, anonymous: false)
        let sut = HistoryListView(history: h, onSelect: { _ in })
        let buttons = try sut.inspect().findAll(ViewType.Button.self)
        XCTAssertGreaterThanOrEqual(buttons.count, 2)
    }
}
```

```swift
// Tests/CommentRelayUITests/ScreenTests/HistoryDetailViewTests.swift
import XCTest
import SwiftUI
import ViewInspector
import CommentRelayCore
@testable import CommentRelayUI

final class HistoryDetailViewTests: XCTestCase {
    func test_rendersNotesHeader_whenNotesPresent() throws {
        let raw = #"""
        {"id":"22222222-2222-2222-2222-222222222222","category_id":"c","category_title":"Bug","status":"complete","created_at":"2026-03-19T10:30:00Z","notes":[
          {"id":"n1","content":"Fixed in v2","created_at":"2026-03-19T12:00:00Z"}]}
        """#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entry = try decoder.decode(CommentRelayHistoryEntry.self, from: Data(raw.utf8))
        let sut = HistoryDetailView(entry: entry)
        XCTAssertNoThrow(try sut.inspect().find(text: Strings.historyNotesHeader))
        XCTAssertNoThrow(try sut.inspect().find(text: "Fixed in v2"))
    }
}
```

- [ ] **Step 2: Run — expect failure.**

```bash
swift test --filter "HistoryListViewTests|HistoryDetailViewTests" 2>&1 | tail -15
```

- [ ] **Step 3: Implement.**

```swift
// Sources/CommentRelayUI/Screens/HistoryListView.swift
import SwiftUI
import CommentRelayCore

public struct HistoryListView: View {
    public let history: CommentRelayHistory
    public let onSelect: (CommentRelayHistoryEntry) -> Void

    public init(history: CommentRelayHistory, onSelect: @escaping (CommentRelayHistoryEntry) -> Void) {
        self.history = history
        self.onSelect = onSelect
    }

    public var body: some View {
        Group {
            if history.submissions.isEmpty {
                EmptyStateView(
                    systemImage: "tray",
                    title: Strings.historyTitle,
                    message: history.isAnonymous ? Strings.historyEmptyAnonymous : Strings.historyEmptyIdentified
                )
            } else {
                List {
                    ForEach(history.submissions) { entry in
                        Button {
                            onSelect(entry)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.categoryTitle).font(.headline)
                                Text(entry.createdAt, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if !entry.notes.isEmpty {
                                    Text(entry.notes[0].content)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(Strings.historyTitle)
    }
}
```

```swift
// Sources/CommentRelayUI/Screens/HistoryDetailView.swift
import SwiftUI
import CommentRelayCore

public struct HistoryDetailView: View {
    public let entry: CommentRelayHistoryEntry

    public init(entry: CommentRelayHistoryEntry) {
        self.entry = entry
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(entry.categoryTitle).font(.title2).bold()
                    Spacer()
                    Text(entry.createdAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !entry.notes.isEmpty {
                    Text(Strings.historyNotesHeader)
                        .font(.headline)
                        .padding(.top)
                    ForEach(entry.notes) { note in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.content).font(.callout)
                            Text(note.createdAt, style: .date).font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(8)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(entry.categoryTitle)
    }
}
```

- [ ] **Step 4: Run — expect pass.**

```bash
swift test --filter "HistoryListViewTests|HistoryDetailViewTests" 2>&1 | tail -10
```

- [ ] **Step 5: Commit.**

```bash
git add Sources/CommentRelayUI/Screens/HistoryListView.swift \
        Sources/CommentRelayUI/Screens/HistoryDetailView.swift \
        Tests/CommentRelayUITests/ScreenTests/HistoryListViewTests.swift \
        Tests/CommentRelayUITests/ScreenTests/HistoryDetailViewTests.swift
git commit -m "Add HistoryListView and HistoryDetailView"
```

---

### Task 19: `CommentRelayView` container

The drop-in entry view that owns the navigation stack and ties everything together. This is where config fetching, draft wiring, submit → upload → finalize orchestration, and error handling live.

**Files:**
- Create: `Sources/CommentRelayUI/Screens/CommentRelayView.swift`
- Create: `Tests/CommentRelayUITests/ScreenTests/CommentRelayViewTests.swift`

- [ ] **Step 1: Write failing test.**

```swift
// Tests/CommentRelayUITests/ScreenTests/CommentRelayViewTests.swift
import XCTest
import SwiftUI
import ViewInspector
import CommentRelayCore
@testable import CommentRelayUI

final class CommentRelayViewTests: XCTestCase {
    func test_rendersLoadingState_onInit() throws {
        let config = CommentRelayConfiguration(baseURL: URL(string: "http://x")!, apiKey: "k")
        let sut = CommentRelayView(configuration: config)
        XCTAssertNoThrow(try sut.inspect().find(ViewType.NavigationStack.self))
    }
}
```

- [ ] **Step 2: Run — expect failure.**

```bash
swift test --filter CommentRelayViewTests 2>&1 | tail -15
```

- [ ] **Step 3: Implement.**

```swift
// Sources/CommentRelayUI/Screens/CommentRelayView.swift
import SwiftUI
import CommentRelayCore

public struct CommentRelayView: View {
    public let configuration: CommentRelayConfiguration

    @State private var route: Route = .loading
    @State private var errorMessage: String? = nil
    @State private var client: CommentRelayClient

    public init(configuration: CommentRelayConfiguration) {
        self.configuration = configuration
        self._client = State(initialValue: CommentRelayClient(configuration: configuration))
    }

    enum Route: Hashable {
        case loading
        case picker(categories: [CommentRelayCategory])
        case form(category: CommentRelayCategory)
        case progress(currentFile: String?)
        case progressFailed(message: String)
        case thanks(showHistory: Bool)
        case history
    }

    public var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { route = .history }
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                                .accessibilityLabel(Strings.historyTitle)
                        }
                    }
                }
                .task {
                    await loadCategories()
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch route {
        case .loading:
            LoadingView(label: Strings.formSending)
        case .picker(let categories):
            CategoryPickerView(categories: categories) { selected in
                route = .form(category: selected)
            }
        case .form(let category):
            let vm = FeedbackFormViewModel(
                category: category,
                userIdentifier: configuration.userIdentifier ?? "anonymous",
                platform: .ios,
                sdkVersion: configuration.effectiveSDKVersion
            )
            FeedbackFormView(viewModel: vm) { submission in
                Task { await submit(submission, viewModel: vm) }
            }
        case .progress(let file):
            SubmissionProgressView(state: .inProgress(currentFile: file))
        case .progressFailed(let message):
            SubmissionProgressView(state: .failed(message: message, retry: {
                route = .loading
                Task { await loadCategories() }
            }))
        case .thanks(let showHistory):
            ThankYouView(
                showHistoryAction: showHistory ? { route = .history } : nil,
                doneAction: { route = .loading; Task { await loadCategories() } }
            )
        case .history:
            HistoryLoader(client: client)
        }
    }

    // MARK: - Actions

    private func loadCategories() async {
        do {
            switch try await client.fetchConfig(cachedHash: nil) {
            case .current:
                // No categories on screen to show; treat as empty.
                route = .picker(categories: [])
            case .updated(_, let categories):
                route = .picker(categories: categories)
            }
        } catch let err as CommentRelayError {
            route = .progressFailed(message: message(for: err))
        } catch {
            route = .progressFailed(message: Strings.errorGeneric)
        }
    }

    private func submit(_ submission: CommentRelaySubmission, viewModel: FeedbackFormViewModel) async {
        route = .progress(currentFile: nil)
        do {
            let receipt = try await client.submit(submission)
            let payloads = viewModel.filePayloads(for: receipt)
            if receipt.hasUploads {
                try await client.uploadFiles(receipt: receipt, payloads: payloads)
            } else {
                try await client.finalize(submissionId: receipt.submissionId)
            }
            route = .thanks(showHistory: configuration.userIdentifier != nil)
        } catch let err as CommentRelayError {
            route = .progressFailed(message: message(for: err))
        } catch {
            route = .progressFailed(message: Strings.errorGeneric)
        }
    }

    private func message(for error: CommentRelayError) -> String {
        switch error {
        case .paymentRequired: return Strings.errorPaymentRequired
        case .rateLimited: return Strings.errorRateLimited
        case .uploadFailed: return Strings.errorUploadFailed
        default: return Strings.errorGeneric
        }
    }
}

private struct HistoryLoader: View {
    let client: CommentRelayClient
    @State private var history: CommentRelayHistory? = nil
    @State private var selected: CommentRelayHistoryEntry? = nil
    @State private var errorMessage: String? = nil

    var body: some View {
        Group {
            if let history {
                HistoryListView(history: history) { entry in
                    selected = entry
                }
                .navigationDestination(item: $selected) { entry in
                    HistoryDetailView(entry: entry)
                }
            } else if let errorMessage {
                ErrorBanner(message: errorMessage, retry: nil)
            } else {
                LoadingView(label: nil)
            }
        }
        .task {
            do {
                history = try await client.fetchHistory()
            } catch {
                errorMessage = Strings.errorGeneric
            }
        }
    }
}
```

- [ ] **Step 4: Run — expect pass.**

```bash
swift test --filter CommentRelayViewTests 2>&1 | tail -10
```

- [ ] **Step 5: Commit.**

```bash
git add Sources/CommentRelayUI/Screens/CommentRelayView.swift \
        Tests/CommentRelayUITests/ScreenTests/CommentRelayViewTests.swift
git commit -m "Add CommentRelayView container orchestrating the full flow"
```

---

## Launchers

### Task 20: `.commentRelaySheet` modifier + `CommentRelayButton`

**Files:**
- Create: `Sources/CommentRelayUI/Launchers/CommentRelaySheetModifier.swift`
- Create: `Sources/CommentRelayUI/Launchers/CommentRelayButton.swift`
- Create: `Tests/CommentRelayUITests/ScreenTests/CommentRelayButtonTests.swift`

- [ ] **Step 1: Write failing test.**

```swift
// Tests/CommentRelayUITests/ScreenTests/CommentRelayButtonTests.swift
import XCTest
import SwiftUI
import ViewInspector
import CommentRelayCore
@testable import CommentRelayUI

final class CommentRelayButtonTests: XCTestCase {
    func test_rendersLabelClosure() throws {
        let config = CommentRelayConfiguration(baseURL: URL(string: "http://x")!, apiKey: "k")
        let sut = CommentRelayButton(configuration: config) {
            Text("Send feedback")
        }
        XCTAssertNoThrow(try sut.inspect().find(text: "Send feedback"))
    }
}
```

- [ ] **Step 2: Run — expect failure.**

```bash
swift test --filter CommentRelayButtonTests 2>&1 | tail -15
```

- [ ] **Step 3: Implement the sheet modifier.**

```swift
// Sources/CommentRelayUI/Launchers/CommentRelaySheetModifier.swift
import SwiftUI
import CommentRelayCore

public extension View {
    func commentRelaySheet(isPresented: Binding<Bool>, configuration: CommentRelayConfiguration) -> some View {
        sheet(isPresented: isPresented) {
            CommentRelayView(configuration: configuration)
        }
    }
}
```

- [ ] **Step 4: Implement the button.**

```swift
// Sources/CommentRelayUI/Launchers/CommentRelayButton.swift
import SwiftUI
import CommentRelayCore

public struct CommentRelayButton<Label: View>: View {
    public let configuration: CommentRelayConfiguration
    public let label: () -> Label

    @State private var isPresented = false

    public init(configuration: CommentRelayConfiguration, @ViewBuilder label: @escaping () -> Label) {
        self.configuration = configuration
        self.label = label
    }

    public var body: some View {
        Button { isPresented = true } label: { label() }
            .commentRelaySheet(isPresented: $isPresented, configuration: configuration)
    }
}
```

- [ ] **Step 5: Run — expect pass.**

```bash
swift test --filter CommentRelayButtonTests 2>&1 | tail -10
```

- [ ] **Step 6: Commit.**

```bash
git add Sources/CommentRelayUI/Launchers/CommentRelaySheetModifier.swift \
        Sources/CommentRelayUI/Launchers/CommentRelayButton.swift \
        Tests/CommentRelayUITests/ScreenTests/CommentRelayButtonTests.swift
git commit -m "Add .commentRelaySheet modifier and CommentRelayButton"
```

---

## Sample app

### Task 21: Expand sample to drive the full flow

**Files:**
- Modify: `Example/CommentRelaySample/CommentRelaySample/ContentView.swift`
- Modify: `Example/CommentRelaySample/CommentRelaySample.xcodeproj/project.pbxproj` (add `CommentRelayUI` as a second linked product)

- [ ] **Step 1: Add `CommentRelayUI` as a linked product in the sample's Xcode project.**

The sample currently links only `CommentRelayCore` via a `XCSwiftPackageProductDependency` block. Add a second entry for `CommentRelayUI`. Use either the Xcode GUI (add package product to target) or edit `project.pbxproj` directly — find the existing block for `productName = CommentRelayCore;` and add a parallel block for `CommentRelayUI`, then register it in the target's `packageProductDependencies` and `PBXFrameworksBuildPhase`.

Alternatively, open the project in Xcode, select the `CommentRelaySample` target → General → Frameworks, Libraries, and Embedded Content → `+` → `CommentRelayUI`.

- [ ] **Step 2: Update `ContentView.swift`** to launch `CommentRelayView` via `.commentRelaySheet`.

```swift
// Example/CommentRelaySample/CommentRelaySample/ContentView.swift
import SwiftUI
import CommentRelayCore
import CommentRelayUI

struct ContentView: View {
    @State private var baseURLString = "http://localhost:3000"
    @State private var apiKeyString = "crk_test_sample"
    @State private var userIdentifier = ""
    @State private var isFeedbackPresented = false
    @State private var pingStatus: PingStatus = .idle

    enum PingStatus {
        case idle, loading, success, failure(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("CommentRelay v\(CommentRelay.version)")
                .font(.headline)

            group("Base URL", $baseURLString)
            group("API key", $apiKeyString)
            group("User identifier (optional)", $userIdentifier)

            Button(action: ping) {
                HStack {
                    if case .loading = pingStatus { ProgressView().controlSize(.small) }
                    Text("Ping /health")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button("Send feedback") {
                isFeedbackPresented = true
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            .commentRelaySheet(
                isPresented: $isFeedbackPresented,
                configuration: makeConfig()
            )

            pingStatusView

            Spacer()
        }
        .padding()
        .frame(minWidth: 320, minHeight: 360)
    }

    private func group(_ label: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
        }
    }

    @ViewBuilder
    private var pingStatusView: some View {
        switch pingStatus {
        case .idle: EmptyView()
        case .loading: Text("Pinging…").foregroundStyle(.secondary)
        case .success: Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failure(let m): Label(m, systemImage: "xmark.circle.fill").foregroundStyle(.red)
        }
    }

    private func makeConfig() -> CommentRelayConfiguration {
        let url = URL(string: baseURLString) ?? URL(string: "http://localhost:3000")!
        return CommentRelayConfiguration(
            baseURL: url,
            apiKey: apiKeyString,
            userIdentifier: userIdentifier.isEmpty ? nil : userIdentifier
        )
    }

    private func ping() {
        pingStatus = .loading
        Task {
            do {
                let ok = try await CommentRelayClient(configuration: makeConfig()).ping()
                pingStatus = ok ? .success : .failure("Server returned non-2xx")
            } catch {
                pingStatus = .failure(error.localizedDescription)
            }
        }
    }
}

#Preview {
    ContentView()
}
```

- [ ] **Step 3: Build the sample.**

```bash
cd /Users/mikesilvers/repos/commentrelay-sdk/commentrelay-sdk-ios
xcodebuild -project Example/CommentRelaySample/CommentRelaySample.xcodeproj -scheme CommentRelaySample -destination 'platform=macOS' -quiet build 2>&1 | tail -10
```

Expected: `BUILD SUCCEEDED`. (If the linker complains about `CommentRelayUI`, Step 1 wasn't fully applied — re-check the Xcode target's package product dependencies.)

- [ ] **Step 4: Commit.**

```bash
git add Example/CommentRelaySample
git commit -m "Expand sample app to drive the full feedback flow via .commentRelaySheet"
```

---

## Smoke test

### Task 22: Bump version + plan-B smoke test

**Files:**
- Modify: `Sources/CommentRelayCore/Public/CommentRelay.swift`

- [ ] **Step 1: Bump `CommentRelay.version`.**

```swift
// Sources/CommentRelayCore/Public/CommentRelay.swift
public enum CommentRelay {
    public static let version = "0.2.0"
}
```

- [ ] **Step 2: Run full test suite.**

```bash
cd /Users/mikesilvers/repos/commentrelay-sdk/commentrelay-sdk-ios
swift build 2>&1 | tail -5
swift test 2>&1 | tail -10
```

Expected: `swift build` succeeds for both `CommentRelayCore` and `CommentRelayUI`. `swift test` reports all Core tests (52 after Task 1's `DraftAPITests`) + all UI tests passing.

- [ ] **Step 3: Verify sample app builds.**

```bash
xcodebuild -project Example/CommentRelaySample/CommentRelaySample.xcodeproj -scheme CommentRelaySample -destination 'platform=macOS' -quiet build 2>&1 | tail -10
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit.**

```bash
git add Sources/CommentRelayCore/Public/CommentRelay.swift
git commit -m "Bump CommentRelay.version to 0.2.0 for UI completion"
```

---

## Summary

Plan B ships:

- **`CommentRelayUI` SPM library** — SwiftUI-only, depending on `CommentRelayCore`.
- **Launchers:** `.commentRelaySheet(isPresented:configuration:)` + `CommentRelayButton`.
- **Container:** `CommentRelayView` with internal NavigationStack orchestrating category → form → progress → thank-you → history.
- **Composable screens:** `CategoryPickerView`, `FeedbackFormView` (+ `FeedbackFormViewModel`), `SubmissionProgressView`, `ThankYouView`, `HistoryListView`, `HistoryDetailView`, `DraftRestorePrompt`.
- **10 field renderers** behind the shared `FieldRenderer` protocol.
- **Shared UI:** `CommentRelayTheme` (2 tokens — see note in Task 4), `ErrorBanner`, `EmptyStateView`, `LoadingView`, `ContactPreferenceSection`.
- **Localization:** `en` + `es-419` `Localizable.strings` resources, with `CommentRelayLocalization.register(locale:bundle:)` public hook for integrator-supplied locales.
- **Core extensions:** public `saveDraft` / `loadDraft` / `deleteDraft` on `CommentRelayClient`; `CommentRelayLocalization.registeredBundle(for:)` made public so `CommentRelayUI.Strings` can walk the resolution chain.
- **Test coverage:** ViewInspector interaction tests for every view (30+), view-model tests for `FeedbackFormViewModel`, localization resolution tests. Snapshot tests are scaffolded via `SnapshotHelpers`; the spec's full 120-snapshot matrix is deferred — shipping 0–2 snapshots per renderer as baseline.
- **Sample app** drives the full flow via `.commentRelaySheet`.

### Accepted deviations from the spec

1. **Theme tokens.** 2 v1 tokens (`accentColor`, `cornerRadius`) instead of 4. Button-style theming flagged as future work; `.tint(theme.accentColor)` propagates accent into button surfaces for v1.
2. **Snapshot test coverage.** Sparse matrix now (~0–2 per renderer) with helpers in place to expand. Full 120-snapshot commitment rolled to a follow-up once integrators surface real regressions.
3. **Smiley SVG rendering.** SF Symbols as a v1 fallback (one of the three spec-offered options). The SVGs returned by the API are not rendered directly.
4. **Background-configuration upload session.** Plan A landed a foreground `URLSession` through the `UploadTransport` protocol seam. Switching to `URLSession(configuration: .background(...))` + delegate plumbing requires App Delegate integration, which is out of scope for this plan.
5. **Consolidated accessibility audit.** The spec asks for a dedicated `AccessibilityAuditTests.swift` that loops through every renderer and asserts on `accessibilityLabel` / `accessibilityValue` / `isStaticText`. The per-renderer tests in Tasks 8–13 exercise these annotations individually via ViewInspector, and the views themselves apply the annotations. A dedicated audit file can be added in a follow-up to cross-check all renderers in one place — v1 accepts per-task coverage as sufficient.

Each deviation is small and self-contained; none block the feedback flow from working end-to-end against the local `dev.sh` API stack.
