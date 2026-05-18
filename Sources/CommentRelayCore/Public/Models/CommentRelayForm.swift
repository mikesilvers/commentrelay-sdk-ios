import Foundation

public enum ResponseLimitType: String, Codable, Sendable, Equatable {
    case perSession = "per_session"
    case timeWindow = "time_window"
    case lifetime
}

public struct CommentRelayForm: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let showInPicker: Bool
    public let responseLimitCount: Int?
    public let responseLimitType: ResponseLimitType?
    public let responseLimitWindowMinutes: Int?
    public let moreFeedbackPrompt: String?
    public let isActive: Bool
    public let sortOrder: Int
    public let fields: [CommentRelayField]

    /// Whether this form may be surfaced to the end user. Single source of
    /// truth for both the picker list and explicit preselect-by-id/title, so
    /// the two paths can never disagree about what is visible.
    public var isPickerVisible: Bool { isActive && showInPicker }

    enum CodingKeys: String, CodingKey {
        case id, title
        case showInPicker = "show_in_picker"
        case responseLimitCount = "response_limit_count"
        case responseLimitType = "response_limit_type"
        case responseLimitWindowMinutes = "response_limit_window_minutes"
        case moreFeedbackPrompt = "more_feedback_prompt"
        case isActive = "is_active"
        case sortOrder = "sort_order"
        case fields
    }
}

public enum CommentRelayConfigResponse: Sendable, Equatable {
    case current
    case updated(hash: String, forms: [CommentRelayForm])
}

extension CommentRelayConfigResponse: Decodable {
    private struct Envelope: Decodable {
        let current: Bool
        let hash: String?
        let forms: [CommentRelayForm]?
    }

    public init(from decoder: Decoder) throws {
        let env = try Envelope(from: decoder)
        if env.current {
            self = .current
        } else {
            self = .updated(hash: env.hash ?? "", forms: env.forms ?? [])
        }
    }
}
