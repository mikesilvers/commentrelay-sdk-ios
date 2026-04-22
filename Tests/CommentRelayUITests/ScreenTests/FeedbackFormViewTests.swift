// Tests/CommentRelayUITests/ScreenTests/FeedbackFormViewTests.swift
import XCTest
import SwiftUI
import ViewInspector
import CommentRelayCore
@testable import CommentRelayUI

@MainActor
final class FeedbackFormViewTests: XCTestCase {
    private func form(with fields: [CommentRelayField]) -> CommentRelayForm {
        let encoded = try! JSONEncoder().encode(fields)
        let fieldsJSON = String(data: encoded, encoding: .utf8)!
        let raw = #"{"id":"c","title":"Bug","show_in_picker":true,"response_limit_count":null,"response_limit_type":null,"response_limit_window_minutes":null,"more_feedback_prompt":null,"is_active":true,"sort_order":1,"fields":\#(fieldsJSON)}"#
        return try! JSONDecoder().decode(CommentRelayForm.self, from: Data(raw.utf8))
    }

    func test_rendersOneRowPerField_excludingInformationalFromValidation() throws {
        let f = form(with: [FakeField.textbox(), FakeField.informational()])
        let vm = FeedbackFormViewModel(form: f, userIdentifier: "u", platform: .ios, sdkVersion: "0.1.0")
        let sut = FeedbackFormView(viewModel: vm, onSubmit: { _ in })
        XCTAssertNoThrow(try sut.inspect().find(text: "Describe the issue"))
        XCTAssertNoThrow(try sut.inspect().find(text: "This is informational copy."))
    }

    func test_childField_hiddenByDefault_whenParentTrueFalseIsOff() throws {
        let parent = FakeField.trueFalse(id: "p", label: "Do you want to be contacted?", sortOrder: 0)
        let child = FakeField.email(id: "c", label: "Email Address", required: false, sortOrder: 1, parentId: "p")
        let f = form(with: [parent, child])
        let vm = FeedbackFormViewModel(form: f, userIdentifier: "u", platform: .ios, sdkVersion: "0.1.0")
        let sut = FeedbackFormView(viewModel: vm, onSubmit: { _ in })
        XCTAssertNoThrow(try sut.inspect().find(text: "Do you want to be contacted?"))
        XCTAssertThrowsError(try sut.inspect().find(text: "Email Address"))
    }

    func test_childField_visible_whenParentToggledOn() throws {
        let parent = FakeField.trueFalse(id: "p", label: "Do you want to be contacted?", sortOrder: 0)
        let child = FakeField.email(id: "c", label: "Email Address", required: false, sortOrder: 1, parentId: "p")
        let f = form(with: [parent, child])
        let vm = FeedbackFormViewModel(form: f, userIdentifier: "u", platform: .ios, sdkVersion: "0.1.0")
        vm.setBool("p", true)
        let sut = FeedbackFormView(viewModel: vm, onSubmit: { _ in })
        XCTAssertNoThrow(try sut.inspect().find(text: "Email Address"))
    }

    func test_childField_hiddenAgain_whenParentToggledBackOff() throws {
        let parent = FakeField.trueFalse(id: "p", label: "Contact?", sortOrder: 0)
        let child = FakeField.email(id: "c", label: "Your email", required: false, sortOrder: 1, parentId: "p")
        let f = form(with: [parent, child])
        let vm = FeedbackFormViewModel(form: f, userIdentifier: "u", platform: .ios, sdkVersion: "0.1.0")
        vm.setBool("p", true)
        vm.setBool("p", false)
        let sut = FeedbackFormView(viewModel: vm, onSubmit: { _ in })
        XCTAssertThrowsError(try sut.inspect().find(text: "Your email"))
    }

    func test_childField_hidden_whenParentIsNotTrueFalse() throws {
        // A textbox parent should never gate children — only true_false does.
        let parent = FakeField.textbox(id: "p", label: "Describe", sortOrder: 0)
        let child = FakeField.email(id: "c", label: "Follow-up email", required: false, sortOrder: 1, parentId: "p")
        let f = form(with: [parent, child])
        let vm = FeedbackFormViewModel(form: f, userIdentifier: "u", platform: .ios, sdkVersion: "0.1.0")
        let sut = FeedbackFormView(viewModel: vm, onSubmit: { _ in })
        XCTAssertThrowsError(try sut.inspect().find(text: "Follow-up email"))
    }

    func test_doesNotRenderHardcodedContactPreferenceSection() throws {
        let f = form(with: [FakeField.textbox()])
        let vm = FeedbackFormViewModel(form: f, userIdentifier: "u", platform: .ios, sdkVersion: "0.1.0")
        let sut = FeedbackFormView(viewModel: vm, onSubmit: { _ in })
        XCTAssertThrowsError(try sut.inspect().find(text: Strings.contactHeader))
        XCTAssertThrowsError(try sut.inspect().find(text: Strings.contactNone))
    }

    func test_submitDisabled_untilRequiredFieldFilled() throws {
        let f = form(with: [FakeField.textbox(required: true)])
        let vm = FeedbackFormViewModel(form: f, userIdentifier: "u", platform: .ios, sdkVersion: "0.1.0")
        let sut = FeedbackFormView(viewModel: vm, onSubmit: { _ in })
        let submit = try sut.inspect().find(button: Strings.formSubmit)
        XCTAssertTrue(submit.isDisabled())
        vm.setText("f1", "a bug")
        let submit2 = try sut.inspect().find(button: Strings.formSubmit)
        XCTAssertFalse(submit2.isDisabled())
    }
}
