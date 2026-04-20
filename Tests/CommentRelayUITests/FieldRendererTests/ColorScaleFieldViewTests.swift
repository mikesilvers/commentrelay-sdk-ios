// Tests/CommentRelayUITests/FieldRendererTests/ColorScaleFieldViewTests.swift
import XCTest
import SwiftUI
import ViewInspector
import CommentRelayCore
@testable import CommentRelayUI

final class ColorScaleFieldViewTests: XCTestCase {
    func test_rendersTenSwatches() throws {
        let sut = ColorScaleFieldView(field: FakeField.colorScale(), selectedPosition: .constant(nil))
        let buttons = try sut.inspect().findAll(ViewType.Button.self)
        XCTAssertEqual(buttons.count, 10)
    }

    func test_tappingSwatchUpdatesValue() throws {
        var value: Int? = nil
        let sut = ColorScaleFieldView(field: FakeField.colorScale(), selectedPosition: Binding(get: { value }, set: { value = $0 }))
        let buttons = try sut.inspect().findAll(ViewType.Button.self)
        try buttons[6].tap()  // position 7
        XCTAssertEqual(value, 7)
    }
}
