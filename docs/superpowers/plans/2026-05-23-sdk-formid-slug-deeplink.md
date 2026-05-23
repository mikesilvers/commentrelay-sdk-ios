# formId deep-link by client_form_id slug (CRLBS-127) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `formId:` open a form by its UUID **or** its `client_form_id` slug, and deep-link that exact active form even when it is hidden from the picker — fixing the production case where `formId: "check-how-they-feel"` (a hidden, slug-only form) showed nothing.

**Architecture:** SDK-only. Decode `client_form_id` on `CommentRelayForm`; in `FormPreselect.match`, the `.id` case matches UUID-or-slug among **active** forms regardless of `show_in_picker` (deep link), while `.title` keeps the picker-visible-only rule (partial reversal of CRLBS-115, id path only). Update README + tests. The API already serves `client_form_id` and only returns active forms — no API change.

**Tech Stack:** Swift 6 / SwiftPM, XCTest.

**Spec:** `docs/superpowers/specs/2026-05-23-sdk-formid-slug-deeplink-design.md`

**Base:** `feature/CRLBS-127-formid-slug-deeplink` off `commentrelay-sdk-ios` `develop` (created; spec committed `3273269`).

**Verification:** `swift build`, `swift test` from repo root. Final acceptance: `xcodebuild test -scheme CommentRelay-Package -destination 'platform=iOS Simulator,name=iPhone 17'` (watch for the known flaky leaked-network-task teardown noise from CRLBS-124 — a clean re-run is the truth).

---

## File structure

- `Sources/CommentRelayCore/Public/Models/CommentRelayForm.swift` (modify) — add `clientFormId` property + coding key.
- `Sources/CommentRelayUI/Shared/FormPreselect.swift` (modify) — split `match` so `.id` deep-links by UUID-or-slug regardless of picker visibility; `.title` unchanged.
- `Tests/CommentRelayCoreTests/CommentRelayFormDecodingTests.swift` (new) — decode `client_form_id` present/absent.
- `Tests/CommentRelayUITests/FieldRendererTests/FormPreselectTests.swift` (modify) — fixture gains a `clientFormId` param; flip one existing assertion; add deep-link/slug cases.
- `Tests/CommentRelayCoreTests/OfflineConfigTests.swift` and `Tests/CommentRelayCoreTests/ConfigCacheTests.swift` (modify) — add `clientFormId: nil` to their `CommentRelayForm(...)` fixtures (memberwise init gains the param).
- `README.md` (modify) — correct the `formId`/`formTitle` visibility note; document slug support.

No API, web, or dependency change.

---

## Task 0: Verify base

**Files:** none (gate).

- [ ] **Step 1: Branch + clean tree**
```bash
cd /Users/mikesilvers/repos/commentrelay-sdk/commentrelay-sdk-ios
git branch --show-current   # feature/CRLBS-127-formid-slug-deeplink
git status --short          # clean (spec already committed)
git --no-pager log --oneline -1   # 3273269 docs(CRLBS-127): design …
```

- [ ] **Step 2: Build + test baseline**
```bash
swift build 2>&1 | tail -5          # clean
swift test 2>&1 | tail -15          # record pass count, 0 failures
```

---

## Task 1: Decode `client_form_id` on the form model

**Files:**
- Modify: `Sources/CommentRelayCore/Public/Models/CommentRelayForm.swift`
- Create: `Tests/CommentRelayCoreTests/CommentRelayFormDecodingTests.swift`
- Modify: `Tests/CommentRelayCoreTests/OfflineConfigTests.swift`, `Tests/CommentRelayCoreTests/ConfigCacheTests.swift`, `Tests/CommentRelayUITests/FieldRendererTests/FormPreselectTests.swift` (fixture call sites — the memberwise init gains a param)

- [ ] **Step 1: Write the failing decoding test**

