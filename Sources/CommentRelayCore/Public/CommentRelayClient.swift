// Sources/CommentRelayCore/Public/CommentRelayClient.swift
import Foundation

public actor CommentRelayClient {
    public let configuration: CommentRelayConfiguration

    private let api: APIClient
    private let configCache: ConfigCache
    private let sessionStore: SessionStore
    private let draftStore: DraftStore
    private let submissionQueue: SubmissionQueue
    nonisolated(unsafe) private var uploadManager: BackgroundUploadManager!
    private(set) public var isEnabled: Bool = true

    /// Latest project-level attribution from the most recent successful config
    /// fetch (CRLBS-132). Defaults to hidden; retained across transport failures.
    private var latestAttribution: CommentRelayAttribution = .hidden

    // MARK: - Reachability / flush triggers

    private let reachability: Reachability
    nonisolated(unsafe) private var flushTriggerTask: Task<Void, Never>?

    nonisolated private func startFlushTriggers() {
        flushTriggerTask = Task { [weak self] in
            guard let stream = self?.reachability.changes else { return }  // subscribe FIRST (registers continuation, buffers events)
            await self?.flushQueue()                                       // init trigger (events during this are now buffered)
            for await connected in stream where connected {
                await self?.flushQueue()                                   // connectivity-restored trigger
            }
        }
    }

    deinit {
        flushTriggerTask?.cancel()
    }

    // MARK: - Flush reentrancy guard

    private var isFlushing = false

    // MARK: - Pending-count broadcaster

    private var pendingCountContinuations: [UUID: AsyncStream<Int>.Continuation] = [:]

    public var pendingSubmissionCount: Int {
        get async { await submissionQueue.retryingCount }
    }

    public func pendingSubmissionCountStream() -> AsyncStream<Int> {
        AsyncStream { continuation in
            let id = UUID()
            pendingCountContinuations[id] = continuation
            let queue = submissionQueue
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removePendingContinuation(id) }
            }
            Task { continuation.yield(await queue.retryingCount) }
        }
    }

    private func removePendingContinuation(_ id: UUID) {
        pendingCountContinuations[id] = nil
    }

    private func broadcastPendingCount() async {
        let n = await submissionQueue.retryingCount
        for c in pendingCountContinuations.values { c.yield(n) }
    }

    /// Persists a queue entry for a submission the server has *already accepted*
    /// (POST succeeded; `receipt` in hand) so the flush state machine resumes via
    /// finalize-first — no re-POST for the no-attachment path; attachments still
    /// re-POST for fresh presigned URLs by design (CRLBS-114 documented limitation).
    /// Then notifies pending-count observers. Returns the local id.
    /// Shared by the post-POST `.pause` (throws) and `.retry` (returns `.queued`)
    /// branches of `submit` so the two cannot drift.
    private func enqueueForResume(_ submission: CommentRelaySubmission,
                                  attachments: [CommentRelayQueuedAttachment],
                                  receipt: CommentRelaySubmissionReceipt) async throws -> UUID {
        let id = try await submissionQueue.enqueue(
            submission, attachments: attachments,
            serverSubmissionId: receipt.submissionId,
            startingPhase: receipt.hasUploads ? .needsUpload : .needsFinalize)
        await broadcastPendingCount()
        return id
    }

    // MARK: - Init

    public init(configuration: CommentRelayConfiguration, session: URLSession = .shared) {
        let fingerprint = Self.fingerprint(apiKey: configuration.apiKey)
        let dir = (try? ConfigCache.defaultDirectory(apiKeyFingerprint: fingerprint))
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("CommentRelay/\(fingerprint)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.configuration = configuration
        self.api = APIClient(baseURL: configuration.baseURL, apiKey: configuration.apiKey, session: session)
        self.configCache = ConfigCache(directory: dir)
        self.sessionStore = SessionStore(service: "com.commentrelay.sdk.\(fingerprint)", hostSupplied: configuration.userIdentifier)
        self.draftStore = DraftStore(directory: dir.appendingPathComponent("drafts"))
        self.submissionQueue = SubmissionQueue(directory: dir,
            maxEntries: configuration.maxQueuedSubmissions, maxAge: configuration.maxQueueAge)
        self.reachability = NetworkReachability()
        // Finalize closure weakly captures self so the manager doesn't retain the client indefinitely.
        let transport: UploadTransport = URLSessionUploadTransport(session: session)
        self.uploadManager = BackgroundUploadManager(transport: transport) { [weak self] submissionId in
            guard let self else { return }
            try await self.finalize(submissionId: submissionId)
        }
        startFlushTriggers()
    }

    /// Test-only: direct queue access for problem-visibility tests (CRLBS-121).
    var _testQueue: SubmissionQueue { submissionQueue }

    // Test-only escape hatch keeping the test suite hermetic.
    init(configuration: CommentRelayConfiguration,
         session: URLSession,
         cacheDirectory: URL,
         keychainService: String,
         reachability: Reachability = NetworkReachability()) {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        self.configuration = configuration
        self.api = APIClient(baseURL: configuration.baseURL, apiKey: configuration.apiKey, session: session)
        self.configCache = ConfigCache(directory: cacheDirectory)
        self.sessionStore = SessionStore(service: keychainService, hostSupplied: configuration.userIdentifier)
        self.draftStore = DraftStore(directory: cacheDirectory.appendingPathComponent("drafts"))
        self.submissionQueue = SubmissionQueue(directory: cacheDirectory,
            maxEntries: configuration.maxQueuedSubmissions, maxAge: configuration.maxQueueAge)
        self.reachability = reachability
        // Finalize closure weakly captures self so the manager doesn't retain the client indefinitely.
        let transport: UploadTransport = URLSessionUploadTransport(session: session)
        self.uploadManager = BackgroundUploadManager(transport: transport) { [weak self] submissionId in
            guard let self else { return }
            try await self.finalize(submissionId: submissionId)
        }
        startFlushTriggers()
    }

    // MARK: - Public API

    public func ping() async throws -> Bool {
        try ensureEnabled()
        return try await api.getHealth()
    }

    public func fetchConfig(cachedHash: String?) async throws -> CommentRelayConfigResponse {
        try ensureEnabled()
        let cached = await configCache.read()
        let effectiveHash: String? = cachedHash ?? cached?.hash
        let basePath = "sdk/v1/config"
        let queryItems: [URLQueryItem]? = effectiveHash.map { [URLQueryItem(name: "hash", value: $0)] }
        do {
            let decoded: DecodedConfigResponse = try await api.send(
                method: "GET", path: basePath, queryItems: queryItems,
                decodingAs: DecodedConfigResponse.self)
            let response = decoded.response
            latestAttribution = decoded.attribution
            if case .updated(let hash, let forms) = response {
                await configCache.write(hash: hash, forms: forms)
            }
            if case .current = response, let snap = cached {
                return .updated(hash: snap.hash, forms: snap.forms)
            }
            if case .current = response {
                CommentRelayLoggerHolder.shared.log(level: .error,
                    message: "config returned .current but no cached snapshot; returning empty/current (server/cache inconsistency)", error: nil)
            }
            return response
        } catch let err as CommentRelayError {
            if case .transport = err, let snap = cached {
                return .updated(hash: snap.hash, forms: snap.forms)
            }
            throw err
        }
    }

    /// The latest "Powered by CommentRelay" attribution state (CRLBS-132).
    /// Reflects the most recent config fetch; hidden until one succeeds.
    public func attribution() -> CommentRelayAttribution { latestAttribution }

    /// Cached-or-fresh forms accessor so the UI can render offline.
    public func effectiveConfig() async throws -> CommentRelayConfigResponse {
        try await fetchConfig(cachedHash: nil)
    }

    /// Resolves a feedback form by its title, matched case-insensitively, from
    /// the effective (cached-or-fresh) config. Only forms visible in the picker
    /// (`isActive && showInPicker`, i.e. `CommentRelayForm.isPickerVisible`) are
    /// eligible — a hidden or inactive form is never returned even by an exact
    /// name match, consistent with the drop-in UI's by-name behaviour
    /// (CRLBS-115/116). Returns `nil` when no visible form has that name.
    /// Offline-capable: resolves from cached config; throws only when there is
    /// no cache and the network is unavailable (same semantics as
    /// `effectiveConfig()`).
    public func form(named name: String) async throws -> CommentRelayForm? {
        let needle = name.lowercased()
        switch try await effectiveConfig() {
        case .updated(_, let forms):
            return forms.first { $0.isPickerVisible && $0.title.lowercased() == needle }
        case .current:
            return nil
        }
    }

    // MARK: - Submit (auto-queueing)

    /// Posts a submission to the server. Returns `.submitted` on success, or `.queued` if the
    /// network is unavailable and offline queueing is enabled. Throws on terminal errors.
    @discardableResult
    public func submit(_ submission: CommentRelaySubmission,
                       attachments: [CommentRelayQueuedAttachment] = []) async throws -> SubmitOutcome {
        try ensureEnabled()
        let receipt: CommentRelaySubmissionReceipt
        do {
            receipt = try await postSubmission(submission)
        } catch let err as CommentRelayError {
            switch RetryPolicy.classify(err) {
            case .terminal, .pause:
                throw err
            case .retry:
                guard configuration.offlineQueueingEnabled else { throw err }
                let id = try await submissionQueue.enqueue(submission, attachments: attachments)
                await broadcastPendingCount()
                return .queued(localId: id)
            }
        }
        // POST succeeded: the server now holds a record (receipt.submissionId).
        do {
            if receipt.hasUploads {
                var payloads: [CommentRelayFilePayload] = []
                for att in attachments {
                    guard let target = receipt.uploadUrls.first(where: {
                        $0.fieldId == att.fieldId && $0.fileName == att.fileName }) else { continue }
                    payloads.append(CommentRelayFilePayload(target: target, data: att.data, contentType: att.contentType))
                }
                try await uploadFiles(receipt: receipt, payloads: payloads)
            } else {
                try await finalize(submissionId: receipt.submissionId)
            }
            return .submitted(receipt)
        } catch let err as CommentRelayError {
            switch RetryPolicy.classify(err) {
            case .terminal:
                throw err
            case .pause:
                // 403 after a successful POST: still surface the error, but persist a
                // recoverable entry so reset()+flush finalizes the existing server record
                // via finalize-first instead of orphaning it (CRLBS-116). The circuit-breaker
                // is already engaged here — finalize()/uploadFiles() call disable() on
                // .forbidden before rethrowing — so no disable() is needed in this branch.
                if configuration.offlineQueueingEnabled {
                    _ = try await enqueueForResume(submission, attachments: attachments, receipt: receipt)
                }
                throw err
            case .retry:
                guard configuration.offlineQueueingEnabled else { throw err }
                let id = try await enqueueForResume(submission, attachments: attachments, receipt: receipt)
                return .queued(localId: id)
            }
        }
    }

    /// Called by `BackgroundUploadManager` when presigned URLs have expired (>15 min).
    /// Re-submits the same logical submission to obtain fresh upload URLs.
    public func resubmit(_ submission: CommentRelaySubmission) async throws -> CommentRelaySubmissionReceipt {
        try await postSubmission(submission)
    }

    public func finalize(submissionId: UUID) async throws {
        try ensureEnabled()
        struct FinalizeResponse: Decodable { let submissionId: UUID; let status: String }
        do {
            _ = try await api.send(
                method: "POST",
                path: "sdk/v1/submissions/\(submissionId.uuidString.lowercased())/finalize",
                body: Data("{}".utf8),
                decodingAs: FinalizeResponse.self)
        } catch let err as CommentRelayError {
            if case .conflict = err { return }   // already finalized is idempotent
            if case .forbidden = err { disable() }
            throw err
        }
    }

    public func uploadFiles(receipt: CommentRelaySubmissionReceipt,
                            payloads: [CommentRelayFilePayload]) async throws {
        try ensureEnabled()
        guard receipt.hasUploads else { return }
        let internalPayloads = payloads.map {
            BackgroundUploadManager.Payload(submissionId: receipt.submissionId,
                                            target: $0.target,
                                            data: $0.data,
                                            contentType: $0.contentType)
        }
        do {
            try await uploadManager.enqueue(internalPayloads)
        } catch let err as CommentRelayError {
            if case .forbidden = err { disable() }
            throw err
        }
    }

    public func fetchHistory() async throws -> CommentRelayHistory {
        try ensureEnabled()
        let effective = sessionStore.effectiveIdentifier
        do {
            return try await api.send(
                method: "GET",
                path: "sdk/v1/history",
                userIdentifier: effective,
                decodingAs: CommentRelayHistory.self)
        } catch let err as CommentRelayError {
            if case .forbidden = err { disable() }
            throw err
        }
    }

    public func reset() {
        isEnabled = true
    }

    public func saveDraft(formId: String, fieldValues: [String: String]) async {
        let draft = CommentRelayDraft(formId: formId, fieldValues: fieldValues, updatedAt: Date())
        await draftStore.save(draft)
    }

    public func loadDraft(formId: String) async -> CommentRelayDraft? {
        await draftStore.load(formId: formId)
    }

    public func deleteDraft(formId: String) async {
        await draftStore.delete(formId: formId)
    }

    // MARK: - Problem visibility (CRLBS-121)

    /// Submissions that did not deliver — still queued for retry or terminally failed (CRLBS-121).
    /// Returned sorted by creation date, most-recent first.
    public func submissionProblems() async -> [CommentRelaySubmissionProblem] {
        await submissionQueue.loadAll().map { e in
            CommentRelaySubmissionProblem(
                id: e.localId,
                formId: e.submission.formId,
                createdAt: e.createdAt,
                kind: e.failedAt == nil ? .queuedRetrying : .failed,
                category: .init(token: e.errorCategory),
                technicalDetail: e.lastError ?? "",
                attemptCount: e.attemptCount,
                lastAttemptAt: e.lastAttemptAt)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    /// Re-enables a problem entry for immediate delivery. No-op if it no longer exists.
    public func retrySubmission(id: UUID) async {
        guard var e = await submissionQueue.loadAll().first(where: { $0.localId == id }) else { return }
        e.failedAt = nil
        e.nextEarliestAttempt = nil
        do {
            try await submissionQueue.persist(e)
        } catch {
            CommentRelayLoggerHolder.shared.log(level: .error,
                message: "retrySubmission: failed to persist re-enabled queue entry", error: error)
            return
        }
        await broadcastPendingCount()
        await flushQueue()
    }

    /// Removes a problem entry — whether still retrying or terminally failed —
    /// along with any attachment sidecars. No-op if the entry no longer exists.
    public func deleteProblemSubmission(id: UUID) async {
        await submissionQueue.delete(localId: id)
        await broadcastPendingCount()
    }

    // MARK: - Queue flush

    public func flushQueue() async {
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }
        await submissionQueue.pruneExpired()
        guard isEnabled else {
            await broadcastPendingCount()
            return     // 403 pause: retain entries, do nothing
        }
        let entries = await submissionQueue.loadAll()   // FIFO
        let now = Date()
        for var entry in entries {
            if entry.failedAt != nil { continue }           // terminally failed: skip until user retries
            if let next = entry.nextEarliestAttempt, next > now { continue }
            do {
                try await advance(&entry)
            } catch let err as CommentRelayError {
                switch RetryPolicy.classify(err) {
                case .pause:
                    await broadcastPendingCount()
                    return                                  // circuit-breaker already engaged by callee
                case .terminal:
                    await submissionQueue.markFailed(
                        localId: entry.localId,
                        category: CommentRelaySubmissionProblem.Category(err).rawValue,
                        detail: "\(err)")
                    CommentRelayLoggerHolder.shared.log(level: .error,
                        message: "queued submission failed (terminal, retained for History)", error: err)
                    await broadcastPendingCount()
                case .retry(let retryAfter):
                    entry.attemptCount += 1
                    entry.lastError = "\(err)"
                    entry.errorCategory = CommentRelaySubmissionProblem.Category(err).rawValue
                    entry.lastAttemptAt = now
                    entry.nextEarliestAttempt = now.addingTimeInterval(
                        RetryPolicy.backoff(attempt: entry.attemptCount, retryAfter: retryAfter))
                    try? await submissionQueue.persist(entry)
                }
            } catch {
                entry.attemptCount += 1
                entry.lastError = "\(error)"
                entry.lastAttemptAt = now
                entry.errorCategory = CommentRelaySubmissionProblem.Category.unknown.rawValue
                entry.nextEarliestAttempt = now.addingTimeInterval(
                    RetryPolicy.backoff(attempt: entry.attemptCount, retryAfter: nil))
                try? await submissionQueue.persist(entry)
            }
        }
        await broadcastPendingCount()
    }

    /// One entry, finalize-first. Throws CommentRelayError on failure (router in flushQueue handles it).
    private func advance(_ entry: inout QueuedSubmission) async throws {
        // Finalize-first resume: a prior crash after POST must not create a duplicate.
        if let serverId = entry.serverSubmissionId, entry.phase == .needsFinalize {
            try await finalize(submissionId: serverId)            // .conflict treated as success inside finalize
            await submissionQueue.delete(localId: entry.localId)
            return
        }
        switch entry.phase {
        case .needsSubmit:
            let receipt = try await postSubmission(entry.submission)
            entry.serverSubmissionId = receipt.submissionId
            entry.phase = entry.attachments.isEmpty ? .needsFinalize : .needsUpload
            try await submissionQueue.persist(entry)
            try await advance(&entry)                              // continue same pass
        case .needsUpload:
            guard entry.serverSubmissionId != nil else {
                entry.phase = .needsSubmit
                try await submissionQueue.persist(entry)
                try await advance(&entry); return
            }
            // Re-POST to get fresh presigned URLs (never cached), then PUT sidecars.
            let receipt = try await postSubmission(entry.submission)
            entry.serverSubmissionId = receipt.submissionId
            var payloads: [CommentRelayFilePayload] = []
            for ref in entry.attachments {
                guard let target = receipt.uploadUrls.first(where: { $0.fieldId == ref.fieldId && $0.fileName == ref.fileName }),
                      let data = await submissionQueue.readSidecar(localId: entry.localId, fileName: ref.fileName)
                else { continue }
                payloads.append(CommentRelayFilePayload(target: target, data: data, contentType: ref.contentType))
            }
            try await uploadFiles(receipt: receipt, payloads: payloads)
            entry.phase = .needsFinalize
            try await submissionQueue.persist(entry)
            try await advance(&entry)
        case .needsFinalize:
            if let serverId = entry.serverSubmissionId {
                try await finalize(submissionId: serverId)
            } else {
                CommentRelayLoggerHolder.shared.log(level: .error,
                    message: "queued entry in needsFinalize without serverSubmissionId; dropping", error: nil)
            }
            await submissionQueue.delete(localId: entry.localId)
        case .done:
            await submissionQueue.delete(localId: entry.localId)
        }
    }

    // MARK: - Private network helpers

    /// Raw network POST for a submission. Returns the server receipt (with upload URLs if any).
    private func postSubmission(_ submission: CommentRelaySubmission) async throws -> CommentRelaySubmissionReceipt {
        try ensureEnabled()
        let encoder = APIClient.defaultEncoder()
        let body = try encoder.encode(submission)
        do {
            return try await api.send(
                method: "POST",
                path: "sdk/v1/submissions",
                body: body,
                userIdentifier: submission.userIdentifier,
                decodingAs: CommentRelaySubmissionReceipt.self)
        } catch let err as CommentRelayError {
            if case .forbidden = err { disable() }
            throw err
        }
    }

    // MARK: - Internal helpers

    private func ensureEnabled() throws {
        if !isEnabled {
            throw CommentRelayError.forbidden(message: "client disabled after 403 — call reset()")
        }
    }

    @inline(__always)
    fileprivate func disable() { isEnabled = false }

    private static func fingerprint(apiKey: String) -> String {
        let digest = apiKey.unicodeScalars.reduce(into: UInt64(5381)) { acc, scalar in
            acc = (acc &* 33) &+ UInt64(scalar.value)
        }
        return String(digest, radix: 16)
    }
}
