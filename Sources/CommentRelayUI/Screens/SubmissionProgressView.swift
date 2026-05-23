import SwiftUI

public struct SubmissionProgressView: View {
    /// Intentionally **not** `Sendable`: this is a view-layer type carrying a
    /// main-actor SwiftUI action closure (`failed`'s `retry`). It is only ever
    /// constructed and consumed on the main actor and never crosses an actor
    /// boundary, so it does not (and should not) conform to `Sendable`.
    public enum State {
        case inProgress(currentFile: String?)
        // retry runs on the main actor (SwiftUI action) — see the type note above.
        case failed(message: String, retry: () -> Void)
    }

    public let state: State

    public init(state: State) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 20) {
            switch state {
            case .inProgress(let currentFile):
                ProgressView().controlSize(.large)
                Text(Strings.progressTitle).font(.headline)
                if let currentFile {
                    Text(Strings.progressFile(currentFile))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            case .failed(let message, let retry):
                ErrorBanner(message: message, retry: retry)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
