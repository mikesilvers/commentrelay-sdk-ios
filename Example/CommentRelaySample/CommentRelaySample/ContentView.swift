import SwiftUI
import CommentRelayCore

struct ContentView: View {
    @State private var baseURLString = "http://localhost:3000"
    @State private var status: Status = .idle

    enum Status {
        case idle
        case loading
        case success
        case failure(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("CommentRelay v\(CommentRelay.version)")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Base URL").font(.caption).foregroundStyle(.secondary)
                TextField("Base URL", text: $baseURLString)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
            }

            Button(action: ping) {
                HStack {
                    if case .loading = status {
                        ProgressView().controlSize(.small)
                    }
                    Text("Ping")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading)

            statusView

            Spacer()
        }
        .padding()
        .frame(minWidth: 320, minHeight: 260)
    }

    private var isLoading: Bool {
        if case .loading = status { return true }
        return false
    }

    @ViewBuilder
    private var statusView: some View {
        switch status {
        case .idle:
            EmptyView()
        case .loading:
            Text("Pinging…").foregroundStyle(.secondary)
        case .success:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failure(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private func ping() {
        guard let url = URL(string: baseURLString) else {
            status = .failure("Invalid URL")
            return
        }
        status = .loading
        Task {
            do {
                let config = CommentRelayConfiguration(baseURL: url, apiKey: "crk_test_sample")
                let client = CommentRelayClient(configuration: config)
                let ok = try await client.ping()
                status = ok ? .success : .failure("Server returned non-2xx")
            } catch {
                status = .failure(error.localizedDescription)
            }
        }
    }
}

#Preview {
    ContentView()
}
