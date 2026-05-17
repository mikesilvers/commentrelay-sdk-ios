import Foundation

public enum Platform: String, Codable, Sendable, Equatable {
    case ios, android, web, server, other, macos
}

public extension Platform {
    /// The platform the SDK is currently running on.
    /// iPadOS and Mac Catalyst compile under `os(iOS)` and report `.ios`.
    static var current: Platform {
        #if os(iOS)
        return .ios
        #elseif os(macOS)
        return .macos
        #else
        return .other
        #endif
    }
}
