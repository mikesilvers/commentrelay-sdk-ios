// Sources/CommentRelayUI/Fields/TextboxFieldView.swift
import SwiftUI
import CommentRelayCore

public struct TextboxFieldView: FieldRenderer {
    public let field: CommentRelayField
    @Binding public var value: String

    public init(field: CommentRelayField, value: Binding<String>) {
        self.field = field
        self._value = value
    }

    public var isValueAcceptable: Bool {
        field.isRequired ? !value.trimmingCharacters(in: .whitespaces).isEmpty : true
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(field: field)
            TextEditor(text: $value)
                .frame(minHeight: 80)
                .overlay(
                    RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3))
                )
            Text(Strings.characterCount(value.count, 10_000))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
    }
}
