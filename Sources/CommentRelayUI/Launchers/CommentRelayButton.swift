// Sources/CommentRelayUI/Launchers/CommentRelayButton.swift
import SwiftUI
import CommentRelayCore

public struct CommentRelayButton<Label: View>: View {
    public let configuration: CommentRelayConfiguration
    public let label: () -> Label

    @State private var isPresented = false

    public init(configuration: CommentRelayConfiguration, @ViewBuilder label: @escaping () -> Label) {
        self.configuration = configuration
        self.label = label
    }

    public var body: some View {
        Button { isPresented = true } label: { label() }
            .commentRelaySheet(isPresented: $isPresented, configuration: configuration)
    }
}
