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

    // MARK: - Pending-count broadcaster

    private var pendingCountContinuations: [UUID: AsyncStream<Int>.Continuation] = [:]

    public var pendingSubmissionCount: Int {
        get async { await submissionQueue.count }
    }

    public func pendingSubmissionCountStream() -> AsyncStream<Int> {
        AsyncStream { continuation in
            let id = UUID()
            pendingCountContinuations[id] = continuation
            let queue = submissionQueue
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removePendingContinuation(id) }
            }
            Task { continuation.yield(await queue.count) }
        }
    }

    private func removePendingContinuation(_ id: UUID) {
        pendingCountContinuations[id] = nil
    }

    private func broadcastPendingCount() async {
        let n = await submissionQueue.count
        for c in pendingCountContinuations.values { c.yield(n) }
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
        // Finalize closure weakly captures self so the manager doesn't retain the client indefinitely.
        let transport: UploadTransport = URLSessionUploadTransport(session: session)
        self.uploadManager = BackgroundUploadManager(transport: transport) { [weak self] submissionId in
            guard let self else { return }
            try await self.finalize(submissionId: submissionId)
        }
    }

    // Test-only escape hatch keeping the test suite hermetic.
    init(configuration: CommentRelayConfiguration,
         session: URLSession,
         cacheDirectory: URL,
         keychainService: String) {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        self.configuration = configuration
        self.api = APIClient(baseURL: configuration.baseURL, apiKey: configuration.apiKey, session: session)
        self.configCache = ConfigCache(directory: cacheDirectory)
        self.sessionStore = SessionStore(service: keychainService, hostSupplied: configuration.userIdentifier)
        self.draftStore = DraftStore(directory: cacheDirectory.appendingPathComponent("drafts"))
        self.submissionQueue = SubmissionQueue(directory: cacheDirectory,
            maxEntries: configuration.maxQueuedSubmissions, maxAge: configuration.maxQueueAge)
        // Finalize closure weakly captures self so the manager doesn't retain the client indefinitely.
        let transport: UploadTransport = URLSessionUploadTransport(session: session)
        self.uploadManager = BackgroundUploadManager(transport: transport) { [weak self] submissionId in
            guard let self else { return }
            try await self.finalize(submissionId: submissionId)
        }
    }

    // MARK: - Public API

    public func ping() async throws -> Bool {
        try ensureEnabled()
        return try await api.getHealth()
    }

    public func fetchConfig(cachedHash: String?) async throws -> CommentRelayConfigResponse {
        try ensureEnabled()
        let basePath = "sdk/v1/config"
        let queryItems: [URLQueryItem]? = cachedHash.map { [URLQueryItem(name: "hash", value: $0)] }
        let response: CommentRelayConfigResponse = try await api.send(
            method: "GET", path: basePath, queryItems: queryItems, decodingAs: CommentRelayConfigResponse.self)
        if case .updated(let hash, let forms) = response {
            await configCache.write(hash: hash, forms: forms)
        }
        return response
    }

    // MARK: - Submit (auto-queueing)

    /// Posts a submission to the server. Returns `.submitted` on success, or `.queued` if the
    /// network is unavailable and offline queueing is enabled. Throws on terminal errors.
    @discardableResult
    public func submit(_ submission: CommentRelaySubmission,
                       attachments: [CommentRelayQueuedAttachment] = []) async throws -> SubmitOutcome {
        try ensureEnabled()
        do {
            let receipt = try await postSubmission(submission)
            if receipt.hasUploads {
                let payloads = attachments.compactMap { att -> CommentRelayFilePayload? in
                    guard let target = receipt.uploadUrls.first(where: {
                        $0.fieldId == att.fieldId && $0.fileName == att.fileName }) else { return nil }
                    return CommentRelayFilePayload(target: target, data: att.data, contentType: att.contentType)
                }
                try await uploadFiles(receipt: receipt, payloads: payloads)
            } else {
                try await finalize(submissionId: receipt.submissionId)
            }
            return .submitted(receipt)
        } catch let err as CommentRelayError {
            switch RetryPolicy.classify(err) {
            case .terminal, .pause:
                throw err                              // terminal still throws; 403 already disabled via existing paths
            case .retry:
                guard configuration.offlineQueueingEnabled else { throw err }
                let id = try await submissionQueue.enqueue(submission, attachments: attachments)
                await broadcastPendingCount()
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

    // MARK: - Queue flush

    public func flushQueue() async {
        await submissionQueue.pruneExpired()
        guard isEnabled else { return }     // 403 pause: retain entries, do nothing
        let entries = await submissionQueue.loadAll()   // FIFO
        let now = Date()
        for var entry in entries {
            if let next = entry.nextEarliestAttempt, next > now { continue }
            do {
                try await advance(&entry)
            } catch let err as CommentRelayError {
                switch RetryPolicy.classify(err) {
                case .pause:
                    return                                  // circuit-breaker already engaged by callee
                case .terminal:
                    await submissionQueue.delete(localId: entry.localId)
                    CommentRelayLoggerHolder.shared.log(level: .error,
                        message: "queued submission dropped (terminal)", error: err)
                case .retry(let retryAfter):
                    entry.attemptCount += 1
                    entry.lastError = "\(err)"
                    entry.nextEarliestAttempt = now.addingTimeInterval(
                        RetryPolicy.backoff(attempt: entry.attemptCount, retryAfter: retryAfter))
                    try? await submissionQueue.persist(entry)
                }
            } catch {
                entry.attemptCount += 1
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
