# SP1 — API Conformance, macOS Platform, Apple Privacy & SPM — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the iOS SDK verifiably conform to the CommentRelay API, report `macos`, and satisfy Apple's third-party-SDK privacy requirements for SPM source distribution.

**Architecture:** Two phases. **Phase A** (`commentrelay-api`): add `macos` to the submission platform enum + fix stale docs. **Phase B** (`commentrelay-sdk-ios`): rating-label conformance fix, `Platform.macos`/`Platform.current`, per-target privacy manifests, SPM packaging. The two `CommentRelayView` call-site switches that *emit* `.macos` are release-gated on Phase A being deployed.

**Tech Stack:** TypeScript + Zod + Jest (API); Swift 6 / SPM / XCTest (SDK); Apple `PrivacyInfo.xcprivacy` plist.

**Spec:** `commentrelay-sdk-ios/docs/superpowers/specs/2026-05-17-ios-sdk-api-conformance-privacy-spm-design.md`
**Ticket:** CRLBS-113.

## Branches & conventions

- API work: branch `feature/CRLBS-113-api-macos-platform-docs` off `develop` in `/Users/mikesilvers/repos/commentrelay/commentrelay-api`.
- SDK work: branch `feature/CRLBS-113-sdk-conformance-privacy-spm` (already exists, checked out) in `/Users/mikesilvers/repos/commentrelay-sdk/commentrelay-sdk-ios`.
- Commits: `type(CRLBS-113): description`, ending with the line `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`. Push after each task (CLAUDE.md convention).

## File structure

| File | Repo | Responsibility | Action |
|---|---|---|---|
| `src/feedback/submission-schema.ts` | api | Zod request validator (enforcing) | Modify L24 |
| `src/shared/types.ts` | api | shared TS platform union | Modify L127 |
| `src/feedback/sdk-submit.ts` | api | submit handler platform type | Modify L35 |
| `tests/unit/feedback/sdk-submit.test.ts` | api | schema unit tests | Add test |
| `docs/sdk-use.md` | api | SDK API reference doc | Modify L51, L127 |
| `Sources/CommentRelayCore/Public/Models/Platform.swift` | sdk | platform enum + `.current` | Modify |
| `Tests/CommentRelayCoreTests/PlatformTests.swift` | sdk | platform tests | Create |
| `Sources/CommentRelayUI/Screens/FeedbackFormViewModel.swift` | sdk | rating payload build | Modify rating case |
| `Tests/CommentRelayUITests/RatingPayloadTests.swift` | sdk | rating payload test | Create |
| `Sources/CommentRelayUI/Screens/CommentRelayView.swift` | sdk | platform call sites | Modify L56, L105 |
| `Sources/CommentRelayCore/PrivacyInfo.xcprivacy` | sdk | Core privacy manifest | Create |
| `Sources/CommentRelayUI/PrivacyInfo.xcprivacy` | sdk | UI privacy manifest | Create |
| `Package.swift` | sdk | resource wiring | Modify targets |
| `README.md` | sdk | privacy/SPM note | Modify |

---

## PHASE A — commentrelay-api (prerequisite; merge + deploy before Phase B release)

### Task 1: Add `macos` to the submission platform enum

**Files:**
- Modify: `/Users/mikesilvers/repos/commentrelay/commentrelay-api/src/feedback/submission-schema.ts:24`
- Modify: `/Users/mikesilvers/repos/commentrelay/commentrelay-api/src/shared/types.ts:127`
- Modify: `/Users/mikesilvers/repos/commentrelay/commentrelay-api/src/feedback/sdk-submit.ts:35`
- Test: `/Users/mikesilvers/repos/commentrelay/commentrelay-api/tests/unit/feedback/sdk-submit.test.ts`

- [ ] **Step 1: Create the API branch**

```bash
cd /Users/mikesilvers/repos/commentrelay/commentrelay-api
git checkout develop && git pull --ff-only
git checkout -b feature/CRLBS-113-api-macos-platform-docs
```

- [ ] **Step 2: Write the failing test**

Append to `tests/unit/feedback/sdk-submit.test.ts` (the file already imports `CreateSubmissionSchema` from `@feedback/submission-schema`). Add this `describe` block at the end of the file:

