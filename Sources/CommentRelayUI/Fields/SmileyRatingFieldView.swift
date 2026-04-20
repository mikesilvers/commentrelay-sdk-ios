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
    let position: Int
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        let icon = iconName(for: position)
        let tint: Color = isSelected ? .accentColor : .secondary
        Button(action: onTap) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(tint)
                .symbolRenderingMode(.hierarchical)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Strings.smileyLabel(position: position))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func iconName(for position: Int) -> String {
        switch position {
        case 1: return "face.dashed"
        case 2: return "face.smiling"
        case 3: return "face.smiling"
        case 4: return "face.smiling.fill"
        case 5: return "face.smiling.fill"
        default: return "face.dashed"
        }
    }
}
