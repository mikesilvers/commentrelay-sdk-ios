import SwiftUI
import CommentRelayCore
import CommentRelayUI

struct ContentView: View {
    @State private var baseURLString = "http://localhost:3000"
    @State private var apiKeyString = "crk_test_sample"
    @State private var userIdentifier = ""
    @State private var isFeedbackPresented = false
    @State private var pingStatus: PingStatus = .idle

    enum PingStatus {
        case idle, loading, success, failure(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("CommentRelay v\(CommentRelay.version)")
                .font(.headline)

            group("Base URL", $baseURLString)
            group("API key", $apiKeyString)
            group("User identifier (optional)", $userIdentifier)

            Button(action: ping) {
                HStack {
                    if case .loading = pingStatus { ProgressView().controlSize(.small) }
                    Text("Ping /health")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button("Send feedback") {
                isFeedbackPresented = true
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            .commentRelaySheet(
                isPresented: $isFeedbackPresented,
                configuration: makeConfig()
            )

            pingStatusView

            Spacer()
        }
        .padding()
        .frame(minWidth: 320, minHeight: 360)
    }

    private func group(_ label: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
        }
    }

    @ViewBuilder
    private var pingStatusView: some View {
        switch pingStatus {
        case .idle: EmptyView()
        case .loading: Text("Pinging…").foregroundStyle(.secondary)
        case .success: Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failure(let m): Label(m, systemImage: "xmark.circle.fill").foregroundStyle(.red)
        }
    }

    private func makeConfig() -> CommentRelayConfiguration {
        let url = URL(string: baseURLString) ?? URL(string: "http://localhost:3000")!
        return CommentRelayConfiguration(
            apiKey: apiKeyString,
            baseURL: url,
            userIdentifier: userIdentifier.isEmpty ? nil : userIdentifier
        )
    }

    private func ping() {
        pingStatus = .loading
        Task {
            do {
                let ok = try await CommentRelayClient(configuration: makeConfig()).ping()
                pingStatus = ok ? .success : .failure("Server returned non-2xx")
            } catch {
                pingStatus = .failure(error.localizedDescription)
            }
        }
    }
}

#Preview {
    ContentView()
}