```typescript
describe('CreateSubmissionSchema platform enum', () => {
  const base = {
    form_id: '11111111-1111-1111-1111-111111111111',
    fields: [{ field_id: '22222222-2222-2222-2222-222222222222', value: 'hi' }],
    user_identifier: 'user-1',
  };

  it.each(['ios', 'android', 'web', 'server', 'other', 'macos'])(
    'accepts platform "%s"',
    (platform) => {
      const result = CreateSubmissionSchema.safeParse({ ...base, platform });
      expect(result.success).toBe(true);
    },
  );

  it('rejects an unknown platform', () => {
    const result = CreateSubmissionSchema.safeParse({ ...base, platform: 'windows' });
    expect(result.success).toBe(false);
  });
});
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd /Users/mikesilvers/repos/commentrelay/commentrelay-api && npx jest tests/unit/feedback/sdk-submit.test.ts -t "platform enum"`
Expected: FAIL — the `'macos'` case fails (`result.success` is `false`) because the enum lacks `macos`.

- [ ] **Step 4: Add `macos` to the enum and the two TS unions**

In `src/feedback/submission-schema.ts` line 24, change:
```typescript
  platform: z.enum(['ios', 'android', 'web', 'server', 'other']),
```
to:
```typescript
  platform: z.enum(['ios', 'android', 'web', 'server', 'other', 'macos']),
```

In `src/shared/types.ts` line 127, change:
```typescript
  platform: 'ios' | 'android' | 'web' | 'server' | 'other';
```
to:
```typescript
  platform: 'ios' | 'android' | 'web' | 'server' | 'other' | 'macos';
```

In `src/feedback/sdk-submit.ts` line 35, change:
```typescript
  platform: 'ios' | 'android' | 'web' | 'server' | 'other';
```
to:
```typescript
  platform: 'ios' | 'android' | 'web' | 'server' | 'other' | 'macos';
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd /Users/mikesilvers/repos/commentrelay/commentrelay-api && npx jest tests/unit/feedback/sdk-submit.test.ts -t "platform enum"`
Expected: PASS (all 6 platforms accepted, `windows` rejected).

- [ ] **Step 6: Run the full unit suite to confirm no regression**

Run: `cd /Users/mikesilvers/repos/commentrelay/commentrelay-api && npm run test:unit`
Expected: all tests pass (no new failures vs. baseline).

- [ ] **Step 7: Commit & push**

```bash
cd /Users/mikesilvers/repos/commentrelay/commentrelay-api
git add src/feedback/submission-schema.ts src/shared/types.ts src/feedback/sdk-submit.ts tests/unit/feedback/sdk-submit.test.ts
git commit -m "feat(CRLBS-113): accept 'macos' platform in SDK submission schema

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
git push -u origin feature/CRLBS-113-api-macos-platform-docs
```

---

### Task 2: Fix stale `response_limit_window_days` docs

**Files:**
- Modify: `/Users/mikesilvers/repos/commentrelay/commentrelay-api/docs/sdk-use.md:51,127`

- [ ] **Step 1: Confirm the exact drift**

Run: `cd /Users/mikesilvers/repos/commentrelay/commentrelay-api && grep -rn "response_limit_window_days\|window_days" docs/`
Expected: matches at `docs/sdk-use.md:51` and `docs/sdk-use.md:127` (and no others; if other files appear, apply the same replacement there too in Step 2).

- [ ] **Step 2: Replace `_days` with `_minutes` in the doc**

In `docs/sdk-use.md` line 51, change:
```json
      "response_limit_window_days": null,
```
to:
```json
      "response_limit_window_minutes": null,
```

In `docs/sdk-use.md` line 127, change:
```
| `time_window` | Limit within `response_limit_window_days` days |
```
to:
```
| `time_window` | Limit within `response_limit_window_minutes` minutes |
```

If Step 1 reported matches in any other `docs/` file, apply the identical `response_limit_window_days` → `response_limit_window_minutes` (and "days" → "minutes" wording) replacement there.

- [ ] **Step 3: Verify no `_days` drift remains and `_minutes` is what the code emits**

