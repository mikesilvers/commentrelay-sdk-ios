import SwiftUI
import CommentRelayCore

public struct HistoryDetailView: View {
    public let entry: CommentRelayHistoryEntry

    public init(entry: CommentRelayHistoryEntry) {
        self.entry = entry
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // CRLBS-129: let a long title wrap instead of truncating; align
                // the date to the title's first line.
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.formTitle).font(.title2).bold()
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Text(entry.createdAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !entry.notes.isEmpty {
                    Text(Strings.historyNotesHeader)
                        .font(.headline)
                        .padding(.top)
                    ForEach(entry.notes) { note in
                        NoteCard(note: note)
                    }
                }
            }
            .padding()
        }
    }
}

private struct NoteCard: View {
    let note: DeveloperNote

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.content).font(.callout)
            Text(note.createdAt, style: .date).font(.caption2).foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
    }
}
