import Foundation

public enum SubmitOutcome: Sendable, Equatable {
    case submitted(CommentRelaySubmissionReceipt)
    case queued(localId: UUID)
}