Run: `cd /Users/mikesilvers/repos/commentrelay/commentrelay-api && grep -rn "response_limit_window_days" docs/ ; echo "---" ; grep -rEoh "response_limit_window_[a-z]+" src | sort -u`
Expected: first grep prints nothing (no `_days` left in docs); second prints `response_limit_window_minutes` (the value the source actually emits), confirming docs now match code.

- [ ] **Step 4: Commit & push**

```bash
cd /Users/mikesilvers/repos/commentrelay/commentrelay-api
git add docs/sdk-use.md
git commit -m "docs(CRLBS-113): correct response_limit_window_days -> _minutes to match emitted API

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
git push
```

---

## PHASE B — commentrelay-sdk-ios

All Phase B tasks run in `/Users/mikesilvers/repos/commentrelay-sdk/commentrelay-sdk-ios` on the already-checked-out branch `feature/CRLBS-113-sdk-conformance-privacy-spm`. Verify with `git branch --show-current` before starting.

### Task 3: `Platform.macos` + `Platform.current`

**Files:**
- Modify: `Sources/CommentRelayCore/Public/Models/Platform.swift`
- Test: `Tests/CommentRelayCoreTests/PlatformTests.swift` (create)

- [ ] **Step 1: Write the failing test**

Create `Tests/CommentRelayCoreTests/PlatformTests.swift`:
```swift
import XCTest
@testable import CommentRelayCore

final class PlatformTests: XCTestCase {
    func testPlatformCurrentMatchesCompiledOS() {
        #if os(iOS)
        XCTAssertEqual(Platform.current, .ios)
        #elseif os(macOS)
        XCTAssertEqual(Platform.current, .macos)
        #else
        XCTAssertEqual(Platform.current, .other)
        #endif
    }

    func testMacosEncodesToWireValue() throws {
        let data = try JSONEncoder().encode(Platform.macos)
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"macos\"")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd /Users/mikesilvers/repos/commentrelay-sdk/commentrelay-sdk-ios && swift test --filter PlatformTests 2>&1 | tail -20`
Expected: FAIL — compile error / unresolved `Platform.current` and `Platform.macos`.

- [ ] **Step 3: Implement the enum case and `current`**

Replace the entire contents of `Sources/CommentRelayCore/Public/Models/Platform.swift` with:
```swift
import Foundation

public enum Platform: String, Codable, Sendable, Equatable {
    case ios, android, web, server, other, macos
}

public extension Platform {
    /// The platform the SDK is currently running on.
    /// iPadOS and Mac Catalyst compile under `os(iOS)` and report `.ios`.
    static var current: Platform {
        #if os(iOS)
        return .ios
        #elseif os(macOS)
        return .macos
        #else
        return .other
        #endif
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd /Users/mikesilvers/repos/commentrelay-sdk/commentrelay-sdk-ios && swift test --filter PlatformTests 2>&1 | tail -20`
Expected: PASS (on the macOS host, `Platform.current == .macos`; wire value `"macos"`).

- [ ] **Step 5: Commit & push**

```bash
cd /Users/mikesilvers/repos/commentrelay-sdk/commentrelay-sdk-ios
git add Sources/CommentRelayCore/Public/Models/Platform.swift Tests/CommentRelayCoreTests/PlatformTests.swift
git commit -m "feat(CRLBS-113): add Platform.macos and Platform.current

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
git push
```

---

### Task 4: C3 — rating payload includes `label`

**Files:**
- Modify: `Sources/CommentRelayUI/Screens/FeedbackFormViewModel.swift` (rating case in `buildSubmission()`, and add a private `RatingValue` type)
- Test: `Tests/CommentRelayUITests/RatingPayloadTests.swift` (create)

- [ ] **Step 1: Write the failing test**

