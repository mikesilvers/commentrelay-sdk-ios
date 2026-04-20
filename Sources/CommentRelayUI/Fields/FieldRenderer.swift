// Sources/CommentRelayUI/Fields/FieldRenderer.swift
import SwiftUI
import CommentRelayCore

public protocol FieldRenderer: View {
    var field: CommentRelayField { get }
    /// `true` iff the renderer's current bound value is sufficient for `field.isRequired`.
    var isValueAcceptable: Bool { get }
}

public struct FieldLabel: View {
    public let field: CommentRelayField
    public init(field: CommentRelayField) { self.field = field }

    public var body: some View {
        HStack(spacing: 4) {
            Text(field.label).font(.headline)
            if field.isRequired {
                Text("*").foregroundStyle(.red).accessibilityLabel(Strings.formRequired)
            }
        }
    }
}
