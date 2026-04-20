import SwiftUI

public struct ThankYouView: View {
    public let showHistoryAction: (@Sendable () -> Void)?
    public let doneAction: @Sendable () -> Void

    public init(showHistoryAction: (@Sendable () -> Void)?, doneAction: @escaping @Sendable () -> Void) {
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
