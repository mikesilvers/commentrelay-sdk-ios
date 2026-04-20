import XCTest
import SwiftUI
import ViewInspector
@testable import CommentRelayUI

final class DraftRestorePromptTests: XCTestCase {
    func test_resumeButton_invokesClosure() throws {
        var resumed = false
        var discarded = false
        let sut = DraftRestorePrompt(onResume: { resumed = true }, onDiscard: { discarded = true })
        try sut.inspect().find(button: Strings.draftResume).tap()
        XCTAssertTrue(resumed)
        XCTAssertFalse(discarded)
    }

    func test_discardButton_invokesClosure() throws {
        var resumed = false
        var discarded = false
        let sut = DraftRestorePrompt(onResume: { resumed = true }, onDiscard: { discarded = true })
        try sut.inspect().find(button: Strings.draftStartOver).tap()
        XCTAssertTrue(discarded)
        XCTAssertFalse(resumed)
    }
}
