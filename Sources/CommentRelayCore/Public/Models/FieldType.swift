import Foundation

public enum FieldType: String, Codable, Sendable, Equatable {
    case textbox
    case trueFalse = "true_false"
    case numeric
    case photo
    case attachment
    case informational
    case email
    case phone
    case smileyRating = "smiley_rating"
    case colorScale = "color_scale"
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = FieldType(rawValue: raw) ?? .unknown
    }
}
