# ErrorMapper status classification & 401 handling (CRLBS-120) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `ErrorMapper`'s blanket `default → .server` (which silently retries every unhandled status, including 401, forever) with a faithful HTTP-status-range mapping that surfaces deterministic failures and only retries 5xx.

**Architecture:** Add two public `CommentRelayError` cases (`.unauthorized`, `.unexpectedStatus(statusCode:message:)`) plus matching arms in `CommentRelaySubmissionProblem.Category` so the model stays exhaustively switched; rewire `ErrorMapper` to enumerate 400/401/402/403/404/409/429, retry `500..<600` as `.server`, and surface anything else as `.unexpectedStatus`; `RetryPolicy.classify` flips both new cases to `.terminal`. UI gets a dedicated localized `errorUnauthorized` message wired through `Strings.friendlyError` and `CommentRelayView.message(for:)`.

**Tech Stack:** Swift Package Manager, XCTest, SwiftUI; existing internal `Sources/CommentRelayCore/Internal/{ErrorMapper,RetryPolicy}.swift`; existing public types `CommentRelayError`, `CommentRelaySubmissionProblem.Category`.

**Spec:** `docs/superpowers/specs/2026-05-20-error-mapper-status-classification-design.md`

**Base / dependency:** Branch `feature/CRLBS-120-error-mapper-status-classification` off `develop` (already created at `f6c55c1` — CRLBS-121 merge tip). The spec was committed as `6214b19` on this branch.

**Verification commands:** `swift build`; `swift test`; targeted: `swift test --filter <TestClass>`. Sample app build: `cd Example/CommentRelaySample && xcodebuild -project CommentRelaySample.xcodeproj -scheme CommentRelaySample -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DD build CODE_SIGNING_ALLOWED=NO`.

---

## File structure

- `Sources/CommentRelayCore/Public/CommentRelayError.swift` — add `.unauthorized(message:)` and `.unexpectedStatus(statusCode:message:)`. `isTerminal` deliberately unchanged (per spec — these are surface-not-pause).
- `Sources/CommentRelayCore/Public/CommentRelaySubmissionProblem.swift` — extend `Category` with `unauthorized`, `unexpectedStatus`; add matching arms to `Category.init(_:CommentRelayError)` (still exhaustive, still no `default`).
- `Sources/CommentRelayCore/Internal/ErrorMapper.swift` — replace `default → .server` with enumerated 401 case, `500..<600 → .server`, `default → .unexpectedStatus`.
- `Sources/CommentRelayCore/Internal/RetryPolicy.swift` — add `.unauthorized` and `.unexpectedStatus` arms to `classify`, both `.terminal`.
- `Sources/CommentRelayUI/Resources/en.lproj/Localizable.strings` — new `crl.error.unauthorized`.
- `Sources/CommentRelayUI/Resources/es-419.lproj/Localizable.strings` — new `crl.error.unauthorized`.
- `Sources/CommentRelayUI/Shared/Strings.swift` — `static var errorUnauthorized`; extend `friendlyError(_:)` exhaustive switch.
- `Sources/CommentRelayUI/Screens/CommentRelayView.swift` — add explicit `.unauthorized` arm to private `message(for:)`.
- Tests:
  - `Tests/CommentRelayCoreTests/ErrorMapperTests.swift` (new) — full status-table sweep.
  - `Tests/CommentRelayCoreTests/RetryPolicyClassificationTests.swift` (new) — full case-table sweep.
  - `Tests/CommentRelayCoreTests/SubmissionProblemsTests.swift` (extend) — Category arms + token round-trip for the two new cases.
  - `Tests/CommentRelayUITests/ProblemStringsTests.swift` (extend) — `errorUnauthorized` resolves; `friendlyError(.unauthorized)` and `friendlyError(.unexpectedStatus)` map correctly.

---

## Task 0: Verify clean base

**Files:** none (gate).

- [ ] **Step 1: Confirm branch + clean tree**

Run:
```bash
git branch --show-current
git status --short
git --no-pager log --oneline -2
```
Expected:
- branch = `feature/CRLBS-120-error-mapper-status-classification`
- empty status (clean tree)
- HEAD is `6214b19 docs(CRLBS-120): design — ErrorMapper status classification & 401 handling`
- HEAD~1 is `f6c55c1 Merged in feature/CRLBS-121-history-problem-visibility (pull request #18)`

