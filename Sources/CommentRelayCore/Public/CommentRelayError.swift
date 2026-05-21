import Foundation

public enum CommentRelayError: Error {
    case badRequest(message: String)
    case unauthorized(message: String)
    case paymentRequired(message: String)
    case forbidden(message: String)
    case notFound(message: String)
    case conflict(message: String)
    case rateLimited(retryAfter: TimeInterval?)
    case server(message: String)
    case transport(URLError)
    case decoding(Error)
    case uploadFailed(submissionId: UUID, fileName: String, underlying: Error)
    case uploadUrlExpired(submissionId: UUID)
    case unexpectedStatus(statusCode: Int, message: String)

    /// A terminal error flips the SDK into a disabled state (circuit breaker) until `reset()` is called.
    /// Note: `.unauthorized` is classified `.terminal` by `RetryPolicy` (fail the submission, don't retry)
    /// but is NOT `isTerminal` — 401 does not engage the circuit breaker; only `forbidden` (403) does.
    public var isTerminal: Bool {
        if case .forbidden = self { return true }
        return false
    }
}
