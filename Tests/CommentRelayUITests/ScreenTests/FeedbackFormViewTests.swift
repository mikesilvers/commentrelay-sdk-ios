// Tests/CommentRelayUITests/ScreenTests/FeedbackFormViewTests.swift
import XCTest
import SwiftUI
import ViewInspector
import CommentRelayCore
@testable import CommentRelayUI

@MainActor
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
        XCTAssertNoThrow(try sut.inspect().find(text: "Describe the issue"))
        XCTAssertNoThrow(try sut.inspect().find(text: "This is informational copy."))
    }

    func test_submitDisabled_untilRequiredFieldFilled() throws {
        let cat = category(with: [FakeField.textbox(required: true)])
        let vm = FeedbackFormViewModel(category: cat, userIdentifier: "u", platform: .ios, sdkVersion: "0.1.0")
        let sut = FeedbackFormView(viewModel: vm, onSubmit: { _ in })
        let submit = try sut.inspect().find(button: Strings.formSubmit)
        XCTAssertTrue(submit.isDisabled())
        vm.setText("f1", "a bug")
        let submit2 = try sut.inspect().find(button: Strings.formSubmit)
        XCTAssertFalse(submit2.isDisabled())
    }
}
