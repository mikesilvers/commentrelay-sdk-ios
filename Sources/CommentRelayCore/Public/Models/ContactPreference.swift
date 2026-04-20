import Foundation

public enum ContactPreference: String, Codable, Sendable, Equatable {
    case none
    case email
    case text
    case phoneCall = "phone_call"
}
