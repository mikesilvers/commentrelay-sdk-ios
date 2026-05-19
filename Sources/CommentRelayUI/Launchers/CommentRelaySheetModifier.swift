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
            let view = CommentRelayView(configuration: configuration, formId: formId, formTitle: formTitle)
            #if os(macOS)
            // macOS sheets size to content's ideal size and aren't resizable by
            // default. Without an explicit frame the form collapses to ~one line
            // and scrolls. Give it a comfortable ideal size with a resizable floor.
            view.frame(
                minWidth: 420, idealWidth: 480,
                minHeight: 520, idealHeight: 640
            )
            #else
            view
            #endif
        }
    }
}
