// Tests/CommentRelayUITests/ScreenTests/DraftSeedTests.swift
// 1.2.4: a saved draft's non-empty text values prefill the form view model on open
// (host-app context written via saveDraft is loaded into the form).
import XCTest
import CommentRelayCore
@testable import CommentRelayUI

@MainActor
final class DraftSeedTests: XCTestCase {
    private func makeVM() -> FeedbackFormViewModel {
        let raw = #"""
        {"id":"c","title":"Bug","show_in_picker":true,"response_limit_count":null,"response_limit_type":null,"response_limit_window_minutes":null,"more_feedback_prompt":null,"is_active":true,"sort_order":1,"fields":[
          {"id":"query","field_type":"textbox","label":"Query","is_required":false,"is_gate":false,"sort_order":1,"max_files":null},
          {"id":"context","field_type":"textbox","label":"Context","is_required":false,"is_gate":false,"sort_order":2,"max_files":null}
        ]}
        """#
        let form = try! JSONDecoder().decode(CommentRelayForm.self, from: Data(raw.utf8))
        return FeedbackFormViewModel(form: form, userIdentifier: "u", platform: .ios, sdkVersion: "0.1.0")
    }

    func test_seed_appliesNonEmptyDraftValuesByFieldId() {
        let vm = makeVM()
        let draft = CommentRelayDraft(
            formId: "crimelookup-bug",
            fieldValues: ["query": "kicked a dog", "context": "App: Crime Code 1.0 (build 42)"],
            updatedAt: Date(timeIntervalSince1970: 0))
        CommentRelayView.seed(vm, from: draft)
        XCTAssertEqual(vm.textValues["query"], "kicked a dog")
        XCTAssertEqual(vm.textValues["context"], "App: Crime Code 1.0 (build 42)")
    }

    func test_seed_nilDraftIsNoOp() {
        let vm = makeVM()
        vm.setText("query", "typed")
        CommentRelayView.seed(vm, from: nil)
        XCTAssertEqual(vm.textValues["query"], "typed")   // unchanged
    }

    func test_seed_nonEmptyValueOverwritesExisting_lastWriteWins() {
        let vm = makeVM()
        vm.setText("query", "old")
        let draft = CommentRelayDraft(
            formId: "x", fieldValues: ["query": "new"], updatedAt: Date(timeIntervalSince1970: 0))
        CommentRelayView.seed(vm, from: draft)
        XCTAssertEqual(vm.textValues["query"], "new")   // non-empty draft value wins
    }

    func test_seed_skipsEmptyValuesSoTheyDoNotClobber() {
        let vm = makeVM()
        vm.setText("context", "keep me")
        let draft = CommentRelayDraft(
            formId: "x", fieldValues: ["query": "new", "context": ""], updatedAt: Date(timeIntervalSince1970: 0))
        CommentRelayView.seed(vm, from: draft)
        XCTAssertEqual(vm.textValues["query"], "new")
        XCTAssertEqual(vm.textValues["context"], "keep me")   // empty draft value must not overwrite
    }
}
