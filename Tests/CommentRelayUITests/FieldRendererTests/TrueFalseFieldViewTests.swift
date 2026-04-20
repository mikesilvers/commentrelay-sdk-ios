import XCTest
import SwiftUI
import ViewInspector
import CommentRelayCore
@testable import CommentRelayUI

final class TrueFalseFieldViewTests: XCTestCase {
    func test_togglesBoundValue() throws {
        var value = false
        let field = FakeField.trueFalse()
        let sut = TrueFalseFieldView(field: field, value: Binding(get: { value }, set: { value = $0 }))
        let toggle = try sut.inspect().find(ViewType.Toggle.self)
        try toggle.tap()
        XCTAssertTrue(value)
    }
}
