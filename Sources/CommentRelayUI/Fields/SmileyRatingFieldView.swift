// Sources/CommentRelayUI/Fields/SmileyRatingFieldView.swift
import SwiftUI
import CommentRelayCore

public struct SmileyRatingFieldView: FieldRenderer {
    public let field: CommentRelayField
    @Binding public var selectedPosition: Int?

    public init(field: CommentRelayField, selectedPosition: Binding<Int?>) {
        self.field = field
        self._selectedPosition = selectedPosition
    }

    public var isValueAcceptable: Bool {
        field.isRequired ? selectedPosition != nil : true
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FieldLabel(field: field)
            HStack(spacing: 16) {
                ForEach(1...5, id: \.self) { position in
                    SmileyButton(
                        content: SmileyContent.resolve(position: position, options: field.options),
                        position: position,
                        isSelected: selectedPosition == position,
                        onTap: { selectedPosition = position }
                    )
                }
            }
        }
    }
}

private struct SmileyButton: View {
    let content: SmileyContent
    let position: Int
    let isSelected: Bool
    let onTap: () -> Void

    private let size: CGFloat = 36

    var body: some View {
        Button(action: onTap) {
            glyph
                .opacity(isSelected ? 1.0 : 0.55)
                .overlay(
                    Circle()
                        .strokeBorder(
                            isSelected ? Color.accentColor : .clear,
                            lineWidth: 2
                        )
                        .frame(width: size + 6, height: size + 6)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Strings.smileyLabel(position: position))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var glyph: some View {
        switch content {
        case .parsed(let parsed):
            SmileyShape(parsed: parsed, size: size)
        case .fallback(let pos):
            Circle()
                .fill(Self.fallbackColor(for: pos))
                .frame(width: size, height: size)
        }
    }

    private static func fallbackColor(for position: Int) -> Color {
        switch position {
        case 1: return .red
        case 2: return .orange
        case 3: return .yellow
        case 4: return Color(red: 0.53, green: 0.80, blue: 0.27)
        case 5: return .green
        default: return .gray
        }
    }
}