Create `Tests/CommentRelayCoreTests/CommentRelayFormDecodingTests.swift`:
```swift
import XCTest
@testable import CommentRelayCore

final class CommentRelayFormDecodingTests: XCTestCase {
    func test_decodes_clientFormId_whenPresent() throws {
        let json = Data("""
        {"id":"f1","title":"Bug","client_form_id":"check-how-they-feel",
         "show_in_picker":true,"is_active":true,"sort_order":0,"fields":[]}
        """.utf8)
        let form = try JSONDecoder().decode(CommentRelayForm.self, from: json)
        XCTAssertEqual(form.clientFormId, "check-how-they-feel")
    }

    func test_clientFormId_isNil_whenAbsent() throws {
        let json = Data("""
        {"id":"f1","title":"Bug","show_in_picker":true,"is_active":true,
         "sort_order":0,"fields":[]}
        """.utf8)
        let form = try JSONDecoder().decode(CommentRelayForm.self, from: json)
        XCTAssertNil(form.clientFormId)
    }
}
```

- [ ] **Step 2: Run it — expect failure (no `clientFormId` member)**
```bash
swift test --filter CommentRelayFormDecodingTests 2>&1 | tail -15
```
Expected: compile error — `value of type 'CommentRelayForm' has no member 'clientFormId'`.

- [ ] **Step 3: Add the property + coding key**

In `Sources/CommentRelayCore/Public/Models/CommentRelayForm.swift`, add the property immediately after `public let title: String`:
```swift
    public let clientFormId: String?
```
and add its coding key in `CodingKeys`, immediately after `case id, title`:
```swift
        case clientFormId = "client_form_id"
```
`clientFormId` is optional, so synthesized `Decodable` treats a missing key as `nil` (decodeIfPresent). `isPickerVisible` is unchanged.

- [ ] **Step 4: Fix the memberwise-init call sites (compile)**

The synthesized memberwise initializer now requires `clientFormId`. Update the three fixtures:

`Tests/CommentRelayUITests/FieldRendererTests/FormPreselectTests.swift` — replace the `form(...)` helper (lines 7-14) with:
```swift
    private func form(_ id: String, _ title: String,
                      showInPicker: Bool = true, isActive: Bool = true,
                      clientFormId: String? = nil) -> CommentRelayForm {
        CommentRelayForm(
            id: id, title: title, clientFormId: clientFormId, showInPicker: showInPicker,
            responseLimitCount: nil, responseLimitType: nil, responseLimitWindowMinutes: nil,
            moreFeedbackPrompt: nil, isActive: isActive, sortOrder: 0, fields: []
        )
    }
```

`Tests/CommentRelayCoreTests/OfflineConfigTests.swift:15` — add `clientFormId: nil,` right after `title: "T",` in the `CommentRelayForm(...)` call.

`Tests/CommentRelayCoreTests/ConfigCacheTests.swift:20` — add `clientFormId: nil,` right after `title: "Bug",` in the `CommentRelayForm(...)` call.

- [ ] **Step 5: Run tests — expect pass**
```bash
swift test --filter CommentRelayFormDecodingTests 2>&1 | tail -8   # 2 passed
swift build 2>&1 | tail -3                                         # clean
```
Expected: both decoding tests pass; package + tests compile.

