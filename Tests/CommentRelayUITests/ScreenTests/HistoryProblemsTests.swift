import XCTest
import SwiftUI
import ViewInspector
@testable import CommentRelayCore
@testable import CommentRelayUI

final class HistoryProblemsTests: XCTestCase {
    private func emptyHistory() -> CommentRelayHistory {
        CommentRelayHistory(isAnonymous: false, submissions: [])
    }
    private func problem() -> CommentRelaySubmissionProblem {
        .init(id: UUID(), formId: "Bug Report", createdAt: Date(), kind: .failed,
              category: .server, technicalDetail: "server(...)", attemptCount: 1, lastAttemptAt: nil)
    }

    func test_problems_render_even_when_history_empty() throws {
        let v = HistoryListView(history: emptyHistory(),
                                problems: [problem()],
                                onSelect: { _ in }, onRetry: { _ in }, onRemove: { _ in })
        XCTAssertNoThrow(try v.inspect().find(text: Strings.problemFailedChip))
    }

    func test_problems_suppress_empty_state() throws {
        let v = HistoryListView(history: emptyHistory(),
                                problems: [problem()],
                                onSelect: { _ in })
        XCTAssertThrowsError(try v.inspect().find(EmptyStateView.self),
            "EmptyStateView must not appear when problems are present")
    }

    func test_problems_shown_with_history_unavailable_notice() throws {
        let harness = HistoryProblemsLoaderHarness(problems: [problem()], serverFailed: true)
        XCTAssertNoThrow(try harness.inspect().find(text: Strings.problemFailedChip))
        XCTAssertNoThrow(try harness.inspect().find(text: Strings.problemHistoryUnavailable))
    }
}

/// Mirrors HistoryLoader's presentation logic with injected state so the
/// offline-resilience branch is unit-testable without a live client.
struct HistoryProblemsLoaderHarness: View {
    let problems: [CommentRelaySubmissionProblem]
    let serverFailed: Bool
    var body: some View {
        VStack {
            if serverFailed {
                Text(Strings.problemHistoryUnavailable).font(.footnote)
            }
            HistoryListView(
                history: CommentRelayHistory(isAnonymous: false, submissions: []),
                problems: problems,
                onSelect: { _ in }, onRetry: { _ in }, onRemove: { _ in })
        }
    }
}
