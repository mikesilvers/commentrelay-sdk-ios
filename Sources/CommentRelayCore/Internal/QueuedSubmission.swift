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
}
