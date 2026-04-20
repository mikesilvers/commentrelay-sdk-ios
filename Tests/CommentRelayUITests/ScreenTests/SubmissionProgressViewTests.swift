import XCTest
import SwiftUI
import ViewInspector
@testable import CommentRelayUI

final class SubmissionProgressViewTests: XCTestCase {
    func test_rendersInProgressTitle() throws {
        let sut = SubmissionProgressView(state: .inProgress(currentFile: "screenshot.png"))
        XCTAssertNoThrow(try sut.inspect().find(text: Strings.progressTitle))
        XCTAssertNoThrow(try sut.inspect().find(text: Strings.progressFile("screenshot.png")))
    }

    func test_rendersErrorBanner_onFailure() throws {
        let sut = SubmissionProgressView(state: .failed(message: "boom", retry: {}))
        XCTAssertNoThrow(try sut.inspect().find(text: "boom"))
    }
}
