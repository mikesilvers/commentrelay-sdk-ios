import SwiftUI

public struct ThankYouView: View {
    // Not @Sendable: main-actor SwiftUI action closures — mutate main-actor state.
    public let showHistoryAction: (() -> Void)?
    public let doneAction: () -> Void

    public init(showHistoryAction: (() -> Void)?, doneAction: @escaping () -> Void) {
        self.showHistoryAction = showHistoryAction
        self.doneAction = doneAction
    }

    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text(Strings.thanksTitle).font(.largeTitle).bold()
            Text(Strings.thanksBody)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                if let showHistoryAction {
                    Button(Strings.thanksViewHistory, action: showHistoryAction)
                        .buttonStyle(.bordered)
                }
                Button(Strings.thanksDone, action: doneAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
