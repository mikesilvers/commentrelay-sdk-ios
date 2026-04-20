// Tests/CommentRelayUITests/FieldRendererTests/SmileyRatingFieldViewTests.swift
import XCTest
import SwiftUI
import ViewInspector
import CommentRelayCore
@testable import CommentRelayUI

final class SmileyRatingFieldViewTests: XCTestCase {
    func test_rendersFiveButtons() throws {
        var value: Int? = nil
        let field = FakeField.smileyRating()
        let sut = SmileyRatingFieldView(field: field, selectedPosition: Binding(get: { value }, set: { value = $0 }))
        let buttons = try sut.inspect().findAll(ViewType.Button.self)
        XCTAssertEqual(buttons.count, 5)
    }

    func test_tappingButtonUpdatesValue() throws {
        var value: Int? = nil
        let field = FakeField.smileyRating()
        let sut = SmileyRatingFieldView(field: field, selectedPosition: Binding(get: { value }, set: { value = $0 }))
        let buttons = try sut.inspect().findAll(ViewType.Button.self)
        try buttons[3].tap()  // position 4 (happy)
        XCTAssertEqual(value, 4)
    }

    func test_requiredUnselected_isUnacceptable() {
        let field = FakeField.smileyRating(required: true)
        let sut = SmileyRatingFieldView(field: field, selectedPosition: .constant(nil))
        XCTAssertFalse(sut.isValueAcceptable)
    }

    func test_requiredSelected_isAcceptable() {
        let field = FakeField.smileyRating(required: true)
        let sut = SmileyRatingFieldView(field: field, selectedPosition: .constant(3))
        XCTAssertTrue(sut.isValueAcceptable)
    }
}
