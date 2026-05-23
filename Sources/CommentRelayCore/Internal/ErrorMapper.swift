import Foundation

enum ErrorMapper {
    private struct APIErrorEnvelope: Decodable {
        struct Inner: Decodable { let code: String; let message: String }
        let error: Inner
    }

    static func map(response: HTTPURLResponse, data: Data) -> CommentRelayError {
        let message: String = {
            if let env = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) {
                return env.error.message
            }
            return "HTTP \(response.statusCode)"
        }()

        switch response.statusCode {
        case 400: return .badRequest(message: message)
        case 401: return .unauthorized(message: message)
        case 402: return .paymentRequired(message: message)
        case 403: return .forbidden(message: message)
        case 404: return .notFound(message: message)
        case 409: return .conflict(message: message)
        case 429:
            let retry = (response.value(forHTTPHeaderField: "Retry-After")).flatMap(TimeInterval.init)
            return .rateLimited(retryAfter: retry)
        case 500..<600:
            return .server(message: message)                                                // retryable
        default:
            return .unexpectedStatus(statusCode: response.statusCode, message: message)     // terminal
        }
    }
}
