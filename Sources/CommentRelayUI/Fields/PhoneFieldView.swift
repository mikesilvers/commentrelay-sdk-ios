// Sources/CommentRelayUI/Fields/PhoneFieldView.swift
import SwiftUI
import CommentRelayCore

public struct PhoneFieldView: FieldRenderer {
    public let field: CommentRelayField
    @Binding public var value: String

    public init(field: CommentRelayField, value: Binding<String>) {
        self.field = field
        self._value = value
    }

    public var isValueAcceptable: Bool {
        if value.isEmpty { return !field.isRequired }
        let digits = value.filter(\.isNumber)
        return digits.count >= 7
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(field: field)
            TextField("", text: $value)
                .textFieldStyle(.roundedBorder)
                #if canImport(UIKit)
                .keyboardType(.phonePad)
                #endif
        }
    }
}
