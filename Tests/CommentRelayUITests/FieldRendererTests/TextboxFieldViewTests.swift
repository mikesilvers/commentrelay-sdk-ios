import XCTest
import SwiftUI
import ViewInspector
import CommentRelayCore
@testable import CommentRelayUI

final class TextboxFieldViewTests: XCTestCase {
    func test_rendersLabel() throws {
        var value = ""
        let field = FakeField.textbox(label: "Describe")
        let sut = TextboxFieldView(field: field, value: Binding(get: { value }, set: { value = $0 }))
        XCTAssertNoThrow(try sut.inspect().find(text: "Describe"))
    }

    func test_rendersRequiredIndicator_whenFieldIsRequired() throws {
        var value = ""
        let field = FakeField.textbox(required: true)
        let sut = TextboxFieldView(field: field, value: Binding(get: { value }, set: { value = $0 }))
        XCTAssertNoThrow(try sut.inspect().find(text: "*"))
    }

    func test_isValueAcceptable_respectsRequired() {
        let requiredField = FakeField.textbox(required: true)
        let optionalField = FakeField.textbox(required: false)
        let emptyRequired = TextboxFieldView(field: requiredField, value: .constant(""))
        let filledRequired = TextboxFieldView(field: requiredField, value: .constant("ok"))
        let emptyOptional = TextboxFieldView(field: optionalField, value: .constant(""))
        XCTAssertFalse(emptyRequired.isValueAcceptable)
        XCTAssertTrue(filledRequired.isValueAcceptable)
        XCTAssertTrue(emptyOptional.isValueAcceptable)
    }
}
