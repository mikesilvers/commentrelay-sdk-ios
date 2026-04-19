# CommentRelayCore Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure the SPM package and build out the `CommentRelayCore` library per `docs/superpowers/specs/2026-04-19-display-components-design.md`. Delivers a working headless SDK (models, errors, API client, persistence, background uploads) that a later `CommentRelayUI` plan will build on.

**Architecture:** Two SPM library products in one package. Plan A creates only `CommentRelayCore` (no SwiftUI). `CommentRelayClient` becomes an `actor` that owns the injected configuration, wraps an internal `APIClient`, and coordinates `ConfigCache`, `SessionStore`, `DraftStore`, `BackgroundUploadManager`, and a 403 circuit-breaker.

**Tech Stack:** Swift 5.9, Foundation, URLSession, Security (Keychain), `os.Logger`. `swift-tools-version: 5.9`. Minimum iOS 18 / macOS 15. No third-party runtime deps. Tests use XCTest + existing `MockURLProtocol`.

**Out of scope for Plan A:** SwiftUI views, launchers, field renderers, theme, snapshot tests, localized `.strings` files (wiring is present; resources ship with Plan B's `CommentRelayUI` bundle), sample app UI expansion beyond the import-path update.

---

## File structure (end of Plan A)

```
Package.swift                                       # modified — products, platforms, targets
Sources/
└── CommentRelayCore/                               # renamed from Sources/CommentRelay/
    ├── Public/
    │   ├── CommentRelay.swift                      # moved, namespace + version (unchanged)
    │   ├── CommentRelayClient.swift                # modified — now actor w/ full public API
    │   ├── CommentRelayConfiguration.swift         # new
    │   ├── CommentRelayError.swift                 # new
    │   ├── CommentRelayLogger.swift                # new
    │   └── Models/
    │       ├── FieldType.swift                     # new
    │       ├── FieldOption.swift                   # new
    │       ├── CommentRelayField.swift             # new
    │       ├── CommentRelayCategory.swift          # new — also holds ConfigResponse
    │       ├── Platform.swift                      # new
    │       ├── ContactPreference.swift             # new
    │       ├── CommentRelaySubmission.swift        # new
    │       ├── CommentRelaySubmissionReceipt.swift # new
    │       └── CommentRelayHistory.swift           # new — History, HistoryEntry, DeveloperNote
    └── Internal/
        ├── APIClient.swift                         # new — URLSession wrapper
        ├── ErrorMapper.swift                       # new
        ├── ConfigCache.swift                       # new
        ├── SessionStore.swift                      # new — Keychain UUID
        ├── DraftStore.swift                        # new — per-category JSON
        ├── UploadTransport.swift                   # new — protocol seam
        ├── BackgroundUploadManager.swift           # new
        └── LocalizationBundle.swift                # new

Tests/
└── CommentRelayCoreTests/                          # renamed from Tests/CommentRelayTests/
    ├── MockURLProtocol.swift                       # moved, unchanged
    ├── CommentRelayClientTests.swift               # moved + expanded
    ├── CommentRelayTests.swift                     # moved, unchanged
    ├── CommentRelayErrorTests.swift                # new
    ├── ErrorMapperTests.swift                      # new
    ├── ModelDecodingTests.swift                    # new
    ├── CommentRelayConfigurationTests.swift        # new
    ├── APIClientTests.swift                        # new
    ├── ConfigCacheTests.swift                      # new
    ├── SessionStoreTests.swift                     # new
    ├── DraftStoreTests.swift                       # new
    ├── BackgroundUploadManagerTests.swift          # new
    ├── LocalizationBundleTests.swift               # new
    └── CircuitBreakerTests.swift                   # new

Example/CommentRelaySample/CommentRelaySample/
├── ContentView.swift                               # modified — import CommentRelayCore
└── CommentRelaySample.xcodeproj/project.pbxproj    # modified — product ref CommentRelay → CommentRelayCore
```

---

### Task 1: Restructure package for the Core library

**Files:**
- Modify: `Package.swift`
- Rename: `Sources/CommentRelay/` → `Sources/CommentRelayCore/`
- Rename: `Tests/CommentRelayTests/` → `Tests/CommentRelayCoreTests/`
- Modify: `Tests/CommentRelayCoreTests/CommentRelayClientTests.swift` (import)
- Modify: `Tests/CommentRelayCoreTests/CommentRelayTests.swift` (import)
- Modify: `Example/CommentRelaySample/CommentRelaySample.xcodeproj/project.pbxproj`
- Modify: `Example/CommentRelaySample/CommentRelaySample/ContentView.swift`

- [ ] **Step 1: Move source and test directories via git.**

```bash
cd /Users/mikesilvers/repos/commentrelay-sdk/commentrelay-sdk-ios
git mv Sources/CommentRelay Sources/CommentRelayCore
git mv Tests/CommentRelayTests Tests/CommentRelayCoreTests
mkdir -p Sources/CommentRelayCore/Public Sources/CommentRelayCore/Public/Models Sources/CommentRelayCore/Internal
git mv Sources/CommentRelayCore/CommentRelay.swift Sources/CommentRelayCore/Public/CommentRelay.swift
git mv Sources/CommentRelayCore/CommentRelayClient.swift Sources/CommentRelayCore/Public/CommentRelayClient.swift
```

- [ ] **Step 2: Overwrite `Package.swift`:**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CommentRelay",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "CommentRelayCore", targets: ["CommentRelayCore"]),
    ],
    targets: [
        .target(name: "CommentRelayCore"),
        .testTarget(name: "CommentRelayCoreTests", dependencies: ["CommentRelayCore"]),
    ]
)
```

- [ ] **Step 3: Update test imports.** Replace `@testable import CommentRelay` with `@testable import CommentRelayCore` in both `Tests/CommentRelayCoreTests/CommentRelayClientTests.swift` and `Tests/CommentRelayCoreTests/CommentRelayTests.swift`.

- [ ] **Step 4: Update sample's `ContentView.swift`.** Replace `import CommentRelay` with `import CommentRelayCore`. The `CommentRelay.version` and `CommentRelayClient` references continue to resolve because both types move into the new module.

- [ ] **Step 5: Update the sample's Xcode project.** In `Example/CommentRelaySample/CommentRelaySample.xcodeproj/project.pbxproj`, replace every occurrence of the product name `CommentRelay` with `CommentRelayCore`. Specifically, the following exact lines (from `grep -n "CommentRelay " project.pbxproj`) must be updated to use `CommentRelayCore`:

```
/* CommentRelay in Frameworks */ = {isa = PBXBuildFile; productRef = … /* CommentRelay */; };
productRef = … /* CommentRelay */
productName = CommentRelay;
```

Use `sed -i '' 's/\/\* CommentRelay \*\//\/\* CommentRelayCore \*\//g; s/productName = CommentRelay;/productName = CommentRelayCore;/g' Example/CommentRelaySample/CommentRelaySample.xcodeproj/project.pbxproj` or edit by hand. Do **not** rename `CommentRelaySample` anywhere — only the SDK product reference changes.

- [ ] **Step 6: Run tests and build.**

```bash
swift test
swift build
```

Expected: all four existing `ping` tests pass, `version_isNonEmpty` passes. `swift build` succeeds with a single `CommentRelayCore` product.

- [ ] **Step 7: Verify sample compiles.**

```bash
xcodebuild -project Example/CommentRelaySample/CommentRelaySample.xcodeproj -scheme CommentRelaySample -destination 'platform=macOS' -quiet build 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 8: Commit.**

```bash
git add -A
git commit -m "Restructure to CommentRelayCore library, bump iOS 18 / macOS 15"
```

---

### Task 2: Add `CommentRelayError`

**Files:**
- Create: `Sources/CommentRelayCore/Public/CommentRelayError.swift`
- Create: `Tests/CommentRelayCoreTests/CommentRelayErrorTests.swift`

- [ ] **Step 1: Write the failing test.**

```swift
// Tests/CommentRelayCoreTests/CommentRelayErrorTests.swift
import XCTest
@testable import CommentRelayCore

final class CommentRelayErrorTests: XCTestCase {
    func test_allCases_instantiateAndDescribe() {
        let cases: [CommentRelayError] = [
            .badRequest(message: "bad"),
            .paymentRequired(message: "billing"),
            .forbidden(message: "key revoked"),
            .notFound(message: "category"),
            .conflict(message: "limit"),
            .rateLimited(retryAfter: 2),
            .server(message: "boom"),
            .transport(URLError(.notConnectedToInternet)),
            .decoding(NSError(domain: "test", code: 0)),
            .uploadFailed(submissionId: UUID(), fileName: "a.png", underlying: NSError(domain: "s3", code: 1)),
            .uploadUrlExpired(submissionId: UUID()),
        ]
        XCTAssertEqual(cases.count, 11)
        for error in cases {
            XCTAssertFalse(String(describing: error).isEmpty)
        }
    }

    func test_isTerminal_trueOnlyForForbidden() {
        XCTAssertTrue(CommentRelayError.forbidden(message: "x").isTerminal)
        XCTAssertFalse(CommentRelayError.server(message: "x").isTerminal)
        XCTAssertFalse(CommentRelayError.rateLimited(retryAfter: nil).isTerminal)
    }
}
```

- [ ] **Step 2: Run — expect failure.**

```bash
swift test --filter CommentRelayErrorTests
```

Expected: FAIL, `cannot find 'CommentRelayError' in scope`.

- [ ] **Step 3: Write implementation.**

```swift
// Sources/CommentRelayCore/Public/CommentRelayError.swift
import Foundation

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

    /// A terminal error should flip the SDK into a disabled state until `reset()` is called.
    public var isTerminal: Bool {
        if case .forbidden = self { return true }
        return false
    }
}
```

- [ ] **Step 4: Run — expect pass.**

```bash
swift test --filter CommentRelayErrorTests
```

- [ ] **Step 5: Commit.**

```bash
git add Sources/CommentRelayCore/Public/CommentRelayError.swift Tests/CommentRelayCoreTests/CommentRelayErrorTests.swift
git commit -m "Add CommentRelayError public enum"
```

---

### Task 3: Add HTTP `ErrorMapper`

**Files:**
- Create: `Sources/CommentRelayCore/Internal/ErrorMapper.swift`
- Create: `Tests/CommentRelayCoreTests/ErrorMapperTests.swift`

- [ ] **Step 1: Write failing tests.**

