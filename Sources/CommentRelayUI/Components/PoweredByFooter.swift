import SwiftUI
import CommentRelayCore

/// CRLBS-132: subtle "Powered by CommentRelay" attribution shown at the bottom
/// of the feedback widget for free-tier projects. Renders nothing unless the
/// backend config enabled attribution and supplied a link.
struct PoweredByFooter: View {
    let attribution: CommentRelayAttribution
    @Environment(\.commentRelayTheme) private var theme

    var body: some View {
        if let url = attribution.resolvedLink {
            Link(destination: url) {
                Text(Strings.poweredBy)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .underline()
            }
            .tint(theme.accentColor)
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityIdentifier("crl.powered_by")
        }
    }
}
