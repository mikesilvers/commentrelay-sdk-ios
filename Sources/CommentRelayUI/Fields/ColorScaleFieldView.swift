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
    // Not @Sendable: SwiftUI Button action — runs on the main actor and
    // mutates the main-actor `@Binding selectedPosition`. @Sendable wrongly
    // forbids that and emits a strict-concurrency warning.
    let onTap: () -> Void

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

