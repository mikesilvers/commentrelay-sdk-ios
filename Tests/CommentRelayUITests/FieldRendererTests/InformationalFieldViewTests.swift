import XCTest
import SwiftUI
import ViewInspector
import CommentRelayCore
@testable import CommentRelayUI

final class InformationalFieldViewTests: XCTestCase {
    func test_rendersText() throws {
        let field = FakeField.informational(label: "Be nice.")
        let sut = InformationalFieldView(field: field)
        XCTAssertNoThrow(try sut.inspect().find(text: "Be nice."))
    }

    func test_isValueAcceptable_alwaysTrue() {
        let field = FakeField.informational()
        XCTAssertTrue(InformationalFieldView(field: field).isValueAcceptable)
    }
}