```swift
// Tests/CommentRelayCoreTests/ErrorMapperTests.swift
import XCTest
@testable import CommentRelayCore

final class ErrorMapperTests: XCTestCase {
    private func mapError(status: Int, body: String = #"{"error":{"code":"X","message":"msg"}}"#, headers: [String: String] = [:]) -> CommentRelayError {
        let url = URL(string: "https://example.com")!
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        return ErrorMapper.map(response: response, data: Data(body.utf8))
    }

    func test_400_mapsToBadRequest() {
        guard case .badRequest(let m) = mapError(status: 400) else { return XCTFail() }
        XCTAssertEqual(m, "msg")
    }
    func test_402_mapsToPaymentRequired() {
        guard case .paymentRequired = mapError(status: 402) else { return XCTFail() }
    }
    func test_403_mapsToForbidden() {
        guard case .forbidden = mapError(status: 403) else { return XCTFail() }
    }
    func test_404_mapsToNotFound() {
        guard case .notFound = mapError(status: 404) else { return XCTFail() }
    }
    func test_409_mapsToConflict() {
        guard case .conflict = mapError(status: 409) else { return XCTFail() }
    }
    func test_429_parsesRetryAfter() {
        guard case .rateLimited(let retry) = mapError(status: 429, headers: ["Retry-After": "3"]) else { return XCTFail() }
        XCTAssertEqual(retry, 3)
    }
    func test_429_noHeader_retryAfterNil() {
        guard case .rateLimited(let retry) = mapError(status: 429) else { return XCTFail() }
        XCTAssertNil(retry)
    }
    func test_500_mapsToServer() {
        guard case .server = mapError(status: 500) else { return XCTFail() }
    }
    func test_unknownStatus_fallsBackToServer() {
        guard case .server = mapError(status: 418) else { return XCTFail() }
    }
    func test_unparseableBody_usesStatusText() {
        guard case .badRequest(let m) = mapError(status: 400, body: "not json") else { return XCTFail() }
        XCTAssertEqual(m, "HTTP 400")
    }
}
```

- [ ] **Step 2: Run — expect failure (type not found).**

```bash
swift test --filter ErrorMapperTests
```

- [ ] **Step 3: Write implementation.**

```swift
// Sources/CommentRelayCore/Internal/ErrorMapper.swift
import Foundation

enum ErrorMapper {
    private struct APIErrorEnvelope: Decodable {
        struct Inner: Decodable { let code: String; let message: String }
        let error: Inner
    }

    static func map(response: HTTPURLResponse, data: Data) -> CommentRelayError {
        let message: String = {
            if let env = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) {
                return env.error.message
            }
            return "HTTP \(response.statusCode)"
        }()

        switch response.statusCode {
        case 400: return .badRequest(message: message)
        case 402: return .paymentRequired(message: message)
        case 403: return .forbidden(message: message)
        case 404: return .notFound(message: message)
        case 409: return .conflict(message: message)
        case 429:
            let retry = (response.value(forHTTPHeaderField: "Retry-After")).flatMap(TimeInterval.init)
            return .rateLimited(retryAfter: retry)
        default:
            return .server(message: message)
        }
    }
}
```

- [ ] **Step 4: Run — expect pass.**

```bash
swift test --filter ErrorMapperTests
```

- [ ] **Step 5: Commit.**

```bash
git add Sources/CommentRelayCore/Internal/ErrorMapper.swift Tests/CommentRelayCoreTests/ErrorMapperTests.swift
git commit -m "Add ErrorMapper covering documented HTTP error codes"
```

---

### Task 4: Add field models (`FieldType`, `FieldOption`, `CommentRelayField`)

**Files:**
- Create: `Sources/CommentRelayCore/Public/Models/FieldType.swift`
- Create: `Sources/CommentRelayCore/Public/Models/FieldOption.swift`
- Create: `Sources/CommentRelayCore/Public/Models/CommentRelayField.swift`
- Create: `Tests/CommentRelayCoreTests/ModelDecodingTests.swift` (starts here; grows in tasks 5–7)

- [ ] **Step 1: Write the failing tests.**

```swift
// Tests/CommentRelayCoreTests/ModelDecodingTests.swift
import XCTest
@testable import CommentRelayCore

final class ModelDecodingTests: XCTestCase {
    private let decoder = JSONDecoder()

    func test_fieldType_roundTripsAllTenCases() throws {
        let raw = #"["textbox","true_false","numeric","photo","attachment","informational","email","phone","smiley_rating","color_scale"]"#
        let types = try decoder.decode([FieldType].self, from: Data(raw.utf8))
        XCTAssertEqual(types, [.textbox, .trueFalse, .numeric, .photo, .attachment, .informational, .email, .phone, .smileyRating, .colorScale])
    }

    func test_fieldType_unknownValueDecodesToUnknown() throws {
        let data = Data(#""martian""#.utf8)
        XCTAssertEqual(try decoder.decode(FieldType.self, from: data), .unknown)
    }

    func test_fieldOption_smileyAndColorBothDecode() throws {
        let smiley = #"{"position":3,"label":"neutral","svg":"<svg/>"}"#
        let color = #"{"position":1,"color":"#FF0000","label":"Poor"}"#
        let s = try decoder.decode(FieldOption.self, from: Data(smiley.utf8))
        let c = try decoder.decode(FieldOption.self, from: Data(color.utf8))
        XCTAssertEqual(s.position, 3)
        XCTAssertEqual(s.label, "neutral")
        XCTAssertEqual(s.svg, "<svg/>")
        XCTAssertNil(s.color)
        XCTAssertEqual(c.color, "#FF0000")
        XCTAssertNil(c.svg)
    }

    func test_field_decodesTextbox() throws {
        let raw = #"""
        {"id":"f1","field_type":"textbox","label":"Describe","is_required":true,"is_gate":false,"sort_order":1,"max_files":null}
        """#
        let f = try decoder.decode(CommentRelayField.self, from: Data(raw.utf8))
        XCTAssertEqual(f.id, "f1")
        XCTAssertEqual(f.fieldType, .textbox)
        XCTAssertEqual(f.label, "Describe")
        XCTAssertTrue(f.isRequired)
        XCTAssertFalse(f.isGate)
        XCTAssertEqual(f.sortOrder, 1)
        XCTAssertNil(f.maxFiles)
    }
}
```

- [ ] **Step 2: Run — expect failure.**

```bash
swift test --filter ModelDecodingTests
```

- [ ] **Step 3: Write `FieldType`.**

```swift
// Sources/CommentRelayCore/Public/Models/FieldType.swift
import Foundation

public enum FieldType: String, Codable, Sendable, Equatable {
    case textbox
    case trueFalse = "true_false"
    case numeric
    case photo
    case attachment
    case informational
    case email
    case phone
    case smileyRating = "smiley_rating"
    case colorScale = "color_scale"
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = FieldType(rawValue: raw) ?? .unknown
    }
}
```

- [ ] **Step 4: Write `FieldOption`.**

```swift
// Sources/CommentRelayCore/Public/Models/FieldOption.swift
import Foundation

public struct FieldOption: Codable, Sendable, Equatable {
    public let position: Int
    public let label: String?
    public let svg: String?
    public let color: String?

    public init(position: Int, label: String?, svg: String? = nil, color: String? = nil) {
        self.position = position
        self.label = label
        self.svg = svg
        self.color = color
    }
}
```

- [ ] **Step 5: Write `CommentRelayField`.**

```swift
// Sources/CommentRelayCore/Public/Models/CommentRelayField.swift
import Foundation

public struct CommentRelayField: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let fieldType: FieldType
    public let label: String
    public let isRequired: Bool
    public let isGate: Bool
    public let sortOrder: Int
    public let maxFiles: Int?
    public let options: [FieldOption]?

    enum CodingKeys: String, CodingKey {
        case id
        case fieldType = "field_type"
        case label
        case isRequired = "is_required"
        case isGate = "is_gate"
        case sortOrder = "sort_order"
        case maxFiles = "max_files"
        case options
    }
}
```

- [ ] **Step 6: Run — expect pass.**

```bash
swift test --filter ModelDecodingTests
```

- [ ] **Step 7: Commit.**

```bash
git add Sources/CommentRelayCore/Public/Models/FieldType.swift \
        Sources/CommentRelayCore/Public/Models/FieldOption.swift \
        Sources/CommentRelayCore/Public/Models/CommentRelayField.swift \
        Tests/CommentRelayCoreTests/ModelDecodingTests.swift
git commit -m "Add FieldType, FieldOption, CommentRelayField models"
```

---

### Task 5: Add `CommentRelayCategory` + config-response model

**Files:**
- Create: `Sources/CommentRelayCore/Public/Models/CommentRelayCategory.swift`
- Modify: `Tests/CommentRelayCoreTests/ModelDecodingTests.swift`

- [ ] **Step 1: Append failing tests to `ModelDecodingTests`.**

```swift
    func test_category_decodesFullConfigPayload() throws {
        let raw = #"""
        {
          "current": false,
          "hash": "abc123",
          "categories": [{
            "id": "cat1",
            "title": "Bug Report",
            "show_in_picker": true,
            "response_limit_count": 5,
            "response_limit_type": "per_session",
            "response_limit_window_days": null,
            "more_feedback_prompt": "Tell us more",
            "is_active": true,
            "sort_order": 1,
            "fields": []
          }]
        }
        """#
        let result = try decoder.decode(CommentRelayConfigResponse.self, from: Data(raw.utf8))
        guard case .updated(let hash, let categories) = result else { return XCTFail() }
        XCTAssertEqual(hash, "abc123")
        XCTAssertEqual(categories.first?.id, "cat1")
        XCTAssertEqual(categories.first?.title, "Bug Report")
        XCTAssertEqual(categories.first?.responseLimitType, .perSession)
    }

    func test_category_decodesCurrentResponse() throws {
        let raw = #"{"current":true}"#
        let result = try decoder.decode(CommentRelayConfigResponse.self, from: Data(raw.utf8))
        guard case .current = result else { return XCTFail() }
    }
```

- [ ] **Step 2: Run — expect failure.**

```bash
swift test --filter ModelDecodingTests/test_category
```

- [ ] **Step 3: Write the model.**