- [ ] **Step 2: Confirm starting test baseline**

Run: `swift test 2>&1 | tail -3`
Expected: `Executed 225 tests, with 0 failures (0 unexpected) in <…> seconds`

If anything in Steps 1-2 differs, STOP and report.

---

## Task 1: Add new error & Category cases (build stays green)

**Why this task is bundled:** `Category.init(_ error: CommentRelayError)` is an exhaustive switch with no `default`. Adding cases to `CommentRelayError` without simultaneously adding matching `Category` arms breaks compilation. Do them together so the project compiles at every step.

**Files:**
- Modify: `Sources/CommentRelayCore/Public/CommentRelayError.swift`
- Modify: `Sources/CommentRelayCore/Public/CommentRelaySubmissionProblem.swift`
- Test: `Tests/CommentRelayCoreTests/SubmissionProblemsTests.swift` (extend)

- [ ] **Step 1: Extend the Category mapping test first (TDD)**

In `Tests/CommentRelayCoreTests/SubmissionProblemsTests.swift`, in the existing `extension SubmissionProblemsTests` that holds `test_category_maps_from_commentRelayError`, append two assertions inside the existing test method:

```swift
        XCTAssertEqual(CommentRelaySubmissionProblem.Category(.unauthorized(message: "x")), .unauthorized)
        XCTAssertEqual(CommentRelaySubmissionProblem.Category(.unexpectedStatus(statusCode: 418, message: "x")), .unexpectedStatus)
```

And extend the `all` array in `test_category_token_roundtrips_and_defaults_to_unknown` to include the two new cases. Replace:

```swift
        let all: [CommentRelaySubmissionProblem.Category] = [
            .server, .transport, .rateLimited, .forbidden, .badRequest,
            .paymentRequired, .notFound, .decoding, .conflict,
            .uploadFailed, .uploadUrlExpired, .unknown
        ]
```

with:

```swift
        let all: [CommentRelaySubmissionProblem.Category] = [
            .server, .transport, .rateLimited, .forbidden, .badRequest,
            .paymentRequired, .notFound, .decoding, .conflict,
            .uploadFailed, .uploadUrlExpired, .unauthorized, .unexpectedStatus, .unknown
        ]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SubmissionProblemsTests`
Expected: FAIL — `CommentRelayError` has no `.unauthorized` / `.unexpectedStatus` cases; `Category` has no `.unauthorized` / `.unexpectedStatus` cases.

- [ ] **Step 3: Add the new CommentRelayError cases**

In `Sources/CommentRelayCore/Public/CommentRelayError.swift`, replace the existing enum body so it reads:

```swift
import Foundation

public enum CommentRelayError: Error {
    case badRequest(message: String)
    case unauthorized(message: String)
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
    case unexpectedStatus(statusCode: Int, message: String)

    /// A terminal error should flip the SDK into a disabled state until `reset()` is called.
    public var isTerminal: Bool {
        if case .forbidden = self { return true }
        return false
    }
}
```

Note: `isTerminal` deliberately stays `forbidden`-only. `.unauthorized` is `terminal` in `RetryPolicy` (this submission fails, surface to caller) but does NOT engage the circuit breaker — per spec decision.

- [ ] **Step 4: Add matching Category cases and switch arms**

In `Sources/CommentRelayCore/Public/CommentRelaySubmissionProblem.swift`, replace the existing `Category` enum body so it reads:

```swift
    /// Localization-free error category; the UI maps this to a friendly message.
    public enum Category: String, Sendable, Equatable {
        case server, transport, rateLimited, forbidden, badRequest
        case paymentRequired, notFound, decoding, conflict
        case uploadFailed, uploadUrlExpired
        case unauthorized, unexpectedStatus
        case unknown

        public init(_ error: CommentRelayError) {
            switch error {
            case .server:           self = .server
            case .transport:        self = .transport
            case .rateLimited:      self = .rateLimited
            case .forbidden:        self = .forbidden
            case .badRequest:       self = .badRequest
            case .paymentRequired:  self = .paymentRequired
            case .notFound:         self = .notFound
            case .decoding:         self = .decoding
            case .conflict:         self = .conflict
            case .uploadFailed:     self = .uploadFailed
            case .uploadUrlExpired: self = .uploadUrlExpired
            case .unauthorized:     self = .unauthorized
            case .unexpectedStatus: self = .unexpectedStatus
            }
        }
        init(token: String?) { self = token.flatMap(Category.init(rawValue:)) ?? .unknown }
    }
```

