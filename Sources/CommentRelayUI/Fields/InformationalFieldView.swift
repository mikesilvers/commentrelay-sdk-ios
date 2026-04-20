import SwiftUI
import CommentRelayCore

public struct InformationalFieldView: FieldRenderer {
    public let field: CommentRelayField

    public init(field: CommentRelayField) {
        self.field = field
    }

    public var isValueAcceptable: Bool { true }

    public var body: some View {
        Text(field.label)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isStaticText)
    }
}
