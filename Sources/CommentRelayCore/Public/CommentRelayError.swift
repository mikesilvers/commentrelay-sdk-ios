import Foundation

public enum CommentRelayError: Error {
    case badRequest(message: String)
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

    /// A terminal error should flip the SDK into a disabled state until `reset()` is called.
    public var isTerminal: Bool {
        if case .forbidden = self { return true }
        return false
    }
}
