import SwiftUI
import CommentRelayCore

struct ProblemRow: View {
    let problem: CommentRelaySubmissionProblem
    // Not @Sendable: SwiftUI actions run on the main actor.
    let onRetry: () async -> Void
    let onRemove: () -> Void

    @State private var expanded: Bool
    @State private var confirmingRemove = false
    @State private var working = false

    // `initiallyExpanded` defaults to false for production; pass true as a testing seam.
    init(problem: CommentRelaySubmissionProblem,
         onRetry: @escaping () async -> Void,
         onRemove: @escaping () -> Void,
         initiallyExpanded: Bool = false) {
        self.problem = problem
        self.onRetry = onRetry
        self.onRemove = onRemove
        self._expanded = State(initialValue: initiallyExpanded)
    }

    private var isFailed: Bool { problem.kind == .failed }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { expanded.toggle() } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(problem.formId).font(.headline)
                        Text(problem.createdAt, style: .date)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    chip
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption).foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(Strings.friendlyError(problem.category))
                        .font(.callout)
                    Text(problem.technicalDetail)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text(Strings.problemAttempts(problem.attemptCount))
                        .font(.caption2).foregroundStyle(.tertiary)
                    HStack(spacing: 12) {
                        Button(Strings.problemTryAgain) {
                            working = true
                            Task {
                                await onRetry()
                                working = false
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(working)
                        Button(Strings.problemRemove, role: .destructive) {
                            confirmingRemove = true
                        }
                        .buttonStyle(.bordered)
                        if working { ProgressView().controlSize(.small) }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .confirmationDialog(Strings.problemRemoveConfirmTitle,
                            isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button(Strings.problemRemoveConfirm, role: .destructive) { onRemove() }
        }
    }

    private var chip: some View {
        Text(isFailed ? Strings.problemFailedChip : Strings.problemQueuedChip)
            .font(.caption2).bold()
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(isFailed ? Color.red : Color.orange))
            .foregroundStyle(.white)
    }
}