Create `Tests/CommentRelayUITests/RatingPayloadTests.swift`:
```swift
import XCTest
import CommentRelayCore
@testable import CommentRelayUI

final class RatingPayloadTests: XCTestCase {
    private func smileyForm() throws -> CommentRelayForm {
        let json = """
        {
          "id": "form-1", "title": "T", "show_in_picker": true,
          "response_limit_count": 0, "response_limit_type": "lifetime",
          "response_limit_window_minutes": null, "more_feedback_prompt": "",
          "is_active": true, "sort_order": 1,
          "fields": [{
            "id": "rate-1", "field_type": "smiley_rating", "label": "Mood",
            "is_required": true, "is_gate": false, "sort_order": 1, "max_files": null,
            "options": [
              {"position": 1, "label": "Sad", "svg": "<svg/>"},
              {"position": 3, "label": "Neutral", "svg": "<svg/>"},
              {"position": 5, "label": "Happy", "svg": "<svg/>"}
            ]
          }]
        }
        """
        return try JSONDecoder().decode(CommentRelayForm.self, from: Data(json.utf8))
    }

    func testRatingPayloadIncludesLabel() throws {
        let vm = FeedbackFormViewModel(form: try smileyForm(),
                                       userIdentifier: "u", platform: .ios, sdkVersion: nil)
        vm.setInt("rate-1", 3)
        let submission = vm.buildSubmission()
        let body = try JSONEncoder().encode(submission)
        let s = String(data: body, encoding: .utf8)!
        XCTAssertTrue(s.contains("\\\"position\\\":3"), "missing position; body=\(s)")
        XCTAssertTrue(s.contains("\\\"label\\\":\\\"Neutral\\\""), "missing label; body=\(s)")
    }

    func testRatingPayloadFallsBackWhenNoOption() throws {
        let vm = FeedbackFormViewModel(form: try smileyForm(),
                                       userIdentifier: "u", platform: .ios, sdkVersion: nil)
        vm.setInt("rate-1", 99) // no matching option/label
        let submission = vm.buildSubmission()
        let body = try JSONEncoder().encode(submission)
        let s = String(data: body, encoding: .utf8)!
        XCTAssertTrue(s.contains("\\\"position\\\":99"), "missing position; body=\(s)")
        XCTAssertFalse(s.contains("\\\"label\\\""), "label must be absent when unknown; body=\(s)")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd /Users/mikesilvers/repos/commentrelay-sdk/commentrelay-sdk-ios && swift test --filter RatingPayloadTests 2>&1 | tail -20`
Expected: FAIL — `testRatingPayloadIncludesLabel` fails because the current payload is `{"position":3}` with no `label`.

- [ ] **Step 3: Implement label-aware rating encoding**

In `Sources/CommentRelayUI/Screens/FeedbackFormViewModel.swift`, add this private type immediately inside the `FeedbackFormViewModel` class body (e.g. directly above `public func buildSubmission()`):
```swift
    private struct RatingValue: Encodable {
        let position: Int
        let label: String?
    }
```

Then replace this exact block in `buildSubmission()`:
```swift
            case .smileyRating, .colorScale:
                if let v = intValues[field.id] {
                    let payload = #"{"position":\#(v)}"#
                    fieldValues.append(.text(fieldId: field.id, value: payload))
                }
```
with:
```swift
            case .smileyRating, .colorScale:
                if let v = intValues[field.id] {
                    let label = field.options?.first(where: { $0.position == v })?.label
                    let rating = RatingValue(position: v, label: label)
                    if let data = try? JSONEncoder().encode(rating),
                       let payload = String(data: data, encoding: .utf8) {
                        fieldValues.append(.text(fieldId: field.id, value: payload))
                    } else {
                        fieldValues.append(.text(fieldId: field.id, value: #"{"position":\#(v)}"#))
                    }
                }
```

Note: Swift's synthesized `Encodable` omits `label` when it is `nil`, so an unknown position yields `{"position":N}` (matches the fallback test).

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd /Users/mikesilvers/repos/commentrelay-sdk/commentrelay-sdk-ios && swift test --filter RatingPayloadTests 2>&1 | tail -20`
Expected: PASS (both tests).

- [ ] **Step 5: Commit & push**

```bash
cd /Users/mikesilvers/repos/commentrelay-sdk/commentrelay-sdk-ios
git add Sources/CommentRelayUI/Screens/FeedbackFormViewModel.swift Tests/CommentRelayUITests/RatingPayloadTests.swift
git commit -m "fix(CRLBS-113): include rating label in smiley/color submission value

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
git push
```

---

### Task 5: `CommentRelayView` emits `Platform.current` (RELEASE-GATED)

> **GATE:** The code change is safe to commit on this branch now, but this branch MUST NOT be merged to `develop` / released until Phase A (Task 1) is merged AND deployed to the environment the SDK targets. Emitting `macos` against an undeployed API yields 400. Record the gate in the PR description.

**Files:**
- Modify: `Sources/CommentRelayUI/Screens/CommentRelayView.swift:56,105`

- [ ] **Step 1: Replace both hardcoded `.ios` call sites**

In `Sources/CommentRelayUI/Screens/CommentRelayView.swift`, there are two occurrences of:
```swift
                    platform: .ios,
