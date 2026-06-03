import SwiftUI

/// Shape of a ``CommentRelayConfigurableButton``.
///
/// - `round`: a fixed-diameter circle. Sized by ``CommentRelayButtonSize`` and intended for an
///   icon or a single short glyph — the `title` is **not** used to size a circle (it would
///   distort it), so for `round` provide a `systemImage` or rely on the title's first character.
/// - `oval`: a true ellipse that circumscribes the padded title.
/// - `capsule`: a pill with fully-rounded ends (SwiftUI `Capsule`), sized to the padded title.
public enum CommentRelayButtonShape: Sendable {
    case round
    case oval
    case capsule
}

/// Size of a ``CommentRelayConfigurableButton``. Drives the label font, the title padding, and
/// the diameter used by the `round` shape so every dimension scales from one choice.
public enum CommentRelayButtonSize: Sendable {
    case small
    case medium
    case large

    var font: Font {
        switch self {
        case .small: return .subheadline
        case .medium: return .body
        case .large: return .title3
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .small: return 12
        case .medium: return 16
        case .large: return 22
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .small: return 8
        case .medium: return 11
        case .large: return 15
        }
    }

    /// Diameter of the circle for the `round` shape (also bounds the icon/glyph).
    var roundDiameter: CGFloat {
        switch self {
        case .small: return 36
        case .medium: return 44
        case .large: return 56
        }
    }
}

/// A reusable, configurable button for building SDK launchers and call-to-action controls.
///
/// Configure the `shape` (round / oval / capsule), `size`, fill `color`, and `title`. When
/// `color` is `nil` the button falls back to the SDK theme's accent color
/// (`\.commentRelayTheme`). This component is presentation-agnostic: tapping it runs the supplied
/// `action` closure and nothing more — it does not present the feedback sheet (use
/// ``CommentRelayButton`` for that).
///
/// For the `round` shape, pass a `systemImage` (an SF Symbol) as the glyph; if none is given the
/// first character of `title` is shown. For `capsule` and `oval`, the `title` is rendered and the
/// shape grows to fit it.
public struct CommentRelayConfigurableButton: View {
    private let title: String
    private let shape: CommentRelayButtonShape
    private let size: CommentRelayButtonSize
    private let color: Color?
    private let systemImage: String?
    private let action: () -> Void

    @Environment(\.commentRelayTheme) private var theme

    public init(
        _ title: String = "",
        shape: CommentRelayButtonShape = .capsule,
        size: CommentRelayButtonSize = .medium,
        color: Color? = nil,
        systemImage: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.shape = shape
        self.size = size
        self.color = color
        self.systemImage = systemImage
        self.action = action
    }

    private var fillColor: Color { color ?? theme.accentColor }

    public var body: some View {
        Button(action: action) { content }
            .buttonStyle(.plain)
            .accessibilityIdentifier("crl.configurable_button")
    }

    @ViewBuilder
    private var content: some View {
        switch shape {
        case .round:
            roundContent
        case .capsule:
            titleLabel
                .background(Capsule().fill(fillColor))
                .contentShape(Capsule())
        case .oval:
            titleLabel
                .background(Ellipse().fill(fillColor))
                .contentShape(Ellipse())
        }
    }

    /// Padded title used by the `capsule` and `oval` shapes.
    private var titleLabel: some View {
        Text(title)
            .font(size.font)
            .foregroundStyle(.white)
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
    }

    /// Fixed-diameter circle holding an SF Symbol or, failing that, the title's first character.
    /// VoiceOver still reads `title` when the visible content is icon-only.
    @ViewBuilder
    private var roundContent: some View {
        let circle = Group {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(size.font)
            } else {
                Text(String(title.first.map(String.init) ?? ""))
                    .font(size.font)
            }
        }
        .foregroundStyle(.white)
        .frame(width: size.roundDiameter, height: size.roundDiameter)
        .background(Circle().fill(fillColor))
        .contentShape(Circle())

        // Apply an explicit VoiceOver label only when there's a title. Setting an
        // empty string would override the SF Symbol's own synthesized label and
        // leave an icon-only button unlabeled.
        if title.isEmpty {
            circle
        } else {
            circle.accessibilityLabel(Text(title))
        }
    }
}
