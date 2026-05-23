// Sources/CommentRelayUI/Screens/CommentRelayView.swift
import SwiftUI
import CommentRelayCore

public struct CommentRelayView: View {
    public let configuration: CommentRelayConfiguration
    let preselect: FormPreselect?

    @State private var route: Route = .loading
    @State private var client: CommentRelayClient
    @State private var activeViewModel: FeedbackFormViewModel? = nil
    @State private var pendingCount = 0
    // CRLBS-130: load config exactly once per sheet session (a spurious .task
    // re-fire must not re-run loadForms and bounce the user back into a form),
    // and remember once a submission succeeded so the preselect isn't reapplied.
    @State private var didLoad = false
    @State private var submitted = false

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    @MainActor
    public init(configuration: CommentRelayConfiguration, formId: String? = nil, formTitle: String? = nil) {
        self.configuration = configuration
        self.preselect = FormPreselect(formId: formId, formTitle: formTitle)
        self._client = State(initialValue: CommentRelayClient(configuration: configuration))
    }

    enum Route: Equatable {
        case loading
        case picker(forms: [CommentRelayForm])
        case form(form: CommentRelayForm)
        case progress(currentFile: String?)
        case progressFailed(message: String)
        case thanks(showHistory: Bool)
        /// Submission accepted locally but NOT yet delivered to the server
        /// (queued for retry). Must never be presented as a delivered/"thank
        /// you" success — see CRLBS-119.
        case queuedSaved
        case history
    }

    /// Pure mapping from a submit outcome to the screen to show. Extracted so
    /// the queued-vs-delivered invariant is unit-testable without SwiftUI.
    /// `.queued` MUST NOT map to `.thanks` (that falsely claims delivery).
    static func route(for outcome: SubmitOutcome, hasUserIdentifier: Bool) -> Route {
        switch outcome {
        case .submitted: return .thanks(showHistory: hasUserIdentifier)
        case .queued:    return .queuedSaved
        }
    }

    public var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(Strings.sheetCancel) { dismiss() }
                    }
                    ToolbarItem(placement: toolbarPlacement) {
                        Button {
                            route = .history
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                                .accessibilityHidden(true)
                                .overlay(alignment: .topTrailing) {
                                    PendingBadge(count: pendingCount)
                                        .offset(x: 8, y: -8)
                                        .accessibilityHidden(true)
                                }
                        }
                        .accessibilityLabel(pendingCount > 0
                            ? "\(Strings.historyTitle), \(pendingCount) pending"
                            : Strings.historyTitle)
                    }
                }
                .task {
                    guard !didLoad else { return }
                    didLoad = true
                    await loadForms()
                }
        }
        .task {
            let stream = await client.pendingSubmissionCountStream()
            for await n in stream { pendingCount = n }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await client.flushQueue() } }
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
                    platform: Platform.current,
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
                doneAction: { dismiss() }
            )
        case .queuedSaved:
            // Honest "saved, not yet delivered" state. No history action —
            // the server has no record yet (queued locally for retry).
            ThankYouView(
                delivered: false,
                showHistoryAction: nil,
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
                if !submitted, let preselect, let match = preselect.match(in: forms) {
                    let vm = FeedbackFormViewModel(
                        form: match,
                        userIdentifier: configuration.userIdentifier ?? "anonymous",
                        platform: Platform.current,
                        sdkVersion: configuration.effectiveSDKVersion
                    )
                    activeViewModel = vm
                    route = .form(form: match)
                } else {
                    if preselect != nil {
                        CommentRelayLoggerHolder.shared.log(level: .warning, message: "requested form not found in config; falling back to picker", error: nil)
                    }
                    route = .picker(forms: forms)
                }
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
        let attachments = vm.queuedAttachments()
        do {
            let outcome = try await client.submit(submission, attachments: attachments)
            // CRLBS-130: consume the preselect so an already-submitted form is
            // never auto-reopened (e.g. queued Done -> reload, or a .task re-run).
            submitted = true
            route = Self.route(for: outcome, hasUserIdentifier: configuration.userIdentifier != nil)
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
        case .unauthorized: return Strings.errorUnauthorized
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
    @State private var problems: [CommentRelaySubmissionProblem] = []
    @State private var selectedId: UUID? = nil
    @State private var serverFailed = false

    var body: some View {
        Group {
            if let history {
                VStack(spacing: 0) {
                    if serverFailed {
                        Text(Strings.problemHistoryUnavailable)
                            .font(.footnote).foregroundStyle(.secondary)
                            .padding(.horizontal)
                    }
                    HistoryListView(
                        history: history,
                        problems: problems,
                        onSelect: { entry in
                            let eid = entry.id
                            Task { @MainActor in selectedId = eid }
                        },
                        onRetry: { id in
                            await client.retrySubmission(id: id)
                            await refreshProblems()
                        },
                        // onRemove is sync (no spinner UX); spawn a Task so we can await the async client calls.
                        onRemove: { id in
                            Task {
                                await client.deleteProblemSubmission(id: id)
                                await refreshProblems()
                            }
                        }
                    )
                    .navigationDestination(item: $selectedId) { entryId in
                        if let entry = history.submissions.first(where: { $0.id == entryId }) {
                            HistoryDetailView(entry: entry)
                        }
                    }
                }
            } else {
                LoadingView(label: nil)
            }
        }
        .task { await load() }
    }

    @MainActor private func load() async {
        let isAnonymous = await client.configuration.userIdentifier == nil
        problems = await client.submissionProblems()
        // Render problems immediately while the server fetch is in flight —
        // offline is exactly when queued problems matter most. If history
        // resolves later it overwrites this synthesized empty value.
        if history == nil && !problems.isEmpty {
            history = CommentRelayHistory(isAnonymous: isAnonymous, submissions: [])
        }
        do {
            history = try await client.fetchHistory()
        } catch {
            CommentRelayLoggerHolder.shared.log(level: .error, message: "fetchHistory failed", error: error)
            serverFailed = true
            history = CommentRelayHistory(isAnonymous: isAnonymous, submissions: [])
        }
    }

    @MainActor private func refreshProblems() async { problems = await client.submissionProblems() }
}
