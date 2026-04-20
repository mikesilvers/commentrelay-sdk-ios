import XCTest
import SwiftUI
import ViewInspector
@testable import CommentRelayUI

private class TapState {
    var tapped = false
}

final class ErrorBannerTests: XCTestCase {
    func test_displaysMessage() throws {
        let sut = ErrorBanner(message: "Kaboom", retry: nil)
        let text = try sut.inspect().find(text: "Kaboom")
        XCTAssertEqual(try text.string(), "Kaboom")
    }

    func test_retryHidden_whenRetryClosureIsNil() throws {
        let sut = ErrorBanner(message: "Kaboom", retry: nil)
        XCTAssertThrowsError(try sut.inspect().find(button: "Try again"))
    }

    @MainActor
    func test_retryVisible_whenClosureSupplied() throws {
        let state = TapState()
        let sut = ErrorBanner(message: "Kaboom") { state.tapped = true }
        try sut.inspect().find(button: "Try again").tap()
        XCTAssertTrue(state.tapped)
    }
}
