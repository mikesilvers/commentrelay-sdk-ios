// Sources/CommentRelayUI/Fields/ColorScaleFieldView.swift
import SwiftUI
import CommentRelayCore

public struct ColorScaleFieldView: FieldRenderer {
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
            HStack(spacing: 4) {
                ForEach(field.options ?? [], id: \.position) { option in
                    ColorSwatch(option: option, isSelected: selectedPosition == option.position) {
                        selectedPosition = option.position
                    }
                }
            }
        }
    }
}

private struct ColorSwatch: View {
    let option: FieldOption
    let isSelected: Bool
    let onTap: @Sendable () -> Void

    var body: some View {
        Button(action: onTap) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hex: option.color ?? "#888888"))
                .frame(height: 36)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isSelected ? Color.primary : Color.clear, lineWidth: 3)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.label ?? "\(option.position)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private extension Color {
    /// Parses `#RRGGBB` or `#RRGGBBAA`. Returns `.gray` on malformed input.
    init(hex: String) {
        let trimmed = hex.trimmingCharacters(in: .whitespaces).trimmingPrefix("#")
        var value: UInt64 = 0
        Scanner(string: String(trimmed)).scanHexInt64(&value)
        let length = trimmed.count
        let r, g, b, a: Double
        switch length {
        case 6:
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
            a = 1
        case 8:
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
            a = Double(value & 0xFF) / 255
        default:
            self = .gray
            return
        }
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
