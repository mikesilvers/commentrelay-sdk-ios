import Foundation

public enum ResponseLimitType: String, Codable, Sendable, Equatable {
    case perSession = "per_session"
    case timeWindow = "time_window"
    case lifetime
}

public struct CommentRelayCategory: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let showInPicker: Bool
    public let responseLimitCount: Int?
    public let responseLimitType: ResponseLimitType?
    public let responseLimitWindowDays: Int?
    public let moreFeedbackPrompt: String?
    public let isActive: Bool
    public let sortOrder: Int
    public let fields: [CommentRelayField]

    enum CodingKeys: String, CodingKey {
        case id, title
        case showInPicker = "show_in_picker"
        case responseLimitCount = "response_limit_count"
        case responseLimitType = "response_limit_type"
        case responseLimitWindowDays = "response_limit_window_days"
        case moreFeedbackPrompt = "more_feedback_prompt"
        case isActive = "is_active"
        case sortOrder = "sort_order"
        case fields
    }
}

public enum CommentRelayConfigResponse: Sendable, Equatable {
    case current
    case updated(hash: String, categories: [CommentRelayCategory])
}

extension CommentRelayConfigResponse: Decodable {
    private struct Envelope: Decodable {
        let current: Bool
        let hash: String?
        let categories: [CommentRelayCategory]?
    }

    public init(from decoder: Decoder) throws {
        let env = try Envelope(from: decoder)
        if env.current {
            self = .current
        } else {
            self = .updated(hash: env.hash ?? "", categories: env.categories ?? [])
        }
    }
}
