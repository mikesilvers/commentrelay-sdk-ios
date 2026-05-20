import Foundation

/// A submission that did not deliver: still queued for retry, or terminally failed.
public struct CommentRelaySubmissionProblem: Sendable, Equatable, Identifiable {
    /// Whether this entry is still being retried automatically, or has been marked terminally failed.
    public enum Kind: Sendable, Equatable { case queuedRetrying, failed }

    /// Localization-free error category; the UI maps this to a friendly message.
    public enum Category: String, Sendable, Equatable {
        case server, transport, rateLimited, forbidden, badRequest
        case paymentRequired, notFound, decoding, conflict
        case uploadFailed, uploadUrlExpired, unknown

        public init(_ error: CommentRelayError) {
            switch error {
            case .server:          self = .server
            case .transport:       self = .transport
            case .rateLimited:     self = .rateLimited
            case .forbidden:       self = .forbidden
            case .badRequest:      self = .badRequest
            case .paymentRequired: self = .paymentRequired
            case .notFound:        self = .notFound
            case .decoding:        self = .decoding
            case .conflict:        self = .conflict
            case .uploadFailed:    self = .uploadFailed
            case .uploadUrlExpired: self = .uploadUrlExpired
            }
        }
        init(token: String?) { self = token.flatMap(Category.init(rawValue:)) ?? .unknown }
    }

    /// The queue's `localId` for this submission.
    public let id: UUID
    /// The form this submission targeted.
    public let formId: String
    /// When the submission was first enqueued.
    public let createdAt: Date
    /// Still retrying, or terminally failed.
    public let kind: Kind
    /// Category of the last error; the UI maps this to a localized friendly message.
    public let category: Category
    /// Raw `lastError` text from the queue; empty string if no attempt has been recorded yet.
    public let technicalDetail: String
    /// Number of delivery attempts so far.
    public let attemptCount: Int
    /// Timestamp of the most recent failed attempt; nil if none recorded.
    public let lastAttemptAt: Date?
}
