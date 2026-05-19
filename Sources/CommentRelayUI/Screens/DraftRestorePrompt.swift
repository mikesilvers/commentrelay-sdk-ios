import SwiftUI

public struct DraftRestorePrompt: View {
    // Not @Sendable: main-actor SwiftUI action closures — mutate main-actor state.
    public let onResume: () -> Void
    public let onDiscard: () -> Void

    public init(onResume: @escaping () -> Void, onDiscard: @escaping () -> Void) {
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
