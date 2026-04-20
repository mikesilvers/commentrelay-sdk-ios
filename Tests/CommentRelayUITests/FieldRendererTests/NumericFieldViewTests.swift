import XCTest
import SwiftUI
import ViewInspector
import CommentRelayCore
@testable import CommentRelayUI

final class NumericFieldViewTests: XCTestCase {
    func test_rendersLabel() throws {
        let field = FakeField.numeric(label: "Rating")
        let sut = NumericFieldView(field: field, value: .constant(""))
        XCTAssertNoThrow(try sut.inspect().find(text: "Rating"))
    }

    func test_rendersRequiredIndicator_whenFieldIsRequired() throws {
        let field = FakeField.numeric(required: true)
        let sut = NumericFieldView(field: field, value: .constant(""))
        XCTAssertNoThrow(try sut.inspect().find(text: "*"))
    }

    func test_isValueAcceptable_respectsRequired_andParses() {
        let required = FakeField.numeric(required: true)
        let optional = FakeField.numeric(required: false)
        XCTAssertFalse(NumericFieldView(field: required, value: .constant("")).isValueAcceptable)
        XCTAssertTrue(NumericFieldView(field: required, value: .constant("3.14")).isValueAcceptable)
        XCTAssertFalse(NumericFieldView(field: required, value: .constant("abc")).isValueAcceptable)
        XCTAssertTrue(NumericFieldView(field: optional, value: .constant("")).isValueAcceptable)
    }
}