The switch is still exhaustive over the now-13 `CommentRelayError` cases, no `default` arm.

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter SubmissionProblemsTests`
Expected: PASS (the existing 4 tests plus the two new assertions inside `test_category_maps_from_commentRelayError` and the extended round-trip).

- [ ] **Step 6: Run full Core suite to confirm no regression**

Run: `swift test --filter CommentRelayCoreTests`
Expected: `0 failures`. Specifically, `Strings.friendlyError(_:Category)`'s exhaustive switch will NOT compile yet — but that's in the UI module. Confirm Core is clean. The UI module compile error is expected and is fixed in Task 4.

- [ ] **Step 7: Verify the build state**

Run: `swift build 2>&1 | tail -5`
Expected: BUILD FAILED with errors in `Sources/CommentRelayUI/Shared/Strings.swift` saying `Switch must be exhaustive` (or similar) because `friendlyError(_:)` doesn't handle the new `.unauthorized` / `.unexpectedStatus` Category cases. This is intentional — Task 4 fixes it. Until then, **do not commit** and **do not advance to Task 2/3 yet**.

If Core tests pass but build fails only at `friendlyError`, that's the expected midpoint. Proceed to Step 8.

- [ ] **Step 8: Temporarily extend `friendlyError` so the build is green for commit**

In `Sources/CommentRelayUI/Shared/Strings.swift`, change the existing catch-all arm of `friendlyError(_:)`. Today it reads:

```swift
        case .server, .transport, .forbidden,
             .badRequest, .notFound, .decoding,
             .conflict, .unknown:              return errorGeneric
```

Replace with (temporarily adding both new cases to the same generic-fallback arm; Task 4 will split out `.unauthorized` to its own dedicated message):

```swift
        case .server, .transport, .forbidden,
             .badRequest, .notFound, .decoding,
             .conflict, .unauthorized, .unexpectedStatus, .unknown: return errorGeneric
```

This keeps the project compiling. The dedicated `errorUnauthorized` message is wired in Task 4.

- [ ] **Step 9: Build and test**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`

