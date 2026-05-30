import Foundation

/// Project-level "Powered by CommentRelay" attribution state (CRLBS-132).
/// Delivered by the backend on every `GET /sdk/v1/config` response. The SDK
/// renders the attribution link only when `showAttribution` is true and a URL
/// is present; otherwise nothing is shown. Defaults to hidden so the SDK is
/// forward-compatible with backends that don't yet send the fields.
public struct CommentRelayAttribution: Sendable, Equatable {
    public let showAttribution: Bool
    public let attributionURL: URL?

    public init(showAttribution: Bool, attributionURL: URL?) {
        self.showAttribution = showAttribution
        self.attributionURL = attributionURL
    }

    /// Safe default: no attribution.
    public static let hidden = CommentRelayAttribution(showAttribution: false, attributionURL: nil)

    /// The link to present, or `nil` when attribution must be hidden. Single
    /// source of truth for the gating rule so the view and tests can't disagree.
    ///
    /// Only `https` links with a non-empty host are surfaced. A non-https scheme
    /// (e.g. `http`, or a hostile `javascript:`/custom scheme) is rejected at this
    /// trust boundary so a malformed or hostile config value can never escalate
    /// the SwiftUI `Link` sink to an arbitrary scheme (CRLBS-132 security review).
    public var resolvedLink: URL? {
        guard showAttribution,
              let url = attributionURL,
              url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }
}
