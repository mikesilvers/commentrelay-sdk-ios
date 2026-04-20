// Tests/CommentRelayUITests/FieldRendererTests/PhotoFieldViewTests.swift
import XCTest
import SwiftUI
import ViewInspector
import CommentRelayCore
@testable import CommentRelayUI

final class PhotoFieldViewTests: XCTestCase {
    func test_rendersLabel_andAddButton_whenEmpty() throws {
        let sut = PhotoFieldView(field: FakeField.photo(), attachments: .constant([]))
        XCTAssertNoThrow(try sut.inspect().find(text: "Screenshot"))
        XCTAssertNoThrow(try sut.inspect().find(text: Strings.photoAdd))
    }

    func test_requiredEmpty_isUnacceptable() {
        let sut = PhotoFieldView(field: FakeField.photo(required: true), attachments: .constant([]))
        XCTAssertFalse(sut.isValueAcceptable)
    }

    func test_requiredOneAttachment_isAcceptable() {
        let att = PhotoAttachment(id: UUID(), name: "a.png", mimeType: "image/png", size: 1, data: Data([1]))
        let sut = PhotoFieldView(field: FakeField.photo(required: true), attachments: .constant([att]))
        XCTAssertTrue(sut.isValueAcceptable)
    }
}
