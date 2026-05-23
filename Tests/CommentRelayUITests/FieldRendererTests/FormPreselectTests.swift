// Tests/CommentRelayUITests/FieldRendererTests/FormPreselectTests.swift
import XCTest
@testable import CommentRelayCore
@testable import CommentRelayUI

final class FormPreselectTests: XCTestCase {
    private func form(_ id: String, _ title: String,
                      showInPicker: Bool = true, isActive: Bool = true,
                      clientFormId: String? = nil) -> CommentRelayForm {
        CommentRelayForm(
            id: id, title: title, clientFormId: clientFormId, showInPicker: showInPicker,
            responseLimitCount: nil, responseLimitType: nil, responseLimitWindowMinutes: nil,
            moreFeedbackPrompt: nil, isActive: isActive, sortOrder: 0, fields: []
        )
    }

    func test_init_returnsNil_whenBothAreNil() {
        XCTAssertNil(FormPreselect(formId: nil, formTitle: nil))
    }

    func test_init_returnsId_whenOnlyIdSet() {
        XCTAssertEqual(FormPreselect(formId: "abc", formTitle: nil), .id("abc"))
    }

    func test_init_returnsTitle_whenOnlyTitleSet() {
        XCTAssertEqual(FormPreselect(formId: nil, formTitle: "Rate us!"), .title("Rate us!"))
    }

    func test_init_idWins_whenBothSet() {
        XCTAssertEqual(FormPreselect(formId: "abc", formTitle: "Rate us!"), .id("abc"))
    }

    func test_match_byId() {
        let forms = [form("a", "Bug Report"), form("b", "Rate us!")]
        XCTAssertEqual(FormPreselect.id("b").match(in: forms)?.id, "b")
    }

    func test_match_byTitle_caseInsensitive() {
        let forms = [form("a", "Bug Report"), form("b", "Rate us!")]
        XCTAssertEqual(FormPreselect.title("rate us!").match(in: forms)?.id, "b")
        XCTAssertEqual(FormPreselect.title("RATE US!").match(in: forms)?.id, "b")
    }

    func test_match_returnsNil_whenNoMatch() {
        let forms = [form("a", "Bug Report")]
        XCTAssertNil(FormPreselect.id("zzz").match(in: forms))
        XCTAssertNil(FormPreselect.title("Nope").match(in: forms))
    }

    func test_match_returnsNil_forEmptyForms() {
        XCTAssertNil(FormPreselect.id("x").match(in: []))
        XCTAssertNil(FormPreselect.title("x").match(in: []))
    }

    func test_match_excludesForm_whenShowInPickerFalse() {
        let forms = [form("a", "Hidden", showInPicker: false)]
        XCTAssertNil(FormPreselect.id("a").match(in: forms),
                     "preselect by id must not surface a show_in_picker:false form")
        XCTAssertNil(FormPreselect.title("Hidden").match(in: forms),
                     "preselect by title must not surface a show_in_picker:false form")
    }

    func test_match_excludesForm_whenInactive() {
        let forms = [form("a", "Inactive", isActive: false)]
        XCTAssertNil(FormPreselect.id("a").match(in: forms))
        XCTAssertNil(FormPreselect.title("Inactive").match(in: forms))
    }

    func test_match_stillMatches_whenVisibleFormSharesTitleWithHiddenOne() {
        // A hidden form must not shadow a visible one with the same title.
        let forms = [
            form("hidden", "Feedback", showInPicker: false),
            form("visible", "Feedback", showInPicker: true),
        ]
        XCTAssertEqual(FormPreselect.title("feedback").match(in: forms)?.id, "visible")
    }
}