- [ ] **Step 6: Commit**
```bash
git add Sources/CommentRelayCore/Public/Models/CommentRelayForm.swift \
        Tests/CommentRelayCoreTests/CommentRelayFormDecodingTests.swift \
        Tests/CommentRelayCoreTests/OfflineConfigTests.swift \
        Tests/CommentRelayCoreTests/ConfigCacheTests.swift \
        Tests/CommentRelayUITests/FieldRendererTests/FormPreselectTests.swift
git commit -m "feat(CRLBS-127): decode client_form_id on CommentRelayForm

Add optional clientFormId (client_form_id) so the SDK can match a form by its
stable slug, not just the UUID. Fixtures updated for the memberwise init.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Deep-link match by id-or-slug, bypassing picker visibility (id path only)

**Files:**
- Modify: `Sources/CommentRelayUI/Shared/FormPreselect.swift`
- Modify: `Tests/CommentRelayUITests/FieldRendererTests/FormPreselectTests.swift`

- [ ] **Step 1: Update the existing test that asserts the OLD behavior, and add new cases**

In `Tests/CommentRelayUITests/FieldRendererTests/FormPreselectTests.swift`, replace `test_match_excludesForm_whenShowInPickerFalse` (currently asserts `.id` returns nil for a hidden form) with the new expectation, and append the new cases:
```swift
    func test_match_excludesForm_whenShowInPickerFalse() {
        let forms = [form("a", "Hidden", showInPicker: false)]
        // CRLBS-127: an explicit id is now a deep link — it opens a hidden but
        // active form. Title preselect still must not.
        XCTAssertEqual(FormPreselect.id("a").match(in: forms)?.id, "a",
                       "preselect by id deep-links a show_in_picker:false form")
        XCTAssertNil(FormPreselect.title("Hidden").match(in: forms),
                     "preselect by title must not surface a show_in_picker:false form")
    }

    func test_match_byId_matchesClientFormIdSlug() {
        let forms = [form("uuid-1", "Bug Report", clientFormId: "bug-report")]
        XCTAssertEqual(FormPreselect.id("bug-report").match(in: forms)?.id, "uuid-1")
    }

    func test_match_byId_opensHiddenForm_viaSlug() {
        let forms = [form("uuid-1", "Hidden", showInPicker: false, clientFormId: "secret-form")]
        XCTAssertEqual(FormPreselect.id("secret-form").match(in: forms)?.id, "uuid-1",
                       "an explicit slug must deep-link a show_in_picker:false form")
    }

    func test_match_byId_opensHiddenForm_viaUUID() {
        let forms = [form("uuid-1", "Hidden", showInPicker: false)]
        XCTAssertEqual(FormPreselect.id("uuid-1").match(in: forms)?.id, "uuid-1")
    }

    func test_match_byId_doesNotOpenInactiveForm() {
        let forms = [form("uuid-1", "Inactive", isActive: false, clientFormId: "x")]
        XCTAssertNil(FormPreselect.id("uuid-1").match(in: forms))
        XCTAssertNil(FormPreselect.id("x").match(in: forms))
    }
```

- [ ] **Step 2: Run — expect failure (slug not decoded for matching / old behavior)**
```bash
swift test --filter FormPreselectTests 2>&1 | tail -20
```
Expected: the new slug/deep-link cases fail and the updated `test_match_excludesForm_whenShowInPickerFalse` fails (current code still returns nil for `.id` on a hidden form).

- [ ] **Step 3: Rewrite the matcher**

Replace the body of `FormPreselect.match` and its doc comment in `Sources/CommentRelayUI/Shared/FormPreselect.swift` (lines 20-34) with:
```swift
    /// Resolves the preselected form.
    ///
    /// `.id` is a deep link: it matches the form's UUID **or** its
    /// `client_form_id` slug, and opens that form even when it is hidden from
    /// the picker (`show_in_picker:false`). An inactive form is never surfaced.
    /// `.title` stays picker-visible-only — a fuzzy title must not surface a
    /// hidden form. (Partial reversal of CRLBS-115 for the id path only.)
    func match(in forms: [CommentRelayForm]) -> CommentRelayForm? {
        switch self {
        case .id(let id):
            return forms.first { $0.isActive && ($0.id == id || $0.clientFormId == id) }
        case .title(let title):
            let needle = title.lowercased()
            return forms.filter { $0.isPickerVisible }.first { $0.title.lowercased() == needle }
        }
    }
```

- [ ] **Step 4: Run — expect pass**
```bash
swift test --filter FormPreselectTests 2>&1 | tail -12
```
Expected: all `FormPreselectTests` pass (including the preserved title/inactive cases).

- [ ] **Step 5: Commit**
```bash
git add Sources/CommentRelayUI/Shared/FormPreselect.swift \
        Tests/CommentRelayUITests/FieldRendererTests/FormPreselectTests.swift
git commit -m "fix(CRLBS-127): formId deep-links by UUID or client_form_id slug

An explicit formId now matches the form's UUID or its client_form_id slug and
opens it even when hidden from the picker. Inactive forms still never surface;
formTitle keeps the picker-visible rule. Partial reversal of CRLBS-115 (id path).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: README — document slug + deep-link behavior

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update the preselect copy**

