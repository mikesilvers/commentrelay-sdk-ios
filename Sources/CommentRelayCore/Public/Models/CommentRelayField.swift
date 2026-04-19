import Foundation

public struct CommentRelayField: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let fieldType: FieldType
    public let label: String
    public let isRequired: Bool
    public let isGate: Bool
    public let sortOrder: Int
    public let maxFiles: Int?
    public let options: [FieldOption]?

    enum CodingKeys: String, CodingKey {
        case id
        case fieldType = "field_type"
        case label
        case isRequired = "is_required"
        case isGate = "is_gate"
        case sortOrder = "sort_order"
        case maxFiles = "max_files"
        case options
    }
}
