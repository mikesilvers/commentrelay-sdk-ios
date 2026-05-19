import SwiftUI

// A SwiftUI View (main-actor); it is never sent across actors, so it neither
// needs nor should assert `Sendable`. The previous `@unchecked Sendable` only
// silenced the non-Sendable `retry` closure — removed.
public struct ErrorBanner: View {
    public let message: String
    public let retry: (() -> Void)?

    public init(message: String, retry: (() -> Void)? = nil) {
        self.message = message
        self.retry = retry
    }

    @Environment(\.commentRelayTheme) private var theme

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let retry {
                Button("Try again") { retry() }
                    .buttonStyle(.bordered)
                    .tint(theme.accentColor)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(message))
    }
}
