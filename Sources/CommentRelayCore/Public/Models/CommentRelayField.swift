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
    public let parentFieldId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case fieldType = "field_type"
        case label
        case isRequired = "is_required"
        case isGate = "is_gate"
        case sortOrder = "sort_order"
        case maxFiles = "max_files"
        case options
        case parentFieldId = "parent_field_id"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        fieldType = try c.decode(FieldType.self, forKey: .fieldType)
        label = try c.decode(String.self, forKey: .label)
        isRequired = try c.decode(Bool.self, forKey: .isRequired)
        isGate = try c.decode(Bool.self, forKey: .isGate)
        sortOrder = try c.decode(Int.self, forKey: .sortOrder)
        maxFiles = try c.decodeIfPresent(Int.self, forKey: .maxFiles)
        options = try c.decodeIfPresent([FieldOption].self, forKey: .options)
        parentFieldId = try c.decodeIfPresent(String.self, forKey: .parentFieldId)
    }
}
