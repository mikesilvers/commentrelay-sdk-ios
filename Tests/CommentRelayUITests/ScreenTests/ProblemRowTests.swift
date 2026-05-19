import XCTest
import SwiftUI
import ViewInspector
@testable import CommentRelayCore
@testable import CommentRelayUI

@MainActor
final class ProblemRowTests: XCTestCase {
    private func problem(_ kind: CommentRelaySubmissionProblem.Kind) -> CommentRelaySubmissionProblem {
        .init(id: UUID(), formId: "f", createdAt: Date(), kind: kind,
              category: .server, technicalDetail: #"server(message: "HTTP 500")"#,
              attemptCount: 2, lastAttemptAt: Date())
    }

    func test_failed_row_shows_failed_chip_and_actions_on_expand() throws {
        var retried = false
        let exp = XCTestExpectation(description: "retry called")
        // Start with expanded = true so actions are visible without @State mutation
        let row = ProblemRow(problem: problem(.failed),
                             onRetry: { retried = true; exp.fulfill() },
                             onRemove: {},
                             initiallyExpanded: true)
        let r = try row.inspect()
        XCTAssertNoThrow(try r.find(text: Strings.problemFailedChip))  // chip visible
        let btn = try r.find(button: Strings.problemTryAgain)
        try btn.tap()
        wait(for: [exp], timeout: 1.0)
        XCTAssertTrue(retried)
        XCTAssertNoThrow(try r.find(text: #"server(message: "HTTP 500")"#))
    }

    func test_failed_row_collapsed_shows_failed_chip() throws {
        let row = ProblemRow(problem: problem(.failed), onRetry: {}, onRemove: {})
        XCTAssertNoThrow(try row.inspect().find(text: Strings.problemFailedChip))
        XCTAssertThrowsError(try row.inspect().find(button: Strings.problemTryAgain),
            "Try again must not be visible when row is collapsed")
    }

    func test_queued_row_shows_queued_chip() throws {
        let row = ProblemRow(problem: problem(.queuedRetrying), onRetry: {}, onRemove: {})
        XCTAssertNoThrow(try row.inspect().find(text: Strings.problemQueuedChip))
    }
}
