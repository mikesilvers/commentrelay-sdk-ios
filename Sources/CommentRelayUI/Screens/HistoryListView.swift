import SwiftUI
import CommentRelayCore

public struct HistoryListView: View {
    public let history: CommentRelayHistory
    // Not @Sendable: main-actor SwiftUI action closure — mutates main-actor state.
    public let onSelect: (CommentRelayHistoryEntry) -> Void

    public init(history: CommentRelayHistory, onSelect: @escaping (CommentRelayHistoryEntry) -> Void) {
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
