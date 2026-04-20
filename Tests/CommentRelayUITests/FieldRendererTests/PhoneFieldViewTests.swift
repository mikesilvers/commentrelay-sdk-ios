import XCTest
import SwiftUI
import ViewInspector
import CommentRelayCore
@testable import CommentRelayUI

final class PhoneFieldViewTests: XCTestCase {
    func test_rendersLabel() throws {
        let field = FakeField.phone(label: "Phone")
        let sut = PhoneFieldView(field: field, value: .constant(""))
        XCTAssertNoThrow(try sut.inspect().find(text: "Phone"))
    }

    func test_rendersRequiredIndicator_whenFieldIsRequired() throws {
        let field = FakeField.phone(required: true)
        let sut = PhoneFieldView(field: field, value: .constant(""))
        XCTAssertNoThrow(try sut.inspect().find(text: "*"))
    }

    func test_isValueAcceptable_respectsRequired_andDigits() {
        let required = FakeField.phone(required: true)
        let optional = FakeField.phone(required: false)
        XCTAssertFalse(PhoneFieldView(field: required, value: .constant("")).isValueAcceptable)
        XCTAssertTrue(PhoneFieldView(field: required, value: .constant("1234567")).isValueAcceptable)
        XCTAssertFalse(PhoneFieldView(field: required, value: .constant("123")).isValueAcceptable)
        XCTAssertTrue(PhoneFieldView(field: optional, value: .constant("")).isValueAcceptable)
    }
}
