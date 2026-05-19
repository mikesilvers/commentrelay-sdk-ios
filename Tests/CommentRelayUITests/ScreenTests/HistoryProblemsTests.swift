import XCTest
import SwiftUI
import ViewInspector
@testable import CommentRelayCore
@testable import CommentRelayUI

final class HistoryProblemsTests: XCTestCase {
    private func emptyHistory() throws -> CommentRelayHistory {
        try JSONDecoder().decode(CommentRelayHistory.self,
            from: Data(#"{"anonymousUser":false,"submissions":[]}"#.utf8))
    }
    private func problem() -> CommentRelaySubmissionProblem {
        .init(id: UUID(), formId: "Bug Report", createdAt: Date(), kind: .failed,
              category: .server, technicalDetail: "server(...)", attemptCount: 1, lastAttemptAt: nil)
    }

    func test_problems_render_even_when_history_empty() throws {
        let v = HistoryListView(history: try emptyHistory(),
                                problems: [problem()],
                                onSelect: { _ in }, onRetry: { _ in }, onRemove: { _ in })
        XCTAssertNoThrow(try v.inspect().find(text: Strings.problemFailedChip))
    }

    func test_problems_suppress_empty_state() throws {
        let v = HistoryListView(history: try emptyHistory(),
                                problems: [problem()],
                                onSelect: { _ in })
        XCTAssertThrowsError(try v.inspect().find(EmptyStateView.self),
            "EmptyStateView must not appear when problems are present")
    }
}
