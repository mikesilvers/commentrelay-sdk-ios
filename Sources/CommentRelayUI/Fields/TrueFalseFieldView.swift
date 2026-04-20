import SwiftUI
import CommentRelayCore

public struct TrueFalseFieldView: FieldRenderer {
    public let field: CommentRelayField
    @Binding public var value: Bool

    public init(field: CommentRelayField, value: Binding<Bool>) {
        self.field = field
        self._value = value
    }

    public var isValueAcceptable: Bool { true } // boolean always has a value

    public var body: some View {
        Toggle(isOn: $value) {
            FieldLabel(field: field)
        }
    }
}
