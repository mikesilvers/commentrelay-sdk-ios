import XCTest
import SwiftUI
import ViewInspector
@testable import CommentRelayUI

final class LoadingViewTests: XCTestCase {
    func test_rendersLabel_whenSupplied() throws {
        let sut = LoadingView(label: "Loading…")
        XCTAssertNoThrow(try sut.inspect().find(text: "Loading…"))
    }

    func test_noLabel_whenOmitted() throws {
        let sut = LoadingView(label: nil)
        XCTAssertThrowsError(try sut.inspect().find(ViewType.Text.self))
    }
}