Run: `swift test 2>&1 | tail -3`
Expected: `Executed 226 tests, with 0 failures` (225 prior + 0 new methods — the added asserts went inside existing test methods; if the implementer's framework reports the count differently because the round-trip test iterates more cases, accept any count >= 225 with 0 failures).

- [ ] **Step 10: Commit**

```bash
git add Sources/CommentRelayCore/Public/CommentRelayError.swift Sources/CommentRelayCore/Public/CommentRelaySubmissionProblem.swift Sources/CommentRelayUI/Shared/Strings.swift Tests/CommentRelayCoreTests/SubmissionProblemsTests.swift
git commit -m "feat(CRLBS-120): add CommentRelayError .unauthorized + .unexpectedStatus cases

Adds the two new public error cases per the CRLBS-120 design. Matching
arms added to CommentRelaySubmissionProblem.Category (still exhaustive,
no default). Strings.friendlyError temporarily routes both to
errorGeneric so the project compiles end-to-end; Task 4 wires the
dedicated errorUnauthorized message.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Rewrite ErrorMapper to use the new cases by status range

**Files:**
- Modify: `Sources/CommentRelayCore/Internal/ErrorMapper.swift`
- Test (create): `Tests/CommentRelayCoreTests/ErrorMapperTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/CommentRelayCoreTests/ErrorMapperTests.swift`:

```swift
import XCTest
@testable import CommentRelayCore

final class ErrorMapperTests: XCTestCase {
    private func response(_ code: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://example.com")!,
                        statusCode: code,
                        httpVersion: nil,
                        headerFields: headers)!
    }
    private let emptyBody = Data()

    func test_enumerated_4xx_map_to_specific_cases() {
        if case .badRequest = ErrorMapper.map(response: response(400), data: emptyBody) {} else {
            XCTFail("400 should map to .badRequest")
        }
        if case .unauthorized = ErrorMapper.map(response: response(401), data: emptyBody) {} else {
            XCTFail("401 should map to .unauthorized")
        }
        if case .paymentRequired = ErrorMapper.map(response: response(402), data: emptyBody) {} else {
            XCTFail("402 should map to .paymentRequired")
        }
        if case .forbidden = ErrorMapper.map(response: response(403), data: emptyBody) {} else {
            XCTFail("403 should map to .forbidden")
        }
        if case .notFound = ErrorMapper.map(response: response(404), data: emptyBody) {} else {
            XCTFail("404 should map to .notFound")
        }
        if case .conflict = ErrorMapper.map(response: response(409), data: emptyBody) {} else {
            XCTFail("409 should map to .conflict")
        }
    }

    func test_429_maps_to_rateLimited_with_retry_after() {
        let result = ErrorMapper.map(response: response(429, headers: ["Retry-After": "5"]), data: emptyBody)
        guard case .rateLimited(let after) = result else {
            return XCTFail("429 should map to .rateLimited, got \(result)")
        }
        XCTAssertEqual(after, 5)
    }

    func test_429_without_retry_after_is_nil() {
        let result = ErrorMapper.map(response: response(429), data: emptyBody)
        guard case .rateLimited(let after) = result else {
            return XCTFail("429 should map to .rateLimited, got \(result)")
        }
        XCTAssertNil(after)
    }

    func test_5xx_maps_to_server() {
        for code in [500, 502, 503, 504, 599] {
            if case .server = ErrorMapper.map(response: response(code), data: emptyBody) {} else {
                XCTFail("\(code) should map to .server")
            }
        }
    }

    func test_other_4xx_maps_to_unexpectedStatus() {
        for code in [405, 410, 415, 418, 422, 451] {
            let result = ErrorMapper.map(response: response(code), data: emptyBody)
            guard case .unexpectedStatus(let statusCode, _) = result else {
                return XCTFail("\(code) should map to .unexpectedStatus, got \(result)")
            }
            XCTAssertEqual(statusCode, code, "preserved status code")
        }
    }

    func test_out_of_range_status_maps_to_unexpectedStatus() {
        // Status codes outside 500..<600 (e.g. 600+) must fall through to .unexpectedStatus,
        // not .server. Guards against an off-by-one in the range bound.
        let result = ErrorMapper.map(response: response(600), data: emptyBody)
        guard case .unexpectedStatus(let statusCode, _) = result else {
            return XCTFail("600 should map to .unexpectedStatus, got \(result)")
        }
        XCTAssertEqual(statusCode, 600)
    }

    func test_envelope_message_is_used_when_present() {
        let body = #"{"error":{"code":"X","message":"forbidden detail"}}"#.data(using: .utf8)!
        let result = ErrorMapper.map(response: response(403), data: body)
        guard case .forbidden(let msg) = result else {
            return XCTFail("expected .forbidden")
        }
        XCTAssertEqual(msg, "forbidden detail")
    }

    func test_fallback_message_when_body_is_not_envelope() {
        let result = ErrorMapper.map(response: response(404), data: Data("not json".utf8))
        guard case .notFound(let msg) = result else {
            return XCTFail("expected .notFound")
        }
        XCTAssertEqual(msg, "HTTP 404")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter ErrorMapperTests`
Expected: FAIL — `test_other_4xx_maps_to_unexpectedStatus`, `test_out_of_range_status_maps_to_unexpectedStatus`, and `test_5xx_maps_to_server` all fail because the current `default → .server` swallows everything. (`test_enumerated_4xx_map_to_specific_cases` also fails on 401 because today 401 falls into the default → .server bucket.)

- [ ] **Step 3: Rewrite ErrorMapper**

In `Sources/CommentRelayCore/Internal/ErrorMapper.swift`, replace the entire file content with:

```swift
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
        case 401: return .unauthorized(message: message)
        case 402: return .paymentRequired(message: message)
        case 403: return .forbidden(message: message)
        case 404: return .notFound(message: message)
        case 409: return .conflict(message: message)
        case 429:
            let retry = (response.value(forHTTPHeaderField: "Retry-After")).flatMap(TimeInterval.init)
            return .rateLimited(retryAfter: retry)
        case 500..<600:
            return .server(message: message)
        default:
            return .unexpectedStatus(statusCode: response.statusCode, message: message)
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter ErrorMapperTests`
Expected: PASS (all 8 test methods).

- [ ] **Step 5: Run the full Core suite (no regression)**

Run: `swift test --filter CommentRelayCoreTests`
Expected: `0 failures`. The behavior change (401 now `.unauthorized` instead of `.server → .retry`) does NOT touch any existing test — no test currently asserts the old broken behavior.

- [ ] **Step 6: Commit**

```bash
git add Sources/CommentRelayCore/Internal/ErrorMapper.swift Tests/CommentRelayCoreTests/ErrorMapperTests.swift
git commit -m "feat(CRLBS-120): ErrorMapper enumerates 401, ranges 5xx, surfaces unknown

Replaces the blanket default→.server (which silently retried every
unhandled status forever, incl. 401 and unknown 4xx) with:
  enumerated 400/401/402/403/404/409/429 → specific cases
  500..<600 → .server (retryable, unchanged semantics)
  default   → .unexpectedStatus(statusCode:message:) (terminal)
Adds ErrorMapperTests sweeping the status table.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: RetryPolicy classifies the new cases as terminal

**Files:**
- Modify: `Sources/CommentRelayCore/Internal/RetryPolicy.swift`
- Test (create): `Tests/CommentRelayCoreTests/RetryPolicyClassificationTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/CommentRelayCoreTests/RetryPolicyClassificationTests.swift`:

```swift
import XCTest
@testable import CommentRelayCore

final class RetryPolicyClassificationTests: XCTestCase {
    func test_retryable_cases() {
        // .server and .transport retry with nil retry-after.
        switch RetryPolicy.classify(.server(message: "x")) {
        case .retry(let after): XCTAssertNil(after)
        default: XCTFail("expected .retry")
        }
        let urlErr = URLError(.notConnectedToInternet)
        switch RetryPolicy.classify(.transport(urlErr)) {
        case .retry(let after): XCTAssertNil(after)
        default: XCTFail("expected .retry")
        }
        // .rateLimited carries Retry-After through.
        switch RetryPolicy.classify(.rateLimited(retryAfter: 7)) {
        case .retry(let after): XCTAssertEqual(after, 7)
        default: XCTFail("expected .retry")
        }
    }

    func test_pause_case() {
        guard case .pause = RetryPolicy.classify(.forbidden(message: "x")) else {
            return XCTFail("expected .pause")
        }
    }

    func test_terminal_cases_including_new_ones() {
        let terminals: [CommentRelayError] = [
            .badRequest(message: "x"),
            .paymentRequired(message: "x"),
            .notFound(message: "x"),
            .decoding(NSError(domain: "x", code: 1)),
            .conflict(message: "x"),
            .uploadFailed(submissionId: UUID(), fileName: "f", underlying: NSError(domain: "x", code: 1)),
            .uploadUrlExpired(submissionId: UUID()),
            // CRLBS-120: new terminal cases
            .unauthorized(message: "x"),
            .unexpectedStatus(statusCode: 418, message: "x"),
        ]
        for err in terminals {
            XCTAssertEqual(RetryPolicy.classify(err), .terminal, "\(err) should be terminal")
        }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter RetryPolicyClassificationTests`
Expected: FAIL — `Switch must be exhaustive` compile error in `RetryPolicy.classify` (it doesn't yet handle the two new cases).

- [ ] **Step 3: Update RetryPolicy.classify**

In `Sources/CommentRelayCore/Internal/RetryPolicy.swift`, replace the existing `classify` function so it reads:

```swift
    static func classify(_ error: CommentRelayError) -> RetryDecision {
        switch error {
        case .transport, .server: return .retry(nil)
        case .rateLimited(let after): return .retry(after)
        case .forbidden: return .pause
        case .badRequest, .paymentRequired, .notFound, .decoding,
             .conflict, .uploadFailed, .uploadUrlExpired,
             .unauthorized, .unexpectedStatus:
            return .terminal
        }
    }
```

The switch stays exhaustive over all 13 `CommentRelayError` cases, no `default`.

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter RetryPolicyClassificationTests`
Expected: PASS (3 test methods).

- [ ] **Step 5: Run full Core suite (no regression)**

Run: `swift test --filter CommentRelayCoreTests`
Expected: 0 failures. Existing flush/queue tests rely on `.retry` / `.terminal` / `.pause` behavior — the only new effect of this change is that 401-classified-as-`.unauthorized` now hits `.terminal` instead of `.retry`, which no existing test asserts either way.

- [ ] **Step 6: Commit**

```bash
git add Sources/CommentRelayCore/Internal/RetryPolicy.swift Tests/CommentRelayCoreTests/RetryPolicyClassificationTests.swift
git commit -m "feat(CRLBS-120): RetryPolicy classifies .unauthorized + .unexpectedStatus as terminal

Adds the two new CommentRelayError cases to RetryPolicy.classify's
terminal bucket. Switch remains exhaustive (no default). Adds a
full classification regression test for every CommentRelayError case.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Localized errorUnauthorized + wire it through

**Files:**
- Modify: `Sources/CommentRelayUI/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/CommentRelayUI/Resources/es-419.lproj/Localizable.strings`
- Modify: `Sources/CommentRelayUI/Shared/Strings.swift`
- Modify: `Sources/CommentRelayUI/Screens/CommentRelayView.swift`
- Test: `Tests/CommentRelayUITests/ProblemStringsTests.swift` (extend)

- [ ] **Step 1: Write the failing tests first**

In `Tests/CommentRelayUITests/ProblemStringsTests.swift`, add two test methods to the existing `ProblemStringsTests` class:

```swift
    func test_errorUnauthorized_resolves_non_empty() {
        let s = Strings.errorUnauthorized
        XCTAssertFalse(s.isEmpty)
        XCTAssertNotEqual(s, "crl.error.unauthorized", "string did not resolve")
    }

    func test_friendlyError_maps_unauthorized_to_dedicated_message_and_unexpectedStatus_to_generic() {
        XCTAssertEqual(Strings.friendlyError(.unauthorized), Strings.errorUnauthorized)
        XCTAssertEqual(Strings.friendlyError(.unexpectedStatus), Strings.errorGeneric)
    }
```

Also extend the existing `test_problem_strings_resolve_non_empty` to include `Strings.errorUnauthorized` in the loop — find that test and add `Strings.errorUnauthorized` to the array iterated by the `for s in [...]` loop. (Verification: the loop checks `!s.isEmpty` and `!s.hasPrefix("crl.problem.")`. The `errorUnauthorized` prefix is `crl.error.` not `crl.problem.`, so update the prefix check OR move the new assertion to the new dedicated test method above — the dedicated test already covers it, so leave the existing `test_problem_strings_resolve_non_empty` loop unchanged.)

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter ProblemStringsTests`
Expected: FAIL — `Strings` has no `errorUnauthorized` member.

- [ ] **Step 3: Add the en string**

Append to `Sources/CommentRelayUI/Resources/en.lproj/Localizable.strings`:

```
"crl.error.unauthorized" = "Your API key isn't authorized to send feedback.";
```

- [ ] **Step 4: Add the es-419 string**

Append to `Sources/CommentRelayUI/Resources/es-419.lproj/Localizable.strings`:

```
"crl.error.unauthorized" = "Tu clave de API no está autorizada para enviar comentarios.";
```

- [ ] **Step 5: Add the Strings accessor**

In `Sources/CommentRelayUI/Shared/Strings.swift`, find the line `static var errorGeneric: String { string("crl.error.generic") }` and add the new accessor immediately above it:

```swift
    static var errorUnauthorized: String { string("crl.error.unauthorized") }
```

- [ ] **Step 6: Split `.unauthorized` out of the generic-fallback arm in `friendlyError`**

In the same file, find the existing `friendlyError(_:)` body (added partially in Task 1, Step 8). Today it reads:

```swift
    static func friendlyError(_ c: CommentRelaySubmissionProblem.Category) -> String {
        switch c {
        case .rateLimited:                     return errorRateLimited
        case .paymentRequired:                 return errorPaymentRequired
        case .uploadFailed, .uploadUrlExpired: return errorUploadFailed
        case .server, .transport, .forbidden,
             .badRequest, .notFound, .decoding,
             .conflict, .unauthorized, .unexpectedStatus, .unknown: return errorGeneric
        }
    }
```

Replace with:

```swift
    static func friendlyError(_ c: CommentRelaySubmissionProblem.Category) -> String {
        switch c {
        case .rateLimited:                     return errorRateLimited
        case .paymentRequired:                 return errorPaymentRequired
        case .uploadFailed, .uploadUrlExpired: return errorUploadFailed
        case .unauthorized:                    return errorUnauthorized
        case .server, .transport, .forbidden,
             .badRequest, .notFound, .decoding,
             .conflict, .unexpectedStatus, .unknown: return errorGeneric
        }
    }
```

The switch is still exhaustive over all 14 `Category` cases.

- [ ] **Step 7: Add the explicit arm in `CommentRelayView.message(for:)`**

In `Sources/CommentRelayUI/Screens/CommentRelayView.swift`, find the private `message(for:)` function near line 188. It currently reads:

```swift
    private func message(for error: CommentRelayError) -> String {
        switch error {
        case .paymentRequired: return Strings.errorPaymentRequired
        case .rateLimited: return Strings.errorRateLimited
        case .uploadFailed: return Strings.errorUploadFailed
        default: return Strings.errorGeneric
        }
    }
```

Add an explicit `.unauthorized` arm so the user-visible progress-failed screen surfaces the dedicated message:

```swift
    private func message(for error: CommentRelayError) -> String {
        switch error {
        case .paymentRequired: return Strings.errorPaymentRequired
        case .rateLimited: return Strings.errorRateLimited
        case .uploadFailed: return Strings.errorUploadFailed
        case .unauthorized: return Strings.errorUnauthorized
        default: return Strings.errorGeneric
        }
    }
```

(Leave the `default` arm — this function uses `default` by design; we're just adding the one new explicit case the user asked for.)

- [ ] **Step 8: Build and run tests**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`

Run: `swift test --filter ProblemStringsTests`
Expected: PASS (4 test methods total — original 2 + new 2).

Run: `swift test 2>&1 | tail -3`
Expected: `Executed N tests, with 0 failures` where N is the prior full-suite count plus the new test methods.

- [ ] **Step 9: Commit**

```bash
git add Sources/CommentRelayUI/Resources/en.lproj/Localizable.strings Sources/CommentRelayUI/Resources/es-419.lproj/Localizable.strings Sources/CommentRelayUI/Shared/Strings.swift Sources/CommentRelayUI/Screens/CommentRelayView.swift Tests/CommentRelayUITests/ProblemStringsTests.swift
git commit -m "feat(CRLBS-120): dedicated localized errorUnauthorized + wiring

New crl.error.unauthorized in en + es-419, Strings.errorUnauthorized
accessor, dedicated arm in Strings.friendlyError(.unauthorized), and
explicit arm in CommentRelayView.message(for:) so the progress-failed
screen surfaces the dedicated message rather than errorGeneric.
.unexpectedStatus continues to fall through to errorGeneric (status
code is preserved in technical detail).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Full verification, sample build, push, open PR

**Files:** none (verification + ship).

- [ ] **Step 1: Full test suite**

Run: `swift test 2>&1 | tail -5`
Expected: `Executed N tests, with 0 failures` (N = 225 prior + new methods across Tasks 1–4; exact count not pinned — accept any "0 failures").

- [ ] **Step 2: macOS sample app build**

Run:
```bash
cd Example/CommentRelaySample
xcodebuild -project CommentRelaySample.xcodeproj -scheme CommentRelaySample -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DD build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)|\*\* " | head -10
rm -rf build
cd -
```
Expected: `** BUILD SUCCEEDED **`. If FAIL, paste errors and STOP (BLOCKED).

- [ ] **Step 3: Push branch**

```bash
git push -u origin feature/CRLBS-120-error-mapper-status-classification 2>&1 | tail -2
```

- [ ] **Step 4: Open Bitbucket PR to develop**

```bash
bb pr create -s feature/CRLBS-120-error-mapper-status-classification -d develop \
  -t "fix(CRLBS-120): ErrorMapper surfaces 401 + unknown statuses; only 5xx retries" \
  -b "$(cat <<'PR_BODY_EOF'
Implements `docs/superpowers/specs/2026-05-20-error-mapper-status-classification-design.md` per `docs/superpowers/plans/2026-05-21-error-mapper-status-classification.md`.

## Problem
ErrorMapper routed every unenumerated HTTP status — including 401 and unknown 4xx — through `default → .server`, which RetryPolicy treats as `.retry`. So a bad/unprovisioned key silently queued submissions forever, as did any 405/410/415/422/451/…

## Fix
- Two new public `CommentRelayError` cases: `.unauthorized(message:)`, `.unexpectedStatus(statusCode:message:)`.
- ErrorMapper switch is now: enumerated 400/401/402/403/404/409/429 → specific cases; `500..<600` → `.server` (retryable, unchanged); default → `.unexpectedStatus` (terminal, preserves the real code).
- RetryPolicy.classify treats both new cases as `.terminal`.
- `CommentRelaySubmissionProblem.Category` extended with matching cases; switch stays exhaustive (no `default`).
- Dedicated `crl.error.unauthorized` string in en + es-419; wired via `Strings.errorUnauthorized` into `Strings.friendlyError(.unauthorized)` and `CommentRelayView.message(for:)`. `.unexpectedStatus` falls through to `errorGeneric` (real code preserved in `technicalDetail`).

## Tests
- New `ErrorMapperTests` (8 methods): enumerated 4xx, 429 with/without Retry-After, 5xx range, unknown 4xx, out-of-range, envelope vs fallback messages.
- New `RetryPolicyClassificationTests` (3 methods): retry/pause/terminal table for every CommentRelayError case.
- Extended `SubmissionProblemsTests` and `ProblemStringsTests` for new Category/Strings paths.

## Side effect to expect when smoke-testing
The sample app's default `crk_test_sample` key likely 401s against prod. Pre-fix it queued silently; post-fix it surfaces as a visible CRLBS-121 "Failed to send" problem row with the dedicated unauthorized message. Intended behavior; flagged so it isn't surprising.

JIRA: https://commentrelay.atlassian.net/browse/CRLBS-120

🤖 Generated with [Claude Code](https://claude.com/claude-code)
PR_BODY_EOF
)"
```
Paste the `bb pr create` output (PR number + URL).

- [ ] **Step 5: Confirm clean working tree**

```bash
git status --porcelain
```
Expected: empty.

---

## Self-review

**1. Spec coverage:** Every spec section is implemented by a task.
- Two new `CommentRelayError` cases → Task 1.
- `ErrorMapper` range-based switch → Task 2.
- `RetryPolicy.classify` updates → Task 3.
- `Category` extensions with exhaustive switch → Task 1.
- `Strings.errorUnauthorized` + en/es + `friendlyError` arms → Task 4.
- `CommentRelayView.message(for:)` explicit arm → Task 4.
- `ErrorMapperTests` + `RetryPolicyClassificationTests` + extended existing tests → Tasks 2, 3, 1, 4.
- Sequencing + base + deliberate side-effect note → header + Task 5 PR body.

**2. Placeholder scan:** No TBD/TODO; every code-change step shows full code; every command has an expected outcome (including the intentional mid-task build-failure in Task 1 Step 7, with the fix in Step 8 also shown in full).

**3. Type consistency:**
- `CommentRelayError.unauthorized(message:)` and `.unexpectedStatus(statusCode:message:)` — same names/labels across Tasks 1/2/3/4 and the tests.
- `CommentRelaySubmissionProblem.Category.unauthorized` and `.unexpectedStatus` — same names across Tasks 1/2/3/4 and tests.
- `Strings.errorUnauthorized` — same accessor in Tasks 4 and ProblemStringsTests.
- `crl.error.unauthorized` key — same in en + es and the Strings accessor.

**4. Known verification points (not placeholders, called out explicitly):**
- Task 1 Step 7 expects a transient build failure as a TDD signal; Step 8 fixes it within the same task — explicit and intentional, not a placeholder.
- Test count after Task 1 may be 225 + n where n depends on whether new assertions inside existing methods register as new test methods (they do not — only the new dedicated test methods in Task 2/3/4 increase the count). Step 9 of Task 1 accepts ">= 225 with 0 failures" rather than a hard count.
- The macOS sample app build uses an isolated `-derivedDataPath build/DD` to avoid the `cdk.out`-style concurrency clash hit during CRLBS-119 test deploys.
