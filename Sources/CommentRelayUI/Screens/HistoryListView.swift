import SwiftUI
import CommentRelayCore

public struct HistoryListView: View {
    public let history: CommentRelayHistory
    public let onSelect: @Sendable (CommentRelayHistoryEntry) -> Void

    public init(history: CommentRelayHistory, onSelect: @escaping @Sendable (CommentRelayHistoryEntry) -> Void) {
        self.history = history
        self.onSelect = onSelect
    }

    public var body: some View {
        Group {
            if history.submissions.isEmpty {
                EmptyStateView(
                    systemImage: "tray",
                    title: Strings.historyTitle,
                    message: history.isAnonymous ? Strings.historyEmptyAnonymous : Strings.historyEmptyIdentified
                )
            } else {
                List {
                    ForEach(history.submissions) { entry in
                        HistoryRow(entry: entry) {
                            onSelect(entry)
                        }
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
    let onTap: @Sendable () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.categoryTitle).font(.headline)
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