```
inside `FeedbackFormViewModel(...)` initializers (around lines 56 and 105). Replace **both** with:
```swift
                    platform: Platform.current,
```

Run to confirm exactly two replacements and none remain:
Run: `cd /Users/mikesilvers/repos/commentrelay-sdk/commentrelay-sdk-ios && grep -n "platform: \.ios" Sources/CommentRelayUI/Screens/CommentRelayView.swift ; grep -cn "platform: Platform.current" Sources/CommentRelayUI/Screens/CommentRelayView.swift`
Expected: first grep prints nothing; second prints `2`.

- [ ] **Step 2: Build to verify it compiles**

Run: `cd /Users/mikesilvers/repos/commentrelay-sdk/commentrelay-sdk-ios && swift build 2>&1 | tail -5`
Expected: build succeeds (`Platform` is already imported via `CommentRelayCore` in this file's module).

- [ ] **Step 3: Commit & push**

```bash
cd /Users/mikesilvers/repos/commentrelay-sdk/commentrelay-sdk-ios
git add Sources/CommentRelayUI/Screens/CommentRelayView.swift
git commit -m "fix(CRLBS-113): report Platform.current instead of hardcoded .ios

Release-gated on commentrelay-api CRLBS-113 deploy (macos enum).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
git push
```

---

### Task 6: Per-target Apple privacy manifests

**Files:**
- Create: `Sources/CommentRelayCore/PrivacyInfo.xcprivacy`
- Create: `Sources/CommentRelayUI/PrivacyInfo.xcprivacy`

- [ ] **Step 1: Create the Core manifest**

Create `Sources/CommentRelayCore/PrivacyInfo.xcprivacy` with exactly:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSPrivacyTracking</key>
    <false/>
    <key>NSPrivacyTrackingDomains</key>
    <array/>
    <key>NSPrivacyAccessedAPITypes</key>
    <array/>
    <key>NSPrivacyCollectedDataTypes</key>
    <array>
        <dict>
            <key>NSPrivacyCollectedDataType</key>
            <string>NSPrivacyCollectedDataTypeUserID</string>
            <key>NSPrivacyCollectedDataTypeLinked</key>
            <true/>
            <key>NSPrivacyCollectedDataTypeTracking</key>
            <false/>
            <key>NSPrivacyCollectedDataTypePurposes</key>
            <array><string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string></array>
        </dict>
        <dict>
            <key>NSPrivacyCollectedDataType</key>
            <string>NSPrivacyCollectedDataTypeOtherUserContent</string>
            <key>NSPrivacyCollectedDataTypeLinked</key>
            <true/>
            <key>NSPrivacyCollectedDataTypeTracking</key>
            <false/>
            <key>NSPrivacyCollectedDataTypePurposes</key>
            <array><string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string></array>
        </dict>
        <dict>
            <key>NSPrivacyCollectedDataType</key>
            <string>NSPrivacyCollectedDataTypeEmailAddress</string>
            <key>NSPrivacyCollectedDataTypeLinked</key>
            <true/>
            <key>NSPrivacyCollectedDataTypeTracking</key>
            <false/>
            <key>NSPrivacyCollectedDataTypePurposes</key>
            <array><string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string></array>
        </dict>
        <dict>
            <key>NSPrivacyCollectedDataType</key>
            <string>NSPrivacyCollectedDataTypePhoneNumber</string>
            <key>NSPrivacyCollectedDataTypeLinked</key>
            <true/>
            <key>NSPrivacyCollectedDataTypeTracking</key>
            <false/>
            <key>NSPrivacyCollectedDataTypePurposes</key>
            <array><string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string></array>
        </dict>
        <dict>
            <key>NSPrivacyCollectedDataType</key>
            <string>NSPrivacyCollectedDataTypeOtherDataTypes</string>
            <key>NSPrivacyCollectedDataTypeLinked</key>
            <true/>
            <key>NSPrivacyCollectedDataTypeTracking</key>
            <false/>
            <key>NSPrivacyCollectedDataTypePurposes</key>
            <array><string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string></array>
        </dict>
    </array>
</dict>
</plist>
```

