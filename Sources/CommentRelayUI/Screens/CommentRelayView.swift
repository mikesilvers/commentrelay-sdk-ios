// Sources/CommentRelayUI/Screens/CommentRelayView.swift
import SwiftUI
import CommentRelayCore

public struct CommentRelayView: View {
    public let configuration: CommentRelayConfiguration

    @State private var route: Route = .loading
    @State private var client: CommentRelayClient
    @State private var activeViewModel: FeedbackFormViewModel? = nil

    @MainActor
    public init(configuration: CommentRelayConfiguration) {
        self.configuration = configuration
        self._client = State(initialValue: CommentRelayClient(configuration: configuration))
    }

    enum Route {
        case loading
        case picker(forms: [CommentRelayForm])
        case form(form: CommentRelayForm)
        case progress(currentFile: String?)
        case progressFailed(message: String)
        case thanks(showHistory: Bool)
        case history
    }

    public var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: toolbarPlacement) {
                        Button {
                            route = .history
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                                .accessibilityLabel(Strings.historyTitle)
                        }
                    }
                }
                .task {
                    await loadForms()
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch route {
        case .loading:
            LoadingView(label: Strings.formSending)
        case .picker(let forms):
            FormPickerView(forms: forms) { selected in
                let vm = FeedbackFormViewModel(
                    form: selected,
                    userIdentifier: configuration.userIdentifier ?? "anonymous",
                    platform: .ios,
                    sdkVersion: configuration.effectiveSDKVersion
                )
                activeViewModel = vm
                route = .form(form: selected)
            }
        case .form:
            if let vm = activeViewModel {
                FeedbackFormView(viewModel: vm) { submission in
                    Task { @MainActor in await submitWithViewModel(submission) }
                }
            } else {
                LoadingView(label: nil)
            }
        case .progress(let file):
            SubmissionProgressView(state: .inProgress(currentFile: file))
        case .progressFailed(let message):
            SubmissionProgressView(state: .failed(message: message, retry: {
                Task { @MainActor in await reload() }
            }))
        case .thanks(let showHistory):
            ThankYouView(
                showHistoryAction: showHistory ? { route = .history } : nil,
                doneAction: { Task { @MainActor in await reload() } }
            )
        case .history:
            HistoryLoader(client: client)
        }
    }

    // MARK: - Actions

    private func reload() async {
        activeViewModel = nil
        route = .loading
        await loadForms()
    }

    private func loadForms() async {
        do {
            switch try await client.fetchConfig(cachedHash: nil) {
            case .current:
                route = .picker(forms: [])
            case .updated(_, let forms):
                route = .picker(forms: forms)
            }
        } catch let err as CommentRelayError {
            CommentRelayLoggerHolder.shared.log(level: .error, message: "fetchConfig failed", error: err)
            route = .progressFailed(message: message(for: err))
        } catch {
            CommentRelayLoggerHolder.shared.log(level: .error, message: "fetchConfig failed with unexpected error", error: error)
            route = .progressFailed(message: Strings.errorGeneric)
        }
    }

    private func submitWithViewModel(_ submission: CommentRelaySubmission) async {
        guard let vm = activeViewModel else { return }
        route = .progress(currentFile: nil)
        do {
            let receipt = try await client.submit(submission)
            let payloads = vm.filePayloads(for: receipt)
            if receipt.hasUploads {
                try await client.uploadFiles(receipt: receipt, payloads: payloads)
            } else {
                try await client.finalize(submissionId: receipt.submissionId)
            }
            route = .thanks(showHistory: configuration.userIdentifier != nil)
        } catch let err as CommentRelayError {
            CommentRelayLoggerHolder.shared.log(level: .error, message: "submit failed", error: err)
            route = .progressFailed(message: message(for: err))
        } catch {
            CommentRelayLoggerHolder.shared.log(level: .error, message: "submit failed with unexpected error", error: error)
            route = .progressFailed(message: Strings.errorGeneric)
        }
    }

    private func message(for error: CommentRelayError) -> String {
        switch error {
        case .paymentRequired: return Strings.errorPaymentRequired
        case .rateLimited: return Strings.errorRateLimited
        case .uploadFailed: return Strings.errorUploadFailed
        default: return Strings.errorGeneric
        }
    }

    // MARK: - Platform helpers

    private var toolbarPlacement: ToolbarItemPlacement {
        #if os(iOS)
        return .topBarTrailing
        #else
        return .primaryAction
        #endif
    }
}

private struct HistoryLoader: View {
    let client: CommentRelayClient
    @State private var history: CommentRelayHistory? = nil
    @State private var selectedId: UUID? = nil
    @State private var errorMessage: String? = nil

    var body: some View {
        Group {
            if let history {
                HistoryListView(history: history) { entry in
                    let eid = entry.id
                    Task { @MainActor in selectedId = eid }
                }
                .navigationDestination(item: $selectedId) { entryId in
                    if let entry = history.submissions.first(where: { $0.id == entryId }) {
                        HistoryDetailView(entry: entry)
                    }
                }
            } else if let errorMessage {
                ErrorBanner(message: errorMessage, retry: nil)
            } else {
                LoadingView(label: nil)
            }
        }
        .task {
            do {
                history = try await client.fetchHistory()
            } catch {
                CommentRelayLoggerHolder.shared.log(level: .error, message: "fetchHistory failed", error: error)
                errorMessage = Strings.errorGeneric
            }
        }
    }
}
