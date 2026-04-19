import Foundation

public struct DeveloperNote: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let content: String
    public let createdAt: Date

    enum CodingKeys: String, CodingKey { case id, content, createdAt = "created_at" }
}

public struct CommentRelayHistoryEntry: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let categoryId: String
    public let categoryTitle: String
    public let status: String
    public let createdAt: Date
    public let notes: [DeveloperNote]

    enum CodingKeys: String, CodingKey {
        case id
        case categoryId = "category_id"
        case categoryTitle = "category_title"
        case status
        case createdAt = "created_at"
        case notes
    }
}

public struct CommentRelayHistory: Codable, Sendable, Equatable {
    public let isAnonymous: Bool
    public let submissions: [CommentRelayHistoryEntry]

    enum CodingKeys: String, CodingKey {
        case anonymousUser
        case submissions
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.isAnonymous = try c.decodeIfPresent(Bool.self, forKey: .anonymousUser) ?? false
        self.submissions = try c.decode([CommentRelayHistoryEntry].self, forKey: .submissions)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(isAnonymous, forKey: .anonymousUser)
        try c.encode(submissions, forKey: .submissions)
    }
}