```swift
// Sources/CommentRelayCore/Public/Models/CommentRelayCategory.swift
import Foundation

public enum ResponseLimitType: String, Codable, Sendable, Equatable {
    case perSession = "per_session"
    case timeWindow = "time_window"
    case lifetime
}

public struct CommentRelayCategory: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let showInPicker: Bool
    public let responseLimitCount: Int?
    public let responseLimitType: ResponseLimitType?
    public let responseLimitWindowDays: Int?
    public let moreFeedbackPrompt: String?
    public let isActive: Bool
    public let sortOrder: Int
    public let fields: [CommentRelayField]

    enum CodingKeys: String, CodingKey {
        case id, title
        case showInPicker = "show_in_picker"
        case responseLimitCount = "response_limit_count"
        case responseLimitType = "response_limit_type"
        case responseLimitWindowDays = "response_limit_window_days"
        case moreFeedbackPrompt = "more_feedback_prompt"
        case isActive = "is_active"
        case sortOrder = "sort_order"
        case fields
    }
}

public enum CommentRelayConfigResponse: Sendable, Equatable {
    case current
    case updated(hash: String, categories: [CommentRelayCategory])
}

extension CommentRelayConfigResponse: Decodable {
    private struct Envelope: Decodable {
        let current: Bool
        let hash: String?
        let categories: [CommentRelayCategory]?
    }

    public init(from decoder: Decoder) throws {
        let env = try Envelope(from: decoder)
        if env.current {
            self = .current
        } else {
            self = .updated(hash: env.hash ?? "", categories: env.categories ?? [])
        }
    }
}
```

- [ ] **Step 4: Run — expect pass.**

```bash
swift test --filter ModelDecodingTests
```

- [ ] **Step 5: Commit.**

```bash
git add Sources/CommentRelayCore/Public/Models/CommentRelayCategory.swift Tests/CommentRelayCoreTests/ModelDecodingTests.swift
git commit -m "Add CommentRelayCategory + ConfigResponse variant"
```

---

### Task 6: Add submission models

**Files:**
- Create: `Sources/CommentRelayCore/Public/Models/Platform.swift`
- Create: `Sources/CommentRelayCore/Public/Models/ContactPreference.swift`
- Create: `Sources/CommentRelayCore/Public/Models/CommentRelaySubmission.swift`
- Create: `Sources/CommentRelayCore/Public/Models/CommentRelaySubmissionReceipt.swift`
- Modify: `Tests/CommentRelayCoreTests/ModelDecodingTests.swift`

- [ ] **Step 1: Append failing tests.**

```swift
    func test_submission_encodesInAPIShape() throws {
        let submission = CommentRelaySubmission(
            categoryId: "cat1",
            userIdentifier: "user-123",
            platform: .ios,
            fields: [.text(fieldId: "f1", value: "bug"), .files(fieldId: "f2", metadata: [
                .init(name: "s.png", type: "image/png", size: 123)
            ])],
            osVersion: "18.0",
            deviceModel: "iPhone 16",
            appVersion: "2.1.0",
            sdkVersion: "0.0.1",
            locale: "en_US",
            contactPreference: .email,
            contactDetails: "a@b.c",
            sessionId: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        )
        let data = try JSONEncoder().encode(submission)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["category_id"] as? String, "cat1")
        XCTAssertEqual(json["user_identifier"] as? String, "user-123")
        XCTAssertEqual(json["platform"] as? String, "ios")
        XCTAssertEqual(json["contact_preference"] as? String, "email")
        let fields = try XCTUnwrap(json["fields"] as? [[String: Any]])
        XCTAssertEqual(fields.count, 2)
        XCTAssertEqual(fields[0]["value"] as? String, "bug")
        let meta = try XCTUnwrap(fields[1]["file_metadata"] as? [[String: Any]])
        XCTAssertEqual(meta.first?["name"] as? String, "s.png")
    }

    func test_receipt_decodes() throws {
        let raw = #"""
        {"submissionId":"11111111-1111-1111-1111-111111111111","hasUploads":true,"uploadUrls":[
          {"fieldId":"f2","fileName":"s.png","uploadUrl":"https://s3/upload"}]}
        """#
        let receipt = try decoder.decode(CommentRelaySubmissionReceipt.self, from: Data(raw.utf8))
        XCTAssertEqual(receipt.submissionId.uuidString.lowercased(), "11111111-1111-1111-1111-111111111111")
        XCTAssertTrue(receipt.hasUploads)
        XCTAssertEqual(receipt.uploadUrls.first?.fileName, "s.png")
    }
```

- [ ] **Step 2: Run — expect failure.**

- [ ] **Step 3: Implement `Platform`.**

```swift
// Sources/CommentRelayCore/Public/Models/Platform.swift
import Foundation

public enum Platform: String, Codable, Sendable, Equatable {
    case ios, android, web, server, other
}
```

- [ ] **Step 4: Implement `ContactPreference`.**

```swift
// Sources/CommentRelayCore/Public/Models/ContactPreference.swift
import Foundation

public enum ContactPreference: String, Codable, Sendable, Equatable {
    case none
    case email
    case text
    case phoneCall = "phone_call"
}
```

- [ ] **Step 5: Implement `CommentRelaySubmission`.**

```swift
// Sources/CommentRelayCore/Public/Models/CommentRelaySubmission.swift
import Foundation

public struct CommentRelaySubmission: Codable, Sendable, Equatable {
    public struct FileMetadata: Codable, Sendable, Equatable {
        public let name: String
        public let type: String
        public let size: Int
        public init(name: String, type: String, size: Int) {
            self.name = name; self.type = type; self.size = size
        }
    }

    public enum FieldValue: Codable, Sendable, Equatable {
        case text(fieldId: String, value: String)
        case files(fieldId: String, metadata: [FileMetadata])

        private enum Keys: String, CodingKey { case fieldId = "field_id", value, fileMetadata = "file_metadata" }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            let id = try c.decode(String.self, forKey: .fieldId)
            if let value = try c.decodeIfPresent(String.self, forKey: .value) {
                self = .text(fieldId: id, value: value)
            } else {
                let m = try c.decode([FileMetadata].self, forKey: .fileMetadata)
                self = .files(fieldId: id, metadata: m)
            }
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: Keys.self)
            switch self {
            case .text(let id, let v):
                try c.encode(id, forKey: .fieldId)
                try c.encode(v, forKey: .value)
            case .files(let id, let m):
                try c.encode(id, forKey: .fieldId)
                try c.encode(m, forKey: .fileMetadata)
            }
        }
    }

    public let categoryId: String
    public let userIdentifier: String
    public let platform: Platform
    public let fields: [FieldValue]
    public let osVersion: String?
    public let deviceModel: String?
    public let appVersion: String?
    public let sdkVersion: String?
    public let locale: String?
    public let contactPreference: ContactPreference?
    public let contactDetails: String?
    public let sessionId: UUID?

    enum CodingKeys: String, CodingKey {
        case categoryId = "category_id"
        case userIdentifier = "user_identifier"
        case platform, fields
        case osVersion = "os_version"
        case deviceModel = "device_model"
        case appVersion = "app_version"
        case sdkVersion = "sdk_version"
        case locale
        case contactPreference = "contact_preference"
        case contactDetails = "contact_details"
        case sessionId = "session_id"
    }

    public init(categoryId: String, userIdentifier: String, platform: Platform, fields: [FieldValue],
                osVersion: String? = nil, deviceModel: String? = nil, appVersion: String? = nil,
                sdkVersion: String? = nil, locale: String? = nil,
                contactPreference: ContactPreference? = nil, contactDetails: String? = nil,
                sessionId: UUID? = nil) {
        self.categoryId = categoryId
        self.userIdentifier = userIdentifier
        self.platform = platform
        self.fields = fields
        self.osVersion = osVersion
        self.deviceModel = deviceModel
        self.appVersion = appVersion
        self.sdkVersion = sdkVersion
        self.locale = locale
        self.contactPreference = contactPreference
        self.contactDetails = contactDetails
        self.sessionId = sessionId
    }
}
```

- [ ] **Step 6: Implement `CommentRelaySubmissionReceipt`.**

```swift
// Sources/CommentRelayCore/Public/Models/CommentRelaySubmissionReceipt.swift
import Foundation

public struct CommentRelaySubmissionReceipt: Codable, Sendable, Equatable {
    public struct UploadTarget: Codable, Sendable, Equatable {
        public let fieldId: String
        public let fileName: String
        public let uploadUrl: URL
    }

    public let submissionId: UUID
    public let hasUploads: Bool
    public let uploadUrls: [UploadTarget]
}
```

- [ ] **Step 7: Run — expect pass.**

```bash
swift test --filter ModelDecodingTests
```

- [ ] **Step 8: Commit.**

```bash
git add Sources/CommentRelayCore/Public/Models/Platform.swift \
        Sources/CommentRelayCore/Public/Models/ContactPreference.swift \
        Sources/CommentRelayCore/Public/Models/CommentRelaySubmission.swift \
        Sources/CommentRelayCore/Public/Models/CommentRelaySubmissionReceipt.swift \
        Tests/CommentRelayCoreTests/ModelDecodingTests.swift
git commit -m "Add submission request/response models"
```

---

### Task 7: Add history models

**Files:**
- Create: `Sources/CommentRelayCore/Public/Models/CommentRelayHistory.swift`
- Modify: `Tests/CommentRelayCoreTests/ModelDecodingTests.swift`

- [ ] **Step 1: Append failing tests.**

```swift
    func test_history_decodesIdentified() throws {
        let raw = #"""
        {"submissions":[{
          "id":"22222222-2222-2222-2222-222222222222",
          "category_id":"cat1",
          "category_title":"Bug Report",
          "status":"complete",
          "created_at":"2026-03-19T10:30:00Z",
          "notes":[{"id":"n1","content":"Fixed in v2","created_at":"2026-03-19T12:00:00Z"}]
        }]}
        """#
        let h = try decoder.decode(CommentRelayHistory.self, from: Data(raw.utf8))
        XCTAssertFalse(h.isAnonymous)
        XCTAssertEqual(h.submissions.count, 1)
        XCTAssertEqual(h.submissions.first?.notes.first?.content, "Fixed in v2")
    }

    func test_history_decodesAnonymous() throws {
        let raw = #"{"anonymousUser":true,"submissions":[]}"#
        let h = try decoder.decode(CommentRelayHistory.self, from: Data(raw.utf8))
        XCTAssertTrue(h.isAnonymous)
        XCTAssertTrue(h.submissions.isEmpty)
    }
```

- [ ] **Step 2: Run — expect failure.**

- [ ] **Step 3: Implement.**