In `README.md`, replace line 103:
```
Jump straight to one form (skips the picker) with `formId:` or `formTitle:`:
```
with:
```
Jump straight to one form (skips the picker) with `formId:` or `formTitle:`.
`formId:` accepts the form's UUID **or** its `client_form_id` slug:
```

Then replace lines 111-112:
```
A form that is inactive or not marked “show in picker” is never surfaced —
including via `formId`/`formTitle` preselect.
```
with:
```
An **inactive** form is never surfaced. `formId:` (UUID or `client_form_id`
slug) opens that exact form even if it is hidden from the picker — a deep link.
`formTitle:` only matches a form that is shown in the picker.
```

- [ ] **Step 2: Commit**
```bash
git add README.md
git commit -m "docs(CRLBS-127): document formId slug + hidden-form deep link

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Verify + push + PR

**Files:** none.

- [ ] **Step 1: Full checks**
```bash
swift build 2>&1 | tail -3                       # clean
swift test 2>&1 | tail -15                        # baseline + new tests, 0 failures
git status --porcelain                            # clean
```

- [ ] **Step 2: iOS acceptance (final)**
```bash
xcodebuild test -scheme CommentRelay-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **`. If a leaked-network-task teardown failure appears (known flaky from CRLBS-124), re-run once; a clean run is the truth. Do NOT accept a false failure, and do NOT mask a real one.

- [ ] **Step 3: Push + open PR**
```bash
git push -u origin feature/CRLBS-127-formid-slug-deeplink 2>&1 | tail -2
bb pr create -s feature/CRLBS-127-formid-slug-deeplink -d develop \
  -t "fix(CRLBS-127): formId deep-link by client_form_id slug, opens hidden forms" \
  -b "$(cat <<'PR_BODY_EOF'
Implements docs/superpowers/specs/2026-05-23-sdk-formid-slug-deeplink-design.md.

## Problem
Production: presenting feedback with formId set to a client_form_id slug
("check-how-they-feel") for a project showed nothing. The form is hidden from
the picker. Two SDK defects combined: (1) the model never decoded
client_form_id and FormPreselect compared formId only to the UUID, so a slug
could never match; (2) CRLBS-115 excluded hidden-from-picker forms from
preselect entirely. The API is healthy (serves the slug, returns 200).

## Fix (SDK-only)
- CommentRelayForm decodes client_form_id (optional).
- FormPreselect.match: an explicit formId matches the UUID OR the slug and opens
  that exact active form even when hidden from the picker (deep link). Inactive
  forms still never surface. formTitle keeps the picker-visible rule. Partial,
  intentional reversal of CRLBS-115 for the id path only.
- README updated; tests added (slug match, hidden-form deep link via slug+UUID,
  inactive excluded, title still blocked for hidden, model decoding).

## Tests
swift test green; xcodebuild iOS acceptance green. No API/web change.

JIRA: https://commentrelay.atlassian.net/browse/CRLBS-127

Generated with Claude Code
PR_BODY_EOF
)" 2>&1 | tail -4
```
Paste the PR number + URL.

---

## Self-review

**1. Spec coverage:**
- Decode `client_form_id` — Task 1.
- `formId` matches UUID or slug — Task 2 (matcher) + tests.
- Deep-link opens hidden-but-active form (id path) — Task 2.
- Inactive never surfaces; `formTitle` unchanged; picker list unchanged — Task 2 matcher (`isActive` guard; `.title` keeps `isPickerVisible`; `FormPickerView` untouched).
- README corrected — Task 3.
- Tests for all — Tasks 1-2.

**2. Placeholder scan:** None. Every code step has full code; commands have expected output.

**3. Type consistency:** `clientFormId: String?` defined in Task 1 is used by the matcher (`$0.clientFormId == id`) in Task 2 and the fixture `clientFormId:` param. The memberwise-init param order (`id, title, clientFormId, showInPicker, …`) matches the property declaration order set in Task 1; all three fixture call sites pass it by label. The flipped assertion in `test_match_excludesForm_whenShowInPickerFalse` is called out explicitly so it isn't mistaken for a regression.
