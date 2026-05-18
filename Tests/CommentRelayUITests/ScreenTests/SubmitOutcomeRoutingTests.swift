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

    func testQueuedAttachmentsCoversAllFieldsAndPhotos() throws {
        let raw = #"""
        {"id":"f","title":"Feedback","show_in_picker":true,"response_limit_count":null,"response_limit_type":null,"response_limit_window_minutes":null,"more_feedback_prompt":null,"is_active":true,"sort_order":1,"fields":[
          {"id":"file-1","field_type":"photo","label":"Screenshot","is_required":false,"is_gate":false,"sort_order":1,"max_files":3},
          {"id":"file-2","field_type":"photo","label":"Video","is_required":false,"is_gate":false,"sort_order":2,"max_files":3}
        ]}
        """#
        let form = try! JSONDecoder().decode(CommentRelayForm.self, from: Data(raw.utf8))
        let vm = FeedbackFormViewModel(form: form, userIdentifier: "u", platform: .ios, sdkVersion: "0.1.0")

        vm.setPhotos("file-1", [
            PhotoAttachment(name: "a.png", mimeType: "image/png", size: 2, data: Data([1, 2])),
            PhotoAttachment(name: "b.png", mimeType: "image/png", size: 3, data: Data([3, 4]))
        ])
        vm.setPhotos("file-2", [
            PhotoAttachment(name: "c.jpg", mimeType: "image/jpeg", size: 4, data: Data([5, 6]))
        ])

        let q = vm.queuedAttachments()

        // Count must be 3 — guards against a first-instead-of-flatMap regression
        XCTAssertEqual(q.count, 3)

        // Order-independent identity check
        let keys = Set(q.map { "\($0.fieldId)/\($0.fileName)" })
        XCTAssertEqual(keys, ["file-1/a.png", "file-1/b.png", "file-2/c.jpg"])

        // Per-attachment content/type correctness
        let byKey = Dictionary(uniqueKeysWithValues: q.map { ("\($0.fieldId)/\($0.fileName)", $0) })
        XCTAssertEqual(byKey["file-1/a.png"]?.contentType, "image/png")
        XCTAssertEqual(byKey["file-1/a.png"]?.data, Data([1, 2]))
        XCTAssertEqual(byKey["file-1/b.png"]?.contentType, "image/png")
        XCTAssertEqual(byKey["file-1/b.png"]?.data, Data([3, 4]))
        XCTAssertEqual(byKey["file-2/c.jpg"]?.contentType, "image/jpeg")
        XCTAssertEqual(byKey["file-2/c.jpg"]?.data, Data([5, 6]))
    }
}
