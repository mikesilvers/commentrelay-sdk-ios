// Sources/CommentRelayUI/Fields/NumericFieldView.swift
import SwiftUI
import CommentRelayCore

public struct NumericFieldView: FieldRenderer {
    public let field: CommentRelayField
    @Binding public var value: String

    public init(field: CommentRelayField, value: Binding<String>) {
        self.field = field
        self._value = value
    }

    public var isValueAcceptable: Bool {
        if value.isEmpty { return !field.isRequired }
        return Double(value) != nil
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(field: field)
            TextField("", text: $value)
                .textFieldStyle(.roundedBorder)
                #if canImport(UIKit)
                .keyboardType(.decimalPad)
                #endif
        }
    }
}
