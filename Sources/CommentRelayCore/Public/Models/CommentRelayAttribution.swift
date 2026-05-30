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
    public var resolvedLink: URL? { showAttribution ? attributionURL : nil }
}
