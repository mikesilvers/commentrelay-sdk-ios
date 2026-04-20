import XCTest
import SwiftUI
import ViewInspector
@testable import CommentRelayUI

final class ThankYouViewTests: XCTestCase {
    func test_historyButtonHidden_whenAnonymous() throws {
        let sut = ThankYouView(showHistoryAction: nil, doneAction: {})
        XCTAssertThrowsError(try sut.inspect().find(button: Strings.thanksViewHistory))
    }

    func test_historyButtonVisible_whenActionProvided() throws {
        var tapped = false
        let sut = ThankYouView(showHistoryAction: { tapped = true }, doneAction: {})
        try sut.inspect().find(button: Strings.thanksViewHistory).tap()
        XCTAssertTrue(tapped)
    }

    func test_doneButtonInvokesClosure() throws {
        var done = false
        let sut = ThankYouView(showHistoryAction: nil, doneAction: { done = true })
        try sut.inspect().find(button: Strings.thanksDone).tap()
        XCTAssertTrue(done)
    }
}
