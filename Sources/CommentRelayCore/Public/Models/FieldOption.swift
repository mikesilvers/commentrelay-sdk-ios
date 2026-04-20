import Foundation

public struct FieldOption: Codable, Sendable, Equatable {
    public let position: Int
    public let label: String?
    public let svg: String?
    public let color: String?

    public init(position: Int, label: String?, svg: String? = nil, color: String? = nil) {
        self.position = position
        self.label = label
        self.svg = svg
        self.color = color
    }
}
