// Sources/CommentRelayUI/Launchers/CommentRelaySheetModifier.swift
import SwiftUI
import CommentRelayCore

public extension View {
    func commentRelaySheet(isPresented: Binding<Bool>, configuration: CommentRelayConfiguration) -> some View {
        sheet(isPresented: isPresented) {
            CommentRelayView(configuration: configuration)
        }
    }
}
