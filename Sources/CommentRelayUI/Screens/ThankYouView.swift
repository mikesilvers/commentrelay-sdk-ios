import SwiftUI

public struct ThankYouView: View {
    /// `true` = delivered to the server (classic thank-you). `false` = saved
    /// locally but not yet delivered (queued for retry) — honest messaging so
    /// a server failure is never shown as a delivered success (CRLBS-119).
    public let delivered: Bool
    // Not @Sendable: main-actor SwiftUI action closures — mutate main-actor state.
    public let showHistoryAction: (() -> Void)?
    public let doneAction: () -> Void

    public init(delivered: Bool = true,
                showHistoryAction: (() -> Void)?,
                doneAction: @escaping () -> Void) {
        self.delivered = delivered
        self.showHistoryAction = showHistoryAction
        self.doneAction = doneAction
    }

    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: delivered ? "checkmark.seal.fill" : "tray.and.arrow.down.fill")
                .font(.system(size: 64))
                .foregroundStyle(delivered ? Color.green : Color.orange)
                .accessibilityHidden(true)
            Text(delivered ? Strings.thanksTitle : Strings.queuedTitle).font(.largeTitle).bold()
            Text(delivered ? Strings.thanksBody : Strings.queuedBody)
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
