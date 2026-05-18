// Tests/CommentRelayUITests/ScreenTests/SubmitOutcomeRoutingTests.swift
import XCTest
import CommentRelayCore
@testable import CommentRelayUI

final class SubmitOutcomeRoutingTests: XCTestCase {
    func testQueuedAttachmentsMirrorStagedPhotos() throws {
        let raw = #"""
        {"id":"f","title":"Feedback","show_in_picker":true,"response_limit_count":null,"response_limit_type":null,"response_limit_window_minutes":null,"more_feedback_prompt":null,"is_active":true,"sort_order":1,"fields":[
          {"id":"file-1","field_type":"photo","label":"Screenshot","is_required":false,"is_gate":false,"sort_order":1,"max_files":3}
        ]}
        """#
        let form = try! JSONDecoder().decode(CommentRelayForm.self, from: Data(raw.utf8))
        let vm = FeedbackFormViewModel(form: form, userIdentifier: "u", platform: .ios, sdkVersion: "0.1.0")
        vm.setPhotos("file-1", [PhotoAttachment(name: "a.png", mimeType: "image/png", size: 2, data: Data([9, 9]))])

        let q = vm.queuedAttachments()
        XCTAssertEqual(q.count, 1)
        XCTAssertEqual(q.first?.fieldId, "file-1")
        XCTAssertEqual(q.first?.fileName, "a.png")
        XCTAssertEqual(q.first?.contentType, "image/png")
        XCTAssertEqual(q.first?.data, Data([9, 9]))
    }
}
