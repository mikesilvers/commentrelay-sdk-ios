import SwiftUI

public struct LoadingView: View {
    public let label: String?

    public init(label: String? = nil) {
        self.label = label
    }

    public var body: some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.large)
            if let label {
                Text(label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
