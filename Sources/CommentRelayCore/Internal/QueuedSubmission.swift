import Foundation

struct QueuedFileRef: Codable, Sendable, Equatable {
    let fieldId: String
    let fileName: String
    let contentType: String
    let size: Int
}

struct QueuedSubmission: Codable, Sendable, Equatable {
    enum Phase: String, Codable, Sendable {
        case needsSubmit   = "needsSubmit"
        case needsUpload   = "needsUpload"
        case needsFinalize = "needsFinalize"
        case done          = "done"
    }
    let localId: UUID
    var submission: CommentRelaySubmission
    var phase: Phase
    var serverSubmissionId: UUID?
    var attachments: [QueuedFileRef]
    var attemptCount: Int
    var nextEarliestAttempt: Date?
    let createdAt: Date
    var lastError: String?
    /// Set when the entry hits a terminal failure (CRLBS-121). Non-nil ⇒ not retried automatically.
    var failedAt: Date?
    /// Timestamp of the most recent attempt that ended in error; nil until the first failure.
    var lastAttemptAt: Date?
    /// Raw value of `CommentRelaySubmissionProblem.Category` (introduced in a later task);
    /// typed `String?` to avoid a cross-task compile dependency — validated against the
    /// enum at write time. UI maps it to a localized friendly message.
    var errorCategory: String?
}
