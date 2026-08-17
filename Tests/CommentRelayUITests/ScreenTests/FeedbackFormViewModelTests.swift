// Tests/CommentRelayUITests/ScreenTests/FeedbackFormViewModelTests.swift
import XCTest
import CommentRelayCore
@testable import CommentRelayUI

final class FeedbackFormViewModelTests: XCTestCase {
    func test_isSubmittable_falseUntilRequiredTextbox_isFilled() {
        let raw = #"""
        {"id":"c","title":"Bug","show_in_picker":true,"response_limit_count":null,"response_limit_type":null,"response_limit_window_minutes":null,"more_feedback_prompt":null,"is_active":true,"sort_order":1,"fields":[
          {"id":"f1","field_type":"textbox","label":"Describe","is_required":true,"is_gate":false,"sort_order":1,"max_files":null}
        ]}
        """#
        let form = try! JSONDecoder().decode(CommentRelayForm.self, from: Data(raw.utf8))
        let vm = FeedbackFormViewModel(form: form, userIdentifier: "u", platform: .ios, sdkVersion: "0.1.0")
        XCTAssertFalse(vm.isSubmittable)
        vm.setText("f1", "a bug")
        XCTAssertTrue(vm.isSubmittable)
    }

    func test_buildSubmission_reflectsFieldValues_andContactPreference() {
        let raw = #"""
        {"id":"c","title":"Bug","show_in_picker":true,"response_limit_count":null,"response_limit_type":null,"response_limit_window_minutes":null,"more_feedback_prompt":null,"is_active":true,"sort_order":1,"fields":[
          {"id":"f1","field_type":"textbox","label":"Describe","is_required":true,"is_gate":false,"sort_order":1,"max_files":null}
        ]}
        """#
        let form = try! JSONDecoder().decode(CommentRelayForm.self, from: Data(raw.utf8))
        let vm = FeedbackFormViewModel(form: form, userIdentifier: "u", platform: .ios, sdkVersion: "0.1.0")
        vm.setText("f1", "oops")
        vm.contactPreference = .email
        vm.contactDetails = "a@b.c"

        let submission = vm.buildSubmission()
        XCTAssertEqual(submission.formId, "c")
        XCTAssertEqual(submission.contactPreference, .email)
        XCTAssertEqual(submission.contactDetails, "a@b.c")
        guard case .text(_, let v) = submission.fields.first else { return XCTFail() }
        XCTAssertEqual(v, "oops")
    }

    // MARK: - Conditional fields (children of a true/false gate)

    /// The exact shape a real dashboard produces: a required root textbox, a true/false toggle, and a
    /// REQUIRED child textbox parented to that toggle. `visibleFields` hides the child while the toggle
    /// is off, so the user cannot see it — let alone fill it.
    private func gatedForm() -> CommentRelayForm {
        let raw = #"""
        {"id":"c","title":"Bug Report","show_in_picker":true,"response_limit_count":null,"response_limit_type":null,"response_limit_window_minutes":null,"more_feedback_prompt":null,"is_active":true,"sort_order":1,"fields":[
          {"id":"desc","field_type":"textbox","label":"Describe the bug","is_required":true,"is_gate":false,"sort_order":0,"max_files":null},
          {"id":"gate","field_type":"true_false","label":"Do you want us to contact you","is_required":true,"is_gate":false,"sort_order":1,"max_files":null},
          {"id":"name","field_type":"textbox","label":"Your name","is_required":true,"is_gate":false,"sort_order":2,"max_files":null,"parent_field_id":"gate"},
          {"id":"mail","field_type":"email","label":"Email","is_required":false,"is_gate":false,"sort_order":3,"max_files":null,"parent_field_id":"gate"}
        ]}
        """#
        return try! JSONDecoder().decode(CommentRelayForm.self, from: Data(raw.utf8))
    }

    private func makeVM(_ form: CommentRelayForm) -> FeedbackFormViewModel {
        FeedbackFormViewModel(form: form, userIdentifier: "u", platform: .ios, sdkVersion: "0.1.0")
    }

    private func submittedFieldIds(_ vm: FeedbackFormViewModel) -> [String] {
        vm.buildSubmission().fields.map {
            switch $0 {
            case .text(let id, _): return id
            case .files(let id, _): return id
            }
        }
    }

    /// A required field that is HIDDEN must not gate submission.
    ///
    /// Previously `isSubmittable` iterated `form.fields` while only `visibleFields` drove rendering, so a
    /// required child under an off toggle left the form permanently unsubmittable with no visible field to
    /// fill. Both CrimeCode feedback forms shipped in exactly this state and could never be submitted.
    func test_isSubmittable_ignoresRequiredFieldsHiddenByGate() {
        let vm = makeVM(gatedForm())
        XCTAssertFalse(vm.isSubmittable, "the visible required textbox is still empty")
        vm.setText("desc", "it crashed")
        XCTAssertTrue(vm.isSubmittable,
                      "'Your name' is required but hidden (gate off) — it must not block submission")
    }

    /// The mirror image: once the gate is on the child is visible, so its requirement applies again.
    func test_isSubmittable_enforcesRequiredChild_onceGateIsOn() {
        let vm = makeVM(gatedForm())
        vm.setText("desc", "it crashed")
        vm.setBool("gate", true)
        XCTAssertFalse(vm.isSubmittable, "'Your name' is now visible and required, and is empty")
        vm.setText("name", "Mike")
        XCTAssertTrue(vm.isSubmittable)
    }

    /// Guards against a vacuous fix (e.g. `isSubmittable` short-circuiting to `true`): a required field at
    /// the root is always visible, so it must still block.
    func test_isSubmittable_stillBlocksOnVisibleRequiredField() {
        let vm = makeVM(gatedForm())
        vm.setBool("gate", true)
        vm.setText("name", "Mike")
        XCTAssertFalse(vm.isSubmittable, "the root 'Describe the bug' is required, visible, and empty")
    }

    /// Toggling the gate off must WITHDRAW the values it was hiding, not merely hide them.
    ///
    /// Otherwise a user who fills in their name, then changes their mind and switches "contact me" back
    /// off, still transmits the name they just retracted.
    func test_buildSubmission_omitsValuesOfFieldsHiddenByGate() {
        let vm = makeVM(gatedForm())
        vm.setText("desc", "it crashed")
        vm.setBool("gate", true)
        vm.setText("name", "Mike")
        vm.setText("mail", "mike@example.com")

        // The user changes their mind.
        vm.setBool("gate", false)

        let ids = submittedFieldIds(vm)
        XCTAssertTrue(ids.contains("desc"), "the visible answer is still submitted")
        XCTAssertFalse(ids.contains("name"), "a withdrawn name must not be transmitted")
        XCTAssertFalse(ids.contains("mail"), "a withdrawn email must not be transmitted")
    }

    /// …but values that ARE visible still go, so the omission above isn't over-broad.
    func test_buildSubmission_includesChildValues_whileGateIsOn() {
        let vm = makeVM(gatedForm())
        vm.setText("desc", "it crashed")
        vm.setBool("gate", true)
        vm.setText("name", "Mike")

        let ids = submittedFieldIds(vm)
        XCTAssertTrue(ids.contains("name"), "a name the user chose to give must be transmitted")
    }
}
