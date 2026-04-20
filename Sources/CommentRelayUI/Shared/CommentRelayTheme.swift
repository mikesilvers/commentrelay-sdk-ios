import SwiftUI

public struct CommentRelayTheme: Sendable {
    public var accentColor: Color
    public var cornerRadius: CGFloat

    public init(accentColor: Color, cornerRadius: CGFloat) {
        self.accentColor = accentColor
        self.cornerRadius = cornerRadius
    }

    public static let `default` = CommentRelayTheme(accentColor: .accentColor, cornerRadius: 12)
}

private struct CommentRelayThemeKey: EnvironmentKey {
    static let defaultValue = CommentRelayTheme.default
}

public extension EnvironmentValues {
    var commentRelayTheme: CommentRelayTheme {
        get { self[CommentRelayThemeKey.self] }
        set { self[CommentRelayThemeKey.self] = newValue }
    }
}