- [ ] **Step 2: Create the UI manifest**

Create `Sources/CommentRelayUI/PrivacyInfo.xcprivacy` with exactly:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSPrivacyTracking</key>
    <false/>
    <key>NSPrivacyTrackingDomains</key>
    <array/>
    <key>NSPrivacyAccessedAPITypes</key>
    <array/>
    <key>NSPrivacyCollectedDataTypes</key>
    <array>
        <dict>
            <key>NSPrivacyCollectedDataType</key>
            <string>NSPrivacyCollectedDataTypeOtherUserContent</string>
            <key>NSPrivacyCollectedDataTypeLinked</key>
            <true/>
            <key>NSPrivacyCollectedDataTypeTracking</key>
            <false/>
            <key>NSPrivacyCollectedDataTypePurposes</key>
            <array><string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string></array>
        </dict>
        <dict>
            <key>NSPrivacyCollectedDataType</key>
            <string>NSPrivacyCollectedDataTypePhotosorVideos</string>
            <key>NSPrivacyCollectedDataTypeLinked</key>
            <true/>
            <key>NSPrivacyCollectedDataTypeTracking</key>
            <false/>
            <key>NSPrivacyCollectedDataTypePurposes</key>
            <array><string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string></array>
        </dict>
        <dict>
            <key>NSPrivacyCollectedDataType</key>
            <string>NSPrivacyCollectedDataTypeEmailAddress</string>
            <key>NSPrivacyCollectedDataTypeLinked</key>
            <true/>
            <key>NSPrivacyCollectedDataTypeTracking</key>
            <false/>
            <key>NSPrivacyCollectedDataTypePurposes</key>
            <array><string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string></array>
        </dict>
        <dict>
            <key>NSPrivacyCollectedDataType</key>
            <string>NSPrivacyCollectedDataTypePhoneNumber</string>
            <key>NSPrivacyCollectedDataTypeLinked</key>
            <true/>
            <key>NSPrivacyCollectedDataTypeTracking</key>
            <false/>
            <key>NSPrivacyCollectedDataTypePurposes</key>
            <array><string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string></array>
        </dict>
    </array>
</dict>
</plist>
```

- [ ] **Step 3: Lint both plists**

Run: `cd /Users/mikesilvers/repos/commentrelay-sdk/commentrelay-sdk-ios && plutil -lint Sources/CommentRelayCore/PrivacyInfo.xcprivacy Sources/CommentRelayUI/PrivacyInfo.xcprivacy`
Expected: both print `OK`.

- [ ] **Step 4: Commit & push**

```bash
cd /Users/mikesilvers/repos/commentrelay-sdk/commentrelay-sdk-ios
git add Sources/CommentRelayCore/PrivacyInfo.xcprivacy Sources/CommentRelayUI/PrivacyInfo.xcprivacy
git commit -m "feat(CRLBS-113): add per-target Apple privacy manifests

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
git push
```

---

### Task 7: Wire manifests as SPM resources

**Files:**
- Modify: `Package.swift`

- [ ] **Step 1: Add resources to both targets**

In `Package.swift`, replace this exact block:
```swift
        .target(name: "CommentRelayCore"),
        .target(
            name: "CommentRelayUI",
            dependencies: ["CommentRelayCore"],
            resources: [.process("Resources")]
        ),
```
with:
```swift
        .target(
            name: "CommentRelayCore",
            resources: [.copy("PrivacyInfo.xcprivacy")]
        ),
        .target(
            name: "CommentRelayUI",
            dependencies: ["CommentRelayCore"],
            resources: [
                .process("Resources"),
                .copy("PrivacyInfo.xcprivacy"),
            ]
        ),
