import SwiftUI
import CommentRelayCore

public struct HistoryListView: View {
    public let history: CommentRelayHistory
    /// Problems to surface above the delivered history. Defaults to empty.
    public let problems: [CommentRelaySubmissionProblem]
    // Not @Sendable: SwiftUI action closures run on the main actor.
    public let onSelect: (CommentRelayHistoryEntry) -> Void
    /// Called with the local id when the user taps Try again. Async so the
    /// row's in-progress spinner reflects real retry duration. Defaults to no-op.
    public let onRetry: (UUID) async -> Void
    /// Called with the local id when the user confirms Remove. Defaults to no-op.
    public let onRemove: (UUID) -> Void

    public init(history: CommentRelayHistory,
                problems: [CommentRelaySubmissionProblem] = [],
                onSelect: @escaping (CommentRelayHistoryEntry) -> Void,
                onRetry: @escaping (UUID) async -> Void = { _ in },
                onRemove: @escaping (UUID) -> Void = { _ in }) {
        self.history = history
        self.problems = problems
        self.onSelect = onSelect
        self.onRetry = onRetry
        self.onRemove = onRemove
    }

    public var body: some View {
        Group {
            if history.submissions.isEmpty && problems.isEmpty {
                EmptyStateView(
                    systemImage: "tray",
                    title: Strings.historyTitle,
                    message: history.isAnonymous ? Strings.historyEmptyAnonymous : Strings.historyEmptyIdentified
                )
            } else {
                List {
                    if !problems.isEmpty {
                        Section {
                            ForEach(problems) { p in
                                ProblemRow(problem: p,
                                           onRetry: { await onRetry(p.id) },
                                           onRemove: { onRemove(p.id) })
                            }
                        }
                    }
                    ForEach(history.submissions) { entry in
                        HistoryRow(entry: entry) { onSelect(entry) }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(Strings.historyTitle)
    }
}

private struct HistoryRow: View {
    let entry: CommentRelayHistoryEntry
    // Not @Sendable: SwiftUI Button action — runs on the main actor.
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.formTitle).font(.headline)
                Text(entry.createdAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !entry.notes.isEmpty {
                    Text(entry.notes[0].content)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
