// Tests/CommentRelayUITests/FieldRendererTests/FormPreselectTests.swift
import XCTest
@testable import CommentRelayCore
@testable import CommentRelayUI

final class FormPreselectTests: XCTestCase {
    private func form(_ id: String, _ title: String) -> CommentRelayForm {
        CommentRelayForm(
            id: id, title: title, showInPicker: true,
            responseLimitCount: nil, responseLimitType: nil, responseLimitWindowMinutes: nil,
            moreFeedbackPrompt: nil, isActive: true, sortOrder: 0, fields: []
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
}
