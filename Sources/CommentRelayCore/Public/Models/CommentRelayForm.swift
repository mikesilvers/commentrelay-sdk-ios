import Foundation

public enum ResponseLimitType: String, Codable, Sendable, Equatable {
    case perSession = "per_session"
    case timeWindow = "time_window"
    case lifetime
}

public struct CommentRelayForm: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let clientFormId: String?
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
        case clientFormId = "client_form_id"
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

/// Full decode of `GET /sdk/v1/config` (CRLBS-132): the forms response plus
/// project-level attribution. Attribution rides the envelope top-level on every
/// response (both `current` and `updated`) so it stays fresh independent of the
/// forms hash. `attribution_url` is decoded leniently — a malformed value maps
/// to `nil` rather than failing the whole config decode.
struct DecodedConfigResponse: Decodable {
    let response: CommentRelayConfigResponse
    let attribution: CommentRelayAttribution

    private enum CodingKeys: String, CodingKey {
        case showAttribution = "show_attribution"
        case attributionURL = "attribution_url"
    }

    init(from decoder: Decoder) throws {
        response = try CommentRelayConfigResponse(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let show = try c.decodeIfPresent(Bool.self, forKey: .showAttribution) ?? false
        let urlString = try c.decodeIfPresent(String.self, forKey: .attributionURL)
        let url = urlString.flatMap(URL.init(string:))
        attribution = CommentRelayAttribution(showAttribution: show, attributionURL: url)
    }
}
