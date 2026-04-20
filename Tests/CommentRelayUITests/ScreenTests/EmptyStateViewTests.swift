import XCTest
import SwiftUI
import ViewInspector
@testable import CommentRelayUI

final class EmptyStateViewTests: XCTestCase {
    func test_rendersTitleAndMessage() throws {
        let sut = EmptyStateView(systemImage: "tray", title: "Nothing here", message: "Pull to refresh.")
        XCTAssertNoThrow(try sut.inspect().find(text: "Nothing here"))
        XCTAssertNoThrow(try sut.inspect().find(text: "Pull to refresh."))
    }
}
