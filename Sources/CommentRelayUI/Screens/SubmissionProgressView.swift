import SwiftUI

public struct SubmissionProgressView: View {
    public enum State {
        case inProgress(currentFile: String?)
        case failed(message: String, retry: @Sendable () -> Void)
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
