// Sources/CommentRelayUI/Launchers/CommentRelaySheetModifier.swift
import SwiftUI
import CommentRelayCore

public extension View {
    func commentRelaySheet(
        isPresented: Binding<Bool>,
        configuration: CommentRelayConfiguration,
        formId: String? = nil,
        formTitle: String? = nil
    ) -> some View {
        sheet(isPresented: isPresented) {
            CommentRelayView(configuration: configuration, formId: formId, formTitle: formTitle)
        }
    }
}