```

- [ ] **Step 2: Resolve & build**

Run: `cd /Users/mikesilvers/repos/commentrelay-sdk/commentrelay-sdk-ios && swift build 2>&1 | tail -5`
Expected: build succeeds with no "unhandled resource" warnings for `PrivacyInfo.xcprivacy`.

- [ ] **Step 3: Confirm the manifests are bundled**

Run: `cd /Users/mikesilvers/repos/commentrelay-sdk/commentrelay-sdk-ios && find .build -name "PrivacyInfo.xcprivacy" | sort`
Expected: at least one bundled copy per target (paths under `.build/.../CommentRelay_CommentRelayCore.bundle` and `..._CommentRelayUI.bundle`).

- [ ] **Step 4: Commit & push**

```bash
cd /Users/mikesilvers/repos/commentrelay-sdk/commentrelay-sdk-ios
git add Package.swift
git commit -m "build(CRLBS-113): ship privacy manifests as SPM target resources

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
git push
```

---

### Task 8: README note + full-suite verification

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add a privacy/SPM section to the README**

Append to `/Users/mikesilvers/repos/commentrelay-sdk/commentrelay-sdk-ios/README.md`:
```markdown

## Privacy

Both library targets ship an Apple privacy manifest (`PrivacyInfo.xcprivacy`) as an SPM resource. The SDK does **not** track users (`NSPrivacyTracking = false`, no tracking domains) and uses no required-reason APIs. Collected data (feedback content, photos/attachments, optional contact details, an app-assigned user identifier, and diagnostic context like OS/app version and locale) is declared as linked to the user and used only for App Functionality. Xcode aggregates these manifests into your app's privacy report automatically.

Source distribution via SPM requires no binary signature; XCFramework/binary signing and notarization are not applicable to this source package.
```

- [ ] **Step 2: Full SDK suite + build (regression gate)**

Run: `cd /Users/mikesilvers/repos/commentrelay-sdk/commentrelay-sdk-ios && swift build 2>&1 | tail -3 && swift test 2>&1 | tail -8`
Expected: build succeeds; tests pass with **0 failures** and total ≥ 148 (148 prior + new `PlatformTests` + `RatingPayloadTests`).

- [ ] **Step 3: Commit & push**

```bash
cd /Users/mikesilvers/repos/commentrelay-sdk/commentrelay-sdk-ios
git add README.md
git commit -m "docs(CRLBS-113): document privacy manifest and SPM distribution

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
git push
```

---

## Sequencing & release gate

1. Phase A (Tasks 1–2) and Phase B Tasks 3, 4, 6, 7, 8 are independent and may proceed in any order.
2. Phase B Task 5 (emit `Platform.current`) may be **implemented/committed** anytime but the SDK branch must **not be merged/released** until Phase A is merged AND deployed to the SDK's target API environment. The PR description must state this gate.
3. Final state: two PRs (one per repo) via Bitbucket `bb pr`, both referencing CRLBS-113.

## Self-Review

**Spec coverage:** API enum → Task 1 ✓. API doc fix → Task 2 ✓. C3 rating label → Task 4 ✓. `Platform.macos`/`current` → Task 3 ✓. Hardcoded `.ios` sites → Task 5 ✓. Per-target manifests (Core+UI, linked/not-tracking, empty AccessedAPITypes) → Task 6 ✓. SPM resource packaging (Core `.copy`, UI `.copy` alongside `.process`) → Task 7 ✓. README + binary-signing N/A note → Task 8 ✓. Suite ≥148 green on macOS → Task 8 Step 2 ✓. Release gate → Sequencing + Task 5 gate ✓. Explicit non-defects (C1, `_minutes` value) untouched — no task modifies the receipt model or the API-emitted value ✓.

**Placeholder scan:** No TBD/TODO; every code/edit step shows exact content; the only conditional ("if other files appear" in Task 2 Step 2) is bounded by a concrete grep with a concrete replacement.

**Type consistency:** `Platform.macos`/`Platform.current` defined in Task 3, used in Task 5; wire value `"macos"` consistent with Task 1's enum string. `RatingValue` defined and used within Task 4. Manifest data-type strings consistent between Task 6 and the Package resource names in Task 7 (`PrivacyInfo.xcprivacy`).

No issues outstanding.
