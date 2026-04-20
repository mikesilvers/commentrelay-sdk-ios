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
