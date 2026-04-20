// Tests/CommentRelayUITests/FieldRendererTests/AttachmentFieldViewTests.swift
import XCTest
import SwiftUI
import ViewInspector
import CommentRelayCore
@testable import CommentRelayUI

final class AttachmentFieldViewTests: XCTestCase {
    func test_rendersAddButton_whenEmpty() throws {
        let sut = AttachmentFieldView(field: FakeField.attachment(), attachments: .constant([]))
        XCTAssertNoThrow(try sut.inspect().find(text: Strings.attachmentAdd))
    }

    func test_acceptability_matchesRequiredFlag() {
        let empty = AttachmentFieldView(field: FakeField.attachment(required: true), attachments: .constant([]))
        XCTAssertFalse(empty.isValueAcceptable)
        let att = PhotoAttachment(name: "doc.pdf", mimeType: "application/pdf", size: 10, data: Data([0]))
        let filled = AttachmentFieldView(field: FakeField.attachment(required: true), attachments: .constant([att]))
        XCTAssertTrue(filled.isValueAcceptable)
    }
}