```swift
// Sources/CommentRelayCore/Public/Models/CommentRelayHistory.swift
import Foundation

public struct DeveloperNote: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let content: String
    public let createdAt: Date

    enum CodingKeys: String, CodingKey { case id, content, createdAt = "created_at" }
}

public struct CommentRelayHistoryEntry: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let categoryId: String
    public let categoryTitle: String
    public let status: String
    public let createdAt: Date
    public let notes: [DeveloperNote]

    enum CodingKeys: String, CodingKey {
        case id
        case categoryId = "category_id"
        case categoryTitle = "category_title"
        case status
        case createdAt = "created_at"
        case notes
    }
}

public struct CommentRelayHistory: Codable, Sendable, Equatable {
    public let isAnonymous: Bool
    public let submissions: [CommentRelayHistoryEntry]

    enum CodingKeys: String, CodingKey {
        case anonymousUser
        case submissions
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.isAnonymous = try c.decodeIfPresent(Bool.self, forKey: .anonymousUser) ?? false
        self.submissions = try c.decode([CommentRelayHistoryEntry].self, forKey: .submissions)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(isAnonymous, forKey: .anonymousUser)
        try c.encode(submissions, forKey: .submissions)
    }
}
```

The per-test `JSONDecoder` must parse ISO-8601 dates. Update `ModelDecodingTests` setup to add `decoder.dateDecodingStrategy = .iso8601` before the history tests run:

```swift
    override func setUp() {
        super.setUp()
        decoder.dateDecodingStrategy = .iso8601
    }
```

