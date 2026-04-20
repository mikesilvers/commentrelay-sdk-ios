// Sources/CommentRelayUI/Fields/EmailFieldView.swift
import SwiftUI
import CommentRelayCore

public struct EmailFieldView: FieldRenderer {
    public let field: CommentRelayField
    @Binding public var value: String

    public init(field: CommentRelayField, value: Binding<String>) {
        self.field = field
        self._value = value
    }

    public var isValueAcceptable: Bool {
        if value.isEmpty { return !field.isRequired }
        return value.contains("@") && value.contains(".")
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(field: field)
            TextField("name@example.com", text: $value)
                .textFieldStyle(.roundedBorder)
                #if canImport(UIKit)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                #endif
                .autocorrectionDisabled()
        }
    }
}
