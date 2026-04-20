import XCTest
import SwiftUI
import ViewInspector
import CommentRelayCore
@testable import CommentRelayUI

final class EmailFieldViewTests: XCTestCase {
    func test_rendersLabel() throws {
        let field = FakeField.email(label: "Email")
        let sut = EmailFieldView(field: field, value: .constant(""))
        XCTAssertNoThrow(try sut.inspect().find(text: "Email"))
    }

    func test_rendersRequiredIndicator_whenFieldIsRequired() throws {
        let field = FakeField.email(required: true)
        let sut = EmailFieldView(field: field, value: .constant(""))
        XCTAssertNoThrow(try sut.inspect().find(text: "*"))
    }

    func test_isValueAcceptable_respectsRequired_andFormat() {
        let required = FakeField.email(required: true)
        let optional = FakeField.email(required: false)
        XCTAssertFalse(EmailFieldView(field: required, value: .constant("")).isValueAcceptable)
        XCTAssertTrue(EmailFieldView(field: required, value: .constant("a@b.c")).isValueAcceptable)
        XCTAssertTrue(EmailFieldView(field: optional, value: .constant("")).isValueAcceptable)
        XCTAssertFalse(EmailFieldView(field: required, value: .constant("notanemail")).isValueAcceptable)
    }
}
