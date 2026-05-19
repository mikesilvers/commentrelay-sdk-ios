import Foundation

enum RetryDecision: Equatable {
    case retry(TimeInterval?)   // associated value = server-supplied Retry-After, if any
    case terminal
    case pause                  // 403: engage circuit-breaker, retain entries
}

enum RetryPolicy {
    static func classify(_ error: CommentRelayError) -> RetryDecision {
        switch error {
        case .transport, .server: return .retry(nil)
        case .rateLimited(let after): return .retry(after)
        case .forbidden: return .pause
        case .badRequest, .paymentRequired, .notFound, .decoding,
             .conflict, .uploadFailed, .uploadUrlExpired:
            return .terminal
        }
    }

    /// Exponential `2^(attempt-1)` capped at 30s; if `retryAfter` is larger, it wins.
    static func backoff(attempt: Int, retryAfter: TimeInterval?) -> TimeInterval {
        let exp = pow(2.0, Double(max(attempt, 1) - 1))
        let capped = min(exp, 30)
        if let ra = retryAfter { return max(capped, ra) }
        return capped
    }
}
