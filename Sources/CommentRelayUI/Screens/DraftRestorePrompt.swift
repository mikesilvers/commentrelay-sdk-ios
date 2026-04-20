import SwiftUI

public struct DraftRestorePrompt: View {
    public let onResume: @Sendable () -> Void
    public let onDiscard: @Sendable () -> Void

    public init(onResume: @escaping @Sendable () -> Void, onDiscard: @escaping @Sendable () -> Void) {
        self.onResume = onResume
        self.onDiscard = onDiscard
    }

    public var body: some View {
        VStack(spacing: 16) {
            Text(Strings.draftRestoreTitle).font(.headline)
            Text(Strings.draftRestoreBody)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button(Strings.draftStartOver, action: onDiscard)
                    .buttonStyle(.bordered)
                Button(Strings.draftResume, action: onResume)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}