(Change the `private let decoder = JSONDecoder()` at the top to `private var decoder = JSONDecoder()` so it's mutable.)

- [ ] **Step 4: Run — expect pass.**

```bash
swift test --filter ModelDecodingTests
```

- [ ] **Step 5: Commit.**

```bash
git add Sources/CommentRelayCore/Public/Models/CommentRelayHistory.swift Tests/CommentRelayCoreTests/ModelDecodingTests.swift
git commit -m "Add history models (DeveloperNote, HistoryEntry, History)"
```

---

### Task 8: Add `CommentRelayConfiguration`

**Files:**
- Create: `Sources/CommentRelayCore/Public/CommentRelayConfiguration.swift`
- Create: `Tests/CommentRelayCoreTests/CommentRelayConfigurationTests.swift`

- [ ] **Step 1: Write failing test.**

```swift
// Tests/CommentRelayCoreTests/CommentRelayConfigurationTests.swift
import XCTest
@testable import CommentRelayCore

final class CommentRelayConfigurationTests: XCTestCase {
    func test_defaults_autoPopulateMetadata() {
        let c = CommentRelayConfiguration(
            baseURL: URL(string: "https://api.example.com")!,
            apiKey: "crk_test_abc")
        XCTAssertFalse(c.effectiveSDKVersion.isEmpty)
        XCTAssertFalse(c.effectiveOSVersion.isEmpty)
        XCTAssertFalse(c.effectiveDeviceModel.isEmpty)
        XCTAssertEqual(c.effectiveSDKVersion, CommentRelay.version)
    }

    func test_overrides_winOverAutoPopulated() {
        let c = CommentRelayConfiguration(
            baseURL: URL(string: "https://api.example.com")!,
            apiKey: "k",
            sdkVersionOverride: "9.9.9",
            osVersionOverride: "42.0",
            deviceModelOverride: "MyFakePhone",
            appVersionOverride: "1.2.3")
        XCTAssertEqual(c.effectiveSDKVersion, "9.9.9")
        XCTAssertEqual(c.effectiveOSVersion, "42.0")
        XCTAssertEqual(c.effectiveDeviceModel, "MyFakePhone")
        XCTAssertEqual(c.effectiveAppVersion, "1.2.3")
    }
}
```

- [ ] **Step 2: Run — expect failure.**

- [ ] **Step 3: Implement.**

```swift
// Sources/CommentRelayCore/Public/CommentRelayConfiguration.swift
import Foundation
#if canImport(UIKit)
import UIKit
#endif

public struct CommentRelayConfiguration: Sendable {
    public let baseURL: URL
    public let apiKey: String
    public let userIdentifier: String?
    public let locale: String?

    public let sdkVersionOverride: String?
    public let osVersionOverride: String?
    public let deviceModelOverride: String?
    public let appVersionOverride: String?

    public init(baseURL: URL,
                apiKey: String,
                userIdentifier: String? = nil,
                locale: String? = nil,
                sdkVersionOverride: String? = nil,
                osVersionOverride: String? = nil,
                deviceModelOverride: String? = nil,
                appVersionOverride: String? = nil) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.userIdentifier = userIdentifier
        self.locale = locale
        self.sdkVersionOverride = sdkVersionOverride
        self.osVersionOverride = osVersionOverride
        self.deviceModelOverride = deviceModelOverride
        self.appVersionOverride = appVersionOverride
    }

    public var effectiveSDKVersion: String {
        sdkVersionOverride ?? CommentRelay.version
    }

    public var effectiveOSVersion: String {
        if let v = osVersionOverride { return v }
        #if canImport(UIKit)
        return UIDevice.current.systemVersion
        #else
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        #endif
    }

    public var effectiveDeviceModel: String {
        if let v = deviceModelOverride { return v }
        #if canImport(UIKit)
        return UIDevice.current.model
        #else
        return "Mac"
        #endif
    }

    public var effectiveAppVersion: String? {
        appVersionOverride
            ?? Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }
}
```

- [ ] **Step 4: Run — expect pass.**

- [ ] **Step 5: Commit.**

```bash
git add Sources/CommentRelayCore/Public/CommentRelayConfiguration.swift Tests/CommentRelayCoreTests/CommentRelayConfigurationTests.swift
git commit -m "Add CommentRelayConfiguration with metadata autopopulation"
```

---

### Task 9: Extract `APIClient` (URLSession wrapper with header injection)

**Files:**
- Create: `Sources/CommentRelayCore/Internal/APIClient.swift`
- Create: `Tests/CommentRelayCoreTests/APIClientTests.swift`

- [ ] **Step 1: Write failing tests.**

```swift
// Tests/CommentRelayCoreTests/APIClientTests.swift
import XCTest
@testable import CommentRelayCore

final class APIClientTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
    }
    override func tearDown() { MockURLProtocol.reset(); session = nil; super.tearDown() }

    func test_getHealth_injectsApiKeyHeader() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (response, Data())
        }
        let client = APIClient(baseURL: URL(string: "http://x")!, apiKey: "crk_test_abc", session: session)
        _ = try await client.getHealth()
        let req = try XCTUnwrap(MockURLProtocol.requests.first)
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-api-key"), "crk_test_abc")
    }

    func test_error403_mapsViaErrorMapper() async throws {
        MockURLProtocol.handler = { request in
            let resp = HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data(#"{"error":{"code":"FORBIDDEN","message":"revoked"}}"#.utf8))
        }
        let client = APIClient(baseURL: URL(string: "http://x")!, apiKey: "k", session: session)
        do {
            _ = try await client.getHealth()
            XCTFail("expected throw")
        } catch let err as CommentRelayError {
            guard case .forbidden(let m) = err else { return XCTFail("wrong case") }
            XCTAssertEqual(m, "revoked")
        }
    }
}
```

- [ ] **Step 2: Run — expect failure.**

- [ ] **Step 3: Write `APIClient`.**

```swift
// Sources/CommentRelayCore/Internal/APIClient.swift
import Foundation

struct APIClient {
    let baseURL: URL
    let apiKey: String
    let session: URLSession

    init(baseURL: URL, apiKey: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
    }

    func getHealth() async throws -> Bool {
        let url = baseURL.appendingPathComponent("health")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            if (200..<300).contains(http.statusCode) { return true }
            if http.statusCode >= 500 { return false }
            throw ErrorMapper.map(response: http, data: data)
        } catch let urlError as URLError {
            throw CommentRelayError.transport(urlError)
        }
    }

    func send<Response: Decodable>(method: String, path: String, body: Data? = nil, userIdentifier: String? = nil, decodingAs: Response.Type, decoder: JSONDecoder = APIClient.defaultDecoder) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let userIdentifier {
            request.setValue(userIdentifier, forHTTPHeaderField: "x-user-identifier")
        }
        request.httpBody = body
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw CommentRelayError.transport(urlError)
        }
        guard let http = response as? HTTPURLResponse else {
            throw CommentRelayError.server(message: "invalid response")
        }
        if !(200..<300).contains(http.statusCode) {
            throw ErrorMapper.map(response: http, data: data)
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw CommentRelayError.decoding(error)
        }
    }

    static var defaultDecoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    static var defaultEncoder: JSONEncoder {
        JSONEncoder()
    }
}
```

- [ ] **Step 4: Run — expect pass.**

```bash
swift test --filter APIClientTests
```

- [ ] **Step 5: Commit.**

```bash
git add Sources/CommentRelayCore/Internal/APIClient.swift Tests/CommentRelayCoreTests/APIClientTests.swift
git commit -m "Add internal APIClient with x-api-key injection and error mapping"
```

---

### Task 10: Add `ConfigCache`

**Files:**
- Create: `Sources/CommentRelayCore/Internal/ConfigCache.swift`
- Create: `Tests/CommentRelayCoreTests/ConfigCacheTests.swift`

- [ ] **Step 1: Write failing tests.**

```swift
// Tests/CommentRelayCoreTests/ConfigCacheTests.swift
import XCTest
@testable import CommentRelayCore

final class ConfigCacheTests: XCTestCase {
    private var tempDir: URL!
    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("crl-cache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: tempDir) }

    func test_emptyOnFirstRead() async {
        let cache = ConfigCache(directory: tempDir)
        let snap = await cache.read()
        XCTAssertNil(snap)
    }

    func test_writeThenReadRoundTrip() async throws {
        let cache = ConfigCache(directory: tempDir)
        let cat = CommentRelayCategory(id: "c1", title: "Bug", showInPicker: true, responseLimitCount: nil, responseLimitType: nil, responseLimitWindowDays: nil, moreFeedbackPrompt: nil, isActive: true, sortOrder: 1, fields: [])
        await cache.write(hash: "abc", categories: [cat])
        let snap = try XCTUnwrap(await cache.read())
        XCTAssertEqual(snap.hash, "abc")
        XCTAssertEqual(snap.categories.first?.id, "c1")
    }

    func test_survivesNewInstance() async throws {
        let cacheA = ConfigCache(directory: tempDir)
        await cacheA.write(hash: "h1", categories: [])
        let cacheB = ConfigCache(directory: tempDir)
        let snap = try XCTUnwrap(await cacheB.read())
        XCTAssertEqual(snap.hash, "h1")
    }
}
```

- [ ] **Step 2: Run — expect failure.**

- [ ] **Step 3: Implement.**

```swift
// Sources/CommentRelayCore/Internal/ConfigCache.swift
import Foundation

actor ConfigCache {
    struct Snapshot: Codable, Sendable {
        let hash: String
        let categories: [CommentRelayCategory]
    }

    private let fileURL: URL
    private let fm = FileManager.default

    init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("config.json")
    }

    /// Defaults to `Application Support/CommentRelay/`.
    static func defaultDirectory(apiKeyFingerprint: String) throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory,
                                               in: .userDomainMask,
                                               appropriateFor: nil,
                                               create: true)
        let dir = base.appendingPathComponent("CommentRelay").appendingPathComponent(apiKeyFingerprint)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func read() -> Snapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    func write(hash: String, categories: [CommentRelayCategory]) {
        let snap = Snapshot(hash: hash, categories: categories)
        guard let data = try? JSONEncoder().encode(snap) else { return }
        try? fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    func clear() {
        try? fm.removeItem(at: fileURL)
    }
}
```

- [ ] **Step 4: Run — expect pass.**

```bash
swift test --filter ConfigCacheTests
```

- [ ] **Step 5: Commit.**

```bash
git add Sources/CommentRelayCore/Internal/ConfigCache.swift Tests/CommentRelayCoreTests/ConfigCacheTests.swift
git commit -m "Add ConfigCache — persists categories + hash to disk"
```

---

### Task 11: Add `SessionStore` (Keychain anonymous UUID)

**Files:**
- Create: `Sources/CommentRelayCore/Internal/SessionStore.swift`
- Create: `Tests/CommentRelayCoreTests/SessionStoreTests.swift`

- [ ] **Step 1: Write failing tests.**

```swift
// Tests/CommentRelayCoreTests/SessionStoreTests.swift
import XCTest
@testable import CommentRelayCore

final class SessionStoreTests: XCTestCase {
    func test_hostSupplied_wins() {
        let store = SessionStore(service: "crl.test.\(UUID().uuidString)", hostSupplied: "host-user-1")
        XCTAssertEqual(store.effectiveIdentifier, "host-user-1")
        XCTAssertFalse(store.isAnonymous)
    }

    func test_anonymousId_isStableAcrossInstances() {
        let service = "crl.test.\(UUID().uuidString)"
        defer { _ = SessionStore(service: service, hostSupplied: nil).resetAnonymous() }

        let a = SessionStore(service: service, hostSupplied: nil)
        let b = SessionStore(service: service, hostSupplied: nil)
        XCTAssertEqual(a.effectiveIdentifier, b.effectiveIdentifier)
        XCTAssertTrue(a.isAnonymous)
    }

    func test_reset_generatesNewId() {
        let service = "crl.test.\(UUID().uuidString)"
        let store = SessionStore(service: service, hostSupplied: nil)
        let first = store.effectiveIdentifier
        store.resetAnonymous()
        let second = store.effectiveIdentifier
        XCTAssertNotEqual(first, second)
    }
}
```

- [ ] **Step 2: Run — expect failure.**

- [ ] **Step 3: Implement.**

```swift
// Sources/CommentRelayCore/Internal/SessionStore.swift
import Foundation
import Security

final class SessionStore: @unchecked Sendable {
    private let service: String
    private let account = "anonymousId"
    private let hostSupplied: String?

    init(service: String, hostSupplied: String?) {
        self.service = service
        self.hostSupplied = hostSupplied
    }

    var isAnonymous: Bool { hostSupplied == nil }

    var effectiveIdentifier: String {
        if let hostSupplied { return hostSupplied }
        if let existing = readKeychain() { return existing }
        let generated = UUID().uuidString
        writeKeychain(generated)
        return generated
    }

    @discardableResult
    func resetAnonymous() -> String {
        deleteKeychain()
        return effectiveIdentifier
    }

    // MARK: - Keychain

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func readKeychain() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, let s = String(data: data, encoding: .utf8) else {
            return nil
        }
        return s
    }

    private func writeKeychain(_ value: String) {
        var attrs = baseQuery()
        attrs[kSecValueData as String] = Data(value.utf8)
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemDelete(baseQuery() as CFDictionary)
        SecItemAdd(attrs as CFDictionary, nil)
    }

    private func deleteKeychain() {
        SecItemDelete(baseQuery() as CFDictionary)
    }
}
```

- [ ] **Step 4: Run — expect pass.**

Note: these tests use per-test unique `service` strings so they don't collide with real SDK entries. On macOS CI the Keychain may require special entitlement; if `errSecMissingEntitlement` surfaces, document in a known-issues comment but don't skip the test locally.

```bash
swift test --filter SessionStoreTests
```

- [ ] **Step 5: Commit.**

```bash
git add Sources/CommentRelayCore/Internal/SessionStore.swift Tests/CommentRelayCoreTests/SessionStoreTests.swift
git commit -m "Add SessionStore with Keychain-backed anonymous identifier"
```

---

### Task 12: Add `DraftStore`

**Files:**
- Create: `Sources/CommentRelayCore/Internal/DraftStore.swift`
- Create: `Tests/CommentRelayCoreTests/DraftStoreTests.swift`

- [ ] **Step 1: Write failing tests.**

```swift
// Tests/CommentRelayCoreTests/DraftStoreTests.swift
import XCTest
@testable import CommentRelayCore

final class DraftStoreTests: XCTestCase {
    private var tempDir: URL!
    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("crl-draft-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: tempDir) }

    func test_saveLoad_roundTrip() async throws {
        let store = DraftStore(directory: tempDir, debounce: 0)
        let draft = DraftStore.Draft(categoryId: "cat1", fieldValues: ["f1": "hello"], updatedAt: Date())
        await store.save(draft)
        try await Task.sleep(nanoseconds: 50_000_000)
        let loaded = await store.load(categoryId: "cat1")
        XCTAssertEqual(loaded?.fieldValues["f1"], "hello")
    }

    func test_debounce_coalescesRapidWrites() async throws {
        let store = DraftStore(directory: tempDir, debounce: 0.2)
        for i in 0..<5 {
            await store.save(.init(categoryId: "cat1", fieldValues: ["f": "\(i)"], updatedAt: Date()))
        }
        // not yet written to disk
        XCTAssertNil(await store.peekOnDisk(categoryId: "cat1")?.fieldValues["f"])
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(await store.peekOnDisk(categoryId: "cat1")?.fieldValues["f"], "4")
    }

    func test_delete_removesDraft() async throws {
        let store = DraftStore(directory: tempDir, debounce: 0)
        await store.save(.init(categoryId: "cat1", fieldValues: ["f": "x"], updatedAt: Date()))
        try await Task.sleep(nanoseconds: 50_000_000)
        await store.delete(categoryId: "cat1")
        XCTAssertNil(await store.load(categoryId: "cat1"))
    }
}
```

- [ ] **Step 2: Run — expect failure.**

- [ ] **Step 3: Implement.**

```swift
// Sources/CommentRelayCore/Internal/DraftStore.swift
import Foundation

actor DraftStore {
    public struct Draft: Codable, Sendable, Equatable {
        public let categoryId: String
        public let fieldValues: [String: String]
        public let updatedAt: Date
        public init(categoryId: String, fieldValues: [String: String], updatedAt: Date) {
            self.categoryId = categoryId; self.fieldValues = fieldValues; self.updatedAt = updatedAt
        }
    }

    private let directory: URL
    private let debounce: TimeInterval
    private var pending: [String: Draft] = [:]
    private var pendingTasks: [String: Task<Void, Never>] = [:]
    private let fm = FileManager.default

    init(directory: URL, debounce: TimeInterval = 0.5) {
        self.directory = directory
        self.debounce = debounce
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func save(_ draft: Draft) {
        pending[draft.categoryId] = draft
        pendingTasks[draft.categoryId]?.cancel()
        let debounce = self.debounce
        let categoryId = draft.categoryId
        pendingTasks[categoryId] = Task { [weak self] in
            if debounce > 0 {
                try? await Task.sleep(nanoseconds: UInt64(debounce * 1_000_000_000))
            }
            guard let self, !Task.isCancelled else { return }
            await self.flush(categoryId: categoryId)
        }
    }

    func load(categoryId: String) -> Draft? {
        if let p = pending[categoryId] { return p }
        return peekOnDisk(categoryId: categoryId)
    }

    func peekOnDisk(categoryId: String) -> Draft? {
        guard let data = try? Data(contentsOf: url(for: categoryId)) else { return nil }
        return try? JSONDecoder().decode(Draft.self, from: data)
    }

    func delete(categoryId: String) {
        pending.removeValue(forKey: categoryId)
        pendingTasks[categoryId]?.cancel()
        pendingTasks.removeValue(forKey: categoryId)
        try? fm.removeItem(at: url(for: categoryId))
    }

    private func flush(categoryId: String) {
        guard let draft = pending[categoryId] else { return }
        if let data = try? JSONEncoder().encode(draft) {
            try? data.write(to: url(for: categoryId), options: .atomic)
        }
        pending.removeValue(forKey: categoryId)
        pendingTasks.removeValue(forKey: categoryId)
    }

    private func url(for categoryId: String) -> URL {
        directory.appendingPathComponent("\(categoryId).json")
    }
}
```

- [ ] **Step 4: Run — expect pass.**

```bash
swift test --filter DraftStoreTests
```

- [ ] **Step 5: Commit.**

```bash
git add Sources/CommentRelayCore/Internal/DraftStore.swift Tests/CommentRelayCoreTests/DraftStoreTests.swift
git commit -m "Add DraftStore with per-category debounced persistence"
```

---

### Task 13: Add `UploadTransport` + `BackgroundUploadManager`

**Files:**
- Create: `Sources/CommentRelayCore/Internal/UploadTransport.swift`
- Create: `Sources/CommentRelayCore/Internal/BackgroundUploadManager.swift`
- Create: `Tests/CommentRelayCoreTests/BackgroundUploadManagerTests.swift`

- [ ] **Step 1: Write failing tests.**

```swift
// Tests/CommentRelayCoreTests/BackgroundUploadManagerTests.swift
import XCTest
@testable import CommentRelayCore

final class BackgroundUploadManagerTests: XCTestCase {
    actor FakeTransport: UploadTransport {
        var puts: [(URL, Data)] = []
        var shouldThrow: Bool = false
        var attempt = 0
        func put(data: Data, to url: URL, contentType: String) async throws {
            attempt += 1
            if shouldThrow { throw URLError(.timedOut) }
            puts.append((url, data))
        }
    }

    func test_happyPath_uploadsAllAndFinalizes() async throws {
        let transport = FakeTransport()
        var finalized: [UUID] = []
        let manager = BackgroundUploadManager(transport: transport) { id in finalized.append(id) }
        let subId = UUID()
        let target = CommentRelaySubmissionReceipt.UploadTarget(fieldId: "f", fileName: "a.png", uploadUrl: URL(string: "https://s3/u/a")!)
        let payload = BackgroundUploadManager.Payload(submissionId: subId, target: target, data: Data([1, 2, 3]), contentType: "image/png")
        try await manager.enqueue([payload])
        XCTAssertEqual(finalized, [subId])
        let count = await transport.puts.count
        XCTAssertEqual(count, 1)
    }

    func test_partialFailure_doesNotFinalize() async throws {
        let transport = FakeTransport()
        await transport.setShouldThrow(true)
        var finalized: [UUID] = []
        let manager = BackgroundUploadManager(transport: transport) { id in finalized.append(id) }
        let subId = UUID()
        let target = CommentRelaySubmissionReceipt.UploadTarget(fieldId: "f", fileName: "a.png", uploadUrl: URL(string: "https://s3/u/a")!)
        let payload = BackgroundUploadManager.Payload(submissionId: subId, target: target, data: Data([1]), contentType: "image/png")
        do {
            try await manager.enqueue([payload])
            XCTFail()
        } catch {
            XCTAssertTrue(finalized.isEmpty)
        }
    }
}

extension BackgroundUploadManagerTests.FakeTransport {
    func setShouldThrow(_ value: Bool) { shouldThrow = value }
}
```

- [ ] **Step 2: Run — expect failure.**

- [ ] **Step 3: Implement `UploadTransport`.**

```swift
// Sources/CommentRelayCore/Internal/UploadTransport.swift
import Foundation

protocol UploadTransport: Sendable {
    func put(data: Data, to url: URL, contentType: String) async throws
}

struct URLSessionUploadTransport: UploadTransport {
    let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func put(data: Data, to url: URL, contentType: String) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")
        do {
            let (_, response) = try await session.upload(for: request, from: data)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw CommentRelayError.server(message: "upload failed")
            }
        } catch let urlError as URLError {
            throw CommentRelayError.transport(urlError)
        }
    }
}
```

- [ ] **Step 4: Implement `BackgroundUploadManager`.**

```swift
// Sources/CommentRelayCore/Internal/BackgroundUploadManager.swift
import Foundation

actor BackgroundUploadManager {
    struct Payload: Sendable {
        let submissionId: UUID
        let target: CommentRelaySubmissionReceipt.UploadTarget
        let data: Data
        let contentType: String
    }

    private let transport: UploadTransport
    private let finalizeHandler: @Sendable (UUID) async throws -> Void
    private var inFlight: [UUID: Set<String>] = [:]

    init(transport: UploadTransport, finalize: @escaping @Sendable (UUID) async throws -> Void) {
        self.transport = transport
        self.finalizeHandler = finalize
    }

    func enqueue(_ payloads: [Payload]) async throws {
        let grouped = Dictionary(grouping: payloads, by: { $0.submissionId })
        for (subId, group) in grouped {
            inFlight[subId] = Set(group.map { $0.target.fileName })
            for payload in group {
                do {
                    try await transport.put(data: payload.data, to: payload.target.uploadUrl, contentType: payload.contentType)
                    inFlight[subId]?.remove(payload.target.fileName)
                } catch {
                    throw CommentRelayError.uploadFailed(submissionId: subId,
                                                         fileName: payload.target.fileName,
                                                         underlying: error)
                }
            }
            if inFlight[subId]?.isEmpty == true {
                inFlight.removeValue(forKey: subId)
                try await finalizeHandler(subId)
            }
        }
    }
}
```

- [ ] **Step 5: Run — expect pass.**

```bash
swift test --filter BackgroundUploadManagerTests
```

- [ ] **Step 6: Commit.**

```bash
git add Sources/CommentRelayCore/Internal/UploadTransport.swift \
        Sources/CommentRelayCore/Internal/BackgroundUploadManager.swift \
        Tests/CommentRelayCoreTests/BackgroundUploadManagerTests.swift
git commit -m "Add UploadTransport + BackgroundUploadManager with fake-transport tests"
```

**Design note for the engineer:** v1 uses a default `URLSession` in `URLSessionUploadTransport`. The spec calls for a background-configuration session (`URLSession(configuration: .background(withIdentifier:))`) so uploads survive sheet dismissal and app backgrounding. Swapping in the background session happens in Task 17 when `CommentRelayClient` wires its dependencies; the protocol seam lets tests keep using a foreground fake. The 15-minute URL expiry handling is deferred to Task 17's `submit(_:)` because recovery requires re-calling `submit` for a fresh set of presigned URLs.

---

### Task 14: Add `CommentRelayLogger` + `LocalizationBundle`

**Files:**
- Create: `Sources/CommentRelayCore/Public/CommentRelayLogger.swift`
- Create: `Sources/CommentRelayCore/Internal/LocalizationBundle.swift`
- Create: `Tests/CommentRelayCoreTests/LocalizationBundleTests.swift`

- [ ] **Step 1: Write failing tests.**

```swift
// Tests/CommentRelayCoreTests/LocalizationBundleTests.swift
import XCTest
@testable import CommentRelayCore

final class LocalizationBundleTests: XCTestCase {
    override func setUp() { CommentRelayLocalization.resetForTesting() }
    override func tearDown() { CommentRelayLocalization.resetForTesting() }

    func test_missingKey_fallsBackToKey() {
        let s = LocalizationBundle.shared.string(forKey: "crl.totally.missing.key")
        XCTAssertEqual(s, "crl.totally.missing.key")
    }

    func test_registeredBundle_takesPrecedence() throws {
        let tempBundlePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("crl-bundle-\(UUID().uuidString)").appendingPathComponent("en.lproj")
        try FileManager.default.createDirectory(at: tempBundlePath, withIntermediateDirectories: true)
        let stringsURL = tempBundlePath.appendingPathComponent("Localizable.strings")
        try #""crl.greeting"="hello from registered";"#.write(to: stringsURL, atomically: true, encoding: .utf8)
        let bundle = Bundle(url: tempBundlePath.deletingLastPathComponent())!
        CommentRelayLocalization.register(locale: Locale(identifier: "en"), bundle: bundle)

        XCTAssertEqual(LocalizationBundle.shared.string(forKey: "crl.greeting"), "hello from registered")
    }
}
```

- [ ] **Step 2: Run — expect failure.**

- [ ] **Step 3: Implement `CommentRelayLogger`.**

```swift
// Sources/CommentRelayCore/Public/CommentRelayLogger.swift
import Foundation
import os

public protocol CommentRelayLogger: Sendable {
    func log(level: CommentRelayLogLevel, message: String, error: Error?)
}

public enum CommentRelayLogLevel: Sendable { case debug, info, warning, error }

public struct DefaultLogger: CommentRelayLogger {
    private let logger = Logger(subsystem: "com.commentrelay.sdk", category: "core")
    public init() {}
    public func log(level: CommentRelayLogLevel, message: String, error: Error?) {
        let detail = error.map { " error=\($0)" } ?? ""
        switch level {
        case .debug: logger.debug("\(message)\(detail, privacy: .public)")
        case .info: logger.info("\(message)\(detail, privacy: .public)")
        case .warning: logger.warning("\(message)\(detail, privacy: .public)")
        case .error: logger.error("\(message)\(detail, privacy: .public)")
        }
    }
}

public enum CommentRelayLoggerHolder {
    nonisolated(unsafe) public static var shared: CommentRelayLogger = DefaultLogger()
}
```

- [ ] **Step 4: Implement `LocalizationBundle` + public `CommentRelayLocalization`.**

```swift
// Sources/CommentRelayCore/Internal/LocalizationBundle.swift
import Foundation

public enum CommentRelayLocalization {
    nonisolated(unsafe) private static var registered: [String: Bundle] = [:]
    private static let lock = NSLock()

    public static func register(locale: Locale, bundle: Bundle) {
        lock.lock(); defer { lock.unlock() }
        registered[locale.identifier] = bundle
    }

    static func registeredBundle(for locale: Locale) -> Bundle? {
        lock.lock(); defer { lock.unlock() }
        if let b = registered[locale.identifier] { return b }
        if let languageCode = locale.language.languageCode?.identifier,
           let b = registered[languageCode] {
            return b
        }
        return nil
    }

    static func resetForTesting() {
        lock.lock(); defer { lock.unlock() }
        registered.removeAll()
    }
}

final class LocalizationBundle: Sendable {
    static let shared = LocalizationBundle()
    private init() {}

    func string(forKey key: String, locale: Locale = .current) -> String {
        if let registered = CommentRelayLocalization.registeredBundle(for: locale) {
            let value = registered.localizedString(forKey: key, value: key, table: nil)
            if value != key { return value }
        }
        let host = Bundle.main.localizedString(forKey: key, value: key, table: nil)
        if host != key { return host }
        // Plan A ships no localized resources; Plan B adds `CommentRelayUI` bundle with en/es-419.
        // Until then: return the key itself so missing lookups are visibly unlocalised rather than crashing.
        return key
    }
}
```

- [ ] **Step 5: Run — expect pass.**

```bash
swift test --filter LocalizationBundleTests
```

- [ ] **Step 6: Commit.**

```bash
git add Sources/CommentRelayCore/Public/CommentRelayLogger.swift \
        Sources/CommentRelayCore/Internal/LocalizationBundle.swift \
        Tests/CommentRelayCoreTests/LocalizationBundleTests.swift
git commit -m "Add CommentRelayLogger protocol and LocalizationBundle resolver"
```

---

### Task 15: Convert `CommentRelayClient` to actor + wire dependencies + add `fetchConfig`

**Files:**
- Modify: `Sources/CommentRelayCore/Public/CommentRelayClient.swift`
- Modify: `Tests/CommentRelayCoreTests/CommentRelayClientTests.swift` (existing ping tests updated for new init)

- [ ] **Step 1: Write failing tests for the new signature.**

```swift
// append to Tests/CommentRelayCoreTests/CommentRelayClientTests.swift
    private func makeClient(cacheDir: URL? = nil) async throws -> CommentRelayClient {
        let dir = cacheDir ?? FileManager.default.temporaryDirectory.appendingPathComponent("crl-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let config = CommentRelayConfiguration(
            baseURL: URL(string: "http://localhost:3000")!,
            apiKey: "crk_test_abc",
            userIdentifier: "test-user")
        return CommentRelayClient(
            configuration: config,
            session: session,
            cacheDirectory: dir,
            keychainService: "crl.test.\(UUID().uuidString)")
    }

    func test_fetchConfig_returnsUpdatedPayload_andPersistsCache() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            let body = #"{"current":false,"hash":"h1","categories":[]}"#
            return (response, Data(body.utf8))
        }
        let client = try await makeClient()
        let result = try await client.fetchConfig(cachedHash: nil)
        guard case .updated(let hash, _) = result else { return XCTFail() }
        XCTAssertEqual(hash, "h1")
        // sending a second fetch with the same hash should hit the server with the hash query:
        MockURLProtocol.reset()
        MockURLProtocol.handler = { request in
            XCTAssertTrue(request.url?.query?.contains("hash=h1") ?? false)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (response, Data(#"{"current":true}"#.utf8))
        }
        _ = try await client.fetchConfig(cachedHash: "h1")
    }
```

- [ ] **Step 2: Run — expect failure.**

- [ ] **Step 3: Replace `CommentRelayClient.swift`.**

```swift
// Sources/CommentRelayCore/Public/CommentRelayClient.swift
import Foundation

public actor CommentRelayClient {
    public let configuration: CommentRelayConfiguration

    private let api: APIClient
    private let configCache: ConfigCache
    private let sessionStore: SessionStore
    private let draftStore: DraftStore
    private(set) public var isEnabled: Bool = true

    public init(configuration: CommentRelayConfiguration, session: URLSession = .shared) {
        let fingerprint = Self.fingerprint(apiKey: configuration.apiKey)
        let dir = (try? ConfigCache.defaultDirectory(apiKeyFingerprint: fingerprint))
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("CommentRelay/\(fingerprint)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.configuration = configuration
        self.api = APIClient(baseURL: configuration.baseURL, apiKey: configuration.apiKey, session: session)
        self.configCache = ConfigCache(directory: dir)
        self.sessionStore = SessionStore(service: "com.commentrelay.sdk.\(fingerprint)", hostSupplied: configuration.userIdentifier)
        self.draftStore = DraftStore(directory: dir.appendingPathComponent("drafts"))
    }

    // Test-only escape hatch keeping the test suite hermetic.
    init(configuration: CommentRelayConfiguration,
         session: URLSession,
         cacheDirectory: URL,
         keychainService: String) {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        self.configuration = configuration
        self.api = APIClient(baseURL: configuration.baseURL, apiKey: configuration.apiKey, session: session)
        self.configCache = ConfigCache(directory: cacheDirectory)
        self.sessionStore = SessionStore(service: keychainService, hostSupplied: configuration.userIdentifier)
        self.draftStore = DraftStore(directory: cacheDirectory.appendingPathComponent("drafts"))
    }

    public func ping() async throws -> Bool {
        try ensureEnabled()
        return try await api.getHealth()
    }

    public func fetchConfig(cachedHash: String?) async throws -> CommentRelayConfigResponse {
        try ensureEnabled()
        var path = "sdk/v1/config"
        if let cachedHash { path += "?hash=\(cachedHash)" }
        let response: CommentRelayConfigResponse = try await api.send(
            method: "GET", path: path, decodingAs: CommentRelayConfigResponse.self)
        if case .updated(let hash, let categories) = response {
            await configCache.write(hash: hash, categories: categories)
        }
        return response
    }

    // MARK: - Internal helpers

    private func ensureEnabled() throws {
        if !isEnabled {
            throw CommentRelayError.forbidden(message: "client disabled after 403 — call reset()")
        }
    }

    fileprivate func disable() { isEnabled = false }

    private static func fingerprint(apiKey: String) -> String {
        let digest = apiKey.unicodeScalars.reduce(into: UInt64(5381)) { acc, scalar in
            acc = (acc &* 33) &+ UInt64(scalar.value)
        }
        return String(digest, radix: 16)
    }
}
```

Also update the existing ping-returning-false-on-500 test: the new `APIClient.getHealth()` returns `false` for 5xx (kept intentional so `ping` remains a liveness probe), so that test continues to work.

Update the existing init calls in `test_ping_*` to use the new test initializer pattern via `makeClient()`.

Apply the following replacement to `test_ping_issuesGetToHealthEndpoint` (and the other three ping tests) — substitute the old inline construction with `let client = try await makeClient()` and drop `let client = CommentRelayClient(baseURL:..., session:...)`.

- [ ] **Step 4: Run — expect pass.**

```bash
swift test --filter CommentRelayClientTests
```

- [ ] **Step 5: Commit.**

```bash
git add Sources/CommentRelayCore/Public/CommentRelayClient.swift Tests/CommentRelayCoreTests/CommentRelayClientTests.swift
git commit -m "Convert CommentRelayClient to actor + add fetchConfig"
```

---

### Task 16: Update the sample app for the new client init

**Files:**
- Modify: `Example/CommentRelaySample/CommentRelaySample/ContentView.swift`

- [ ] **Step 1: Update `ping()` in `ContentView.swift`.**

```swift
// Example/CommentRelaySample/CommentRelaySample/ContentView.swift (replace the existing ping() function only)
    private func ping() {
        guard let url = URL(string: baseURLString) else {
            status = .failure("Invalid URL")
            return
        }
        status = .loading
        Task {
            do {
                let config = CommentRelayConfiguration(baseURL: url, apiKey: "crk_test_sample")
                let client = CommentRelayClient(configuration: config)
                let ok = try await client.ping()
                status = ok ? .success : .failure("Server returned non-2xx")
            } catch {
                status = .failure(error.localizedDescription)
            }
        }
    }
```

- [ ] **Step 2: Build and run.**

```bash
xcodebuild -project Example/CommentRelaySample/CommentRelaySample.xcodeproj -scheme CommentRelaySample -destination 'platform=macOS' -quiet build 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit.**

```bash
git add Example/CommentRelaySample/CommentRelaySample/ContentView.swift
git commit -m "Update sample to use CommentRelayConfiguration-based init"
```

---

### Task 17: Add `submit(_:)` (with 15-minute URL retry contract)

**Files:**
- Modify: `Sources/CommentRelayCore/Public/CommentRelayClient.swift`
- Modify: `Tests/CommentRelayCoreTests/CommentRelayClientTests.swift`

- [ ] **Step 1: Write failing test.**

```swift
    func test_submit_returnsReceipt_andPostsExpectedBody() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/sdk/v1/submissions")
            let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: "HTTP/1.1", headerFields: nil)!
            let body = #"""
            {"submissionId":"11111111-1111-1111-1111-111111111111",
             "hasUploads":false,
             "uploadUrls":[]}
            """#
            return (response, Data(body.utf8))
        }
        let client = try await makeClient()
        let submission = CommentRelaySubmission(
            categoryId: "cat1", userIdentifier: "u", platform: .ios,
            fields: [.text(fieldId: "f1", value: "hello")])
        let receipt = try await client.submit(submission)
        XCTAssertEqual(receipt.submissionId.uuidString.lowercased(), "11111111-1111-1111-1111-111111111111")
        XCTAssertFalse(receipt.hasUploads)
    }
```

- [ ] **Step 2: Run — expect failure.**

- [ ] **Step 3: Add `submit(_:)` to `CommentRelayClient` (append to the actor).**

```swift
    public func submit(_ submission: CommentRelaySubmission) async throws -> CommentRelaySubmissionReceipt {
        try ensureEnabled()
        let encoder = APIClient.defaultEncoder
        let body = try encoder.encode(submission)
        do {
            return try await api.send(
                method: "POST",
                path: "sdk/v1/submissions",
                body: body,
                userIdentifier: submission.userIdentifier,
                decodingAs: CommentRelaySubmissionReceipt.self)
        } catch let err as CommentRelayError {
            if case .forbidden = err { disable() }
            throw err
        }
    }

    /// Called by `BackgroundUploadManager` when presigned URLs have expired (>15 min).
    /// Re-submits the same logical submission to obtain fresh upload URLs.
    public func resubmit(_ submission: CommentRelaySubmission) async throws -> CommentRelaySubmissionReceipt {
        try await submit(submission)
    }
```

- [ ] **Step 4: Run — expect pass.**

```bash
swift test --filter CommentRelayClientTests/test_submit
```

- [ ] **Step 5: Commit.**

```bash
git add Sources/CommentRelayCore/Public/CommentRelayClient.swift Tests/CommentRelayCoreTests/CommentRelayClientTests.swift
git commit -m "Add submit(_:) — posts submission, flips disabled on 403"
```

---

### Task 18: Add `finalize`, `fetchHistory`, `reset` + 403 circuit-breaker coverage

**Files:**
- Modify: `Sources/CommentRelayCore/Public/CommentRelayClient.swift`
- Create: `Tests/CommentRelayCoreTests/CircuitBreakerTests.swift`
- Modify: `Tests/CommentRelayCoreTests/CommentRelayClientTests.swift`

- [ ] **Step 1: Append failing tests to `CommentRelayClientTests`.**

```swift
    func test_finalize_postsEmptyBodyAndReturnsVoidOn200() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertTrue(request.url?.path.hasSuffix("/finalize") ?? false)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (response, Data(#"{"submissionId":"11111111-1111-1111-1111-111111111111","status":"complete"}"#.utf8))
        }
        let client = try await makeClient()
        try await client.finalize(submissionId: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)
    }

    func test_fetchHistory_passesUserIdentifierHeader_anonymousFalse() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-user-identifier"), "test-user")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (response, Data(#"{"submissions":[]}"#.utf8))
        }
        let client = try await makeClient()
        let h = try await client.fetchHistory()
        XCTAssertFalse(h.isAnonymous)
    }
```

- [ ] **Step 2: Create the circuit-breaker test file.**

```swift
// Tests/CommentRelayCoreTests/CircuitBreakerTests.swift
import XCTest
@testable import CommentRelayCore

final class CircuitBreakerTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
    }
    override func tearDown() { MockURLProtocol.reset(); session = nil; super.tearDown() }

    func test_403OnSubmit_disablesClientUntilReset() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (response, Data(#"{"error":{"code":"FORBIDDEN","message":"revoked"}}"#.utf8))
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("crl-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let config = CommentRelayConfiguration(baseURL: URL(string: "http://x")!, apiKey: "k", userIdentifier: "u")
        let client = CommentRelayClient(configuration: config, session: session, cacheDirectory: dir, keychainService: "crl.test.\(UUID().uuidString)")

        let submission = CommentRelaySubmission(categoryId: "c", userIdentifier: "u", platform: .ios, fields: [])
        do { _ = try await client.submit(submission); XCTFail() } catch {}
        let enabledAfter403 = await client.isEnabled
        XCTAssertFalse(enabledAfter403)

        // Second call short-circuits and throws .forbidden without hitting network.
        MockURLProtocol.reset()
        do { _ = try await client.ping(); XCTFail() } catch let e as CommentRelayError {
            guard case .forbidden = e else { return XCTFail("wrong case") }
            XCTAssertEqual(MockURLProtocol.requests.count, 0)
        }

        await client.reset()
        let enabledAfterReset = await client.isEnabled
        XCTAssertTrue(enabledAfterReset)
    }
}
```

- [ ] **Step 3: Run — expect failure.**

- [ ] **Step 4: Extend `CommentRelayClient` (append to the actor).**

```swift
    public func finalize(submissionId: UUID) async throws {
        try ensureEnabled()
        struct FinalizeResponse: Decodable { let submissionId: UUID; let status: String }
        do {
            _ = try await api.send(
                method: "POST",
                path: "sdk/v1/submissions/\(submissionId.uuidString.lowercased())/finalize",
                body: Data("{}".utf8),
                decodingAs: FinalizeResponse.self)
        } catch let err as CommentRelayError {
            if case .conflict = err { return }   // already finalized is idempotent
            if case .forbidden = err { disable() }
            throw err
        }
    }

    public func fetchHistory() async throws -> CommentRelayHistory {
        try ensureEnabled()
        let effective = sessionStore.effectiveIdentifier
        do {
            return try await api.send(
                method: "GET",
                path: "sdk/v1/history",
                userIdentifier: effective,
                decodingAs: CommentRelayHistory.self)
        } catch let err as CommentRelayError {
            if case .forbidden = err { disable() }
            throw err
        }
    }

    public func reset() {
        isEnabled = true
    }
```

- [ ] **Step 5: Run — expect pass.**

```bash
swift test --filter CommentRelayClientTests
swift test --filter CircuitBreakerTests
```

- [ ] **Step 6: Commit.**

```bash
git add Sources/CommentRelayCore/Public/CommentRelayClient.swift \
        Tests/CommentRelayCoreTests/CommentRelayClientTests.swift \
        Tests/CommentRelayCoreTests/CircuitBreakerTests.swift
git commit -m "Add finalize, fetchHistory, and reset; cover 403 circuit breaker"
```

---

### Task 19: Wire `BackgroundUploadManager` into `CommentRelayClient`

Completes the Core upload hand-off: `CommentRelayClient` owns a `BackgroundUploadManager` instance whose finalize closure calls back into the client, and exposes a public `uploadFiles(receipt:payloads:)` entry point. Plan B's `FeedbackFormView` will call this after `submit`.

**Files:**
- Modify: `Sources/CommentRelayCore/Public/CommentRelayClient.swift`
- Modify: `Sources/CommentRelayCore/Internal/BackgroundUploadManager.swift` (add a public `FilePayload` projection)
- Modify: `Tests/CommentRelayCoreTests/CommentRelayClientTests.swift`

- [ ] **Step 1: Expose a public `FilePayload` struct** that callers use to supply raw bytes per `UploadTarget`. Modify `BackgroundUploadManager.swift`, adding at module scope (outside the actor):

```swift
public struct CommentRelayFilePayload: Sendable {
    public let target: CommentRelaySubmissionReceipt.UploadTarget
    public let data: Data
    public let contentType: String
    public init(target: CommentRelaySubmissionReceipt.UploadTarget, data: Data, contentType: String) {
        self.target = target; self.data = data; self.contentType = contentType
    }
}
```

- [ ] **Step 2: Write failing test — successful upload triggers finalize exactly once.**

Append to `CommentRelayClientTests`:

```swift
    func test_uploadFiles_runsAllUploads_andTriggersFinalize() async throws {
        var pathsSeen: [String] = []
        MockURLProtocol.handler = { request in
            pathsSeen.append(request.url?.path ?? "")
            if request.url?.host == "s3.example.com" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
                return (response, Data())
            }
            // finalize endpoint
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (response, Data(#"{"submissionId":"11111111-1111-1111-1111-111111111111","status":"complete"}"#.utf8))
        }
        let client = try await makeClient()
        let subId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let receipt = CommentRelaySubmissionReceipt(
            submissionId: subId,
            hasUploads: true,
            uploadUrls: [.init(fieldId: "f", fileName: "a.png", uploadUrl: URL(string: "https://s3.example.com/u/a")!)])
        let payload = CommentRelayFilePayload(
            target: receipt.uploadUrls[0],
            data: Data([1, 2, 3]),
            contentType: "image/png")
        try await client.uploadFiles(receipt: receipt, payloads: [payload])

        XCTAssertTrue(pathsSeen.contains("/u/a"))
        XCTAssertTrue(pathsSeen.contains("/sdk/v1/submissions/\(subId.uuidString.lowercased())/finalize"))
    }

    func test_uploadFiles_skippedWhenReceiptHasNoUploads() async throws {
        MockURLProtocol.handler = { request in
            XCTFail("no network call expected when hasUploads == false")
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (response, Data())
        }
        let client = try await makeClient()
        let receipt = CommentRelaySubmissionReceipt(
            submissionId: UUID(),
            hasUploads: false,
            uploadUrls: [])
        try await client.uploadFiles(receipt: receipt, payloads: [])
    }
```

- [ ] **Step 3: Run — expect failure.**

```bash
swift test --filter CommentRelayClientTests/test_uploadFiles
```

- [ ] **Step 4: Update the test's mock handler to tolerate two-host routing.** The helper `makeClient()` already sets `session` with `MockURLProtocol`; no further wiring needed. The test above is complete.

- [ ] **Step 5: Add the upload manager and `uploadFiles` to `CommentRelayClient`.** In `CommentRelayClient.swift`, add a new stored property immediately below the existing `private let draftStore: DraftStore`:

```swift
    private var uploadManager: BackgroundUploadManager!
```

(Use of `!` is intentional: the manager captures `self` in a closure, so it must be set after `self` is fully initialized — Swift won't let a non-optional stored property reference `self` in its default value.)

At the end of both initializers (production and test-only), append:

```swift
        // Finalize closure weakly captures self so the manager doesn't retain the client indefinitely.
        let transport: UploadTransport = URLSessionUploadTransport(session: session)
        self.uploadManager = BackgroundUploadManager(transport: transport) { [weak self] submissionId in
            guard let self else { return }
            try await self.finalize(submissionId: submissionId)
        }
```

Add the public method on the actor:

```swift
    public func uploadFiles(receipt: CommentRelaySubmissionReceipt,
                            payloads: [CommentRelayFilePayload]) async throws {
        try ensureEnabled()
        guard receipt.hasUploads else { return }
        let internalPayloads = payloads.map {
            BackgroundUploadManager.Payload(submissionId: receipt.submissionId,
                                            target: $0.target,
                                            data: $0.data,
                                            contentType: $0.contentType)
        }
        do {
            try await uploadManager.enqueue(internalPayloads)
        } catch let err as CommentRelayError {
            if case .forbidden = err { disable() }
            throw err
        }
    }
```

- [ ] **Step 6: Run — expect pass.**

```bash
swift test --filter CommentRelayClientTests/test_uploadFiles
swift test
```

- [ ] **Step 7: Commit.**

```bash
git add Sources/CommentRelayCore/Public/CommentRelayClient.swift \
        Sources/CommentRelayCore/Internal/BackgroundUploadManager.swift \
        Tests/CommentRelayCoreTests/CommentRelayClientTests.swift
git commit -m "Wire BackgroundUploadManager + CommentRelayClient.uploadFiles"
```

**Design note:** the production `URLSessionUploadTransport` in this task uses the default `URLSession`. Switching to a true background configuration (`.background(withIdentifier:)`) requires `URLSessionDelegate` handling for app-relaunch scenarios — that work lives with Plan B's UI integration where the relaunch surfaces through the host `App`. The protocol seam keeps this swap non-breaking.

---

### Task 20: Bump SDK version + plan-A smoke test

**Files:**
- Modify: `Sources/CommentRelayCore/Public/CommentRelay.swift`

- [ ] **Step 1: Bump `CommentRelay.version`.**

```swift
// Sources/CommentRelayCore/Public/CommentRelay.swift
public enum CommentRelay {
    public static let version = "0.1.0"
}
```

- [ ] **Step 2: Run full test suite.**

```bash
swift build
swift test
```

Expected: `swift build` succeeds. `swift test` reports all suites passing:
- `CommentRelayTests` (version)
- `CommentRelayErrorTests`
- `ErrorMapperTests`
- `ModelDecodingTests`
- `CommentRelayConfigurationTests`
- `APIClientTests`
- `ConfigCacheTests`
- `SessionStoreTests`
- `DraftStoreTests`
- `BackgroundUploadManagerTests`
- `LocalizationBundleTests`
- `CommentRelayClientTests`
- `CircuitBreakerTests`

- [ ] **Step 3: Verify sample app still builds.**

```bash
xcodebuild -project Example/CommentRelaySample/CommentRelaySample.xcodeproj -scheme CommentRelaySample -destination 'platform=macOS' -quiet build 2>&1 | tail -10
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit.**

```bash
git add Sources/CommentRelayCore/Public/CommentRelay.swift
git commit -m "Bump CommentRelay.version to 0.1.0 for Core completion"
```

---

## Summary

At the end of Plan A the repository has a working headless SDK:

- Two SPM targets (library + tests), iOS 18 / macOS 15, no third-party runtime deps.
- Full `CommentRelayClient` public API: `ping`, `fetchConfig`, `submit`, `resubmit`, `uploadFiles`, `finalize`, `fetchHistory`, `reset`, `isEnabled`.
- `CommentRelayConfiguration` with metadata autopopulation + overrides.
- All documented models (Category, Field, FieldType, FieldOption, Submission, Receipt, History, HistoryEntry, DeveloperNote, ContactPreference, Platform).
- `CommentRelayError` + `ErrorMapper` covering the full error taxonomy.
- Internal infrastructure: `APIClient`, `ConfigCache`, `SessionStore` (Keychain), `DraftStore` (debounced JSON), `UploadTransport` + `BackgroundUploadManager` (behind a protocol seam), `LocalizationBundle` (ready for Plan B's bundled resources), `CommentRelayLogger`.
- 403 circuit-breaker verified end-to-end.
- Sample app updated to the new configuration-based init.

**Plan B (CommentRelayUI)** picks up from here: adds the SwiftUI target, theme, 10 field renderers, seven screen views, two launchers, shared UI primitives, localized resources (en + es-419), snapshot/interaction tests, and expands the sample app to drive the full flow.
