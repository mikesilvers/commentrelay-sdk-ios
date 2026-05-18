import Foundation

actor SubmissionQueue {
    private let root: URL          // <dir>/queue
    private let maxEntries: Int
    private let maxAge: TimeInterval
    private let fm = FileManager.default

    init(directory: URL, maxEntries: Int, maxAge: TimeInterval) {
        self.root = directory.appendingPathComponent("queue")
        self.maxEntries = maxEntries
        self.maxAge = maxAge
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func entryDir(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString) }

    /// Rejects any attachment fileName that contains a path separator or normalizes differently
    /// than its bare form. Empty names and the special components "." and ".." are also rejected.
    private func safeSidecarName(_ raw: String) throws -> String {
        let bare = (raw as NSString).lastPathComponent
        guard bare == raw, !bare.isEmpty, bare != ".", bare != ".." else {
            throw CommentRelayError.badRequest(message: "invalid attachment file name: \(raw)")
        }
        return bare
    }

    // MARK: - Attachment caps (Task 5)

    static let allowedMIME: Set<String> = [
        "image/jpeg", "image/png", "image/heic", "image/heif", "image/webp",
        "application/pdf", "text/plain"
    ]

    private func validate(_ attachments: [CommentRelayQueuedAttachment]) throws {
        for a in attachments {
            if a.data.count > 10_000_000 {
                throw CommentRelayError.badRequest(message: "attachment \(a.fileName) exceeds 10MB")
            }
            if !Self.allowedMIME.contains(a.contentType) {
                throw CommentRelayError.badRequest(message: "attachment type \(a.contentType) not allowed")
            }
        }
        let byField = Dictionary(grouping: attachments, by: \.fieldId)
        for (field, group) in byField where group.count > 3 {
            throw CommentRelayError.badRequest(message: "field \(field) exceeds 3 files")
        }
    }

    private func evictIfNeeded() {
        var entries = loadAll() // FIFO (oldest first)
        while entries.count > maxEntries {
            delete(localId: entries.removeFirst().localId)
        }
    }

    func pruneExpired() {
        let cutoff = Date().addingTimeInterval(-maxAge)
        for e in loadAll() where e.createdAt < cutoff { delete(localId: e.localId) }
    }

    /// Persists entry.json + one sidecar per attachment. Validates size/MIME/per-field caps first.
    func enqueue(_ submission: CommentRelaySubmission,
                 attachments: [CommentRelayQueuedAttachment]) throws -> UUID {
        // --- Cap validation: size, MIME type, per-field count ---
        try validate(attachments)

        // --- Validate ALL attachment names up front before writing anything ---
        let safeNames = try attachments.map { try safeSidecarName($0.fileName) }
        if Set(safeNames).count != safeNames.count {
            throw CommentRelayError.badRequest(message: "duplicate attachment file name")
        }

        let id = UUID()
        let dir = entryDir(id)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for (att, safeName) in zip(attachments, safeNames) {
            try att.data.write(to: dir.appendingPathComponent(safeName), options: .atomic)
        }
        let refs = zip(attachments, safeNames).map { att, safeName in
            QueuedFileRef(fieldId: att.fieldId, fileName: safeName,
                          contentType: att.contentType, size: att.data.count)
        }
        let entry = QueuedSubmission(
            localId: id, submission: submission,
            phase: .needsSubmit,
            serverSubmissionId: nil, attachments: refs,
            attemptCount: 0, nextEarliestAttempt: nil, createdAt: Date(), lastError: nil)
        try persist(entry)
        evictIfNeeded()
        return id
    }

    func persist(_ entry: QueuedSubmission) throws {
        let data = try JSONEncoder().encode(entry)
        try data.write(to: entryDir(entry.localId).appendingPathComponent("entry.json"), options: .atomic)
    }

    func loadAll() -> [QueuedSubmission] {
        guard let dirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        let entries = dirs.compactMap { d -> QueuedSubmission? in
            guard let data = try? Data(contentsOf: d.appendingPathComponent("entry.json")) else { return nil }
            return try? JSONDecoder().decode(QueuedSubmission.self, from: data)
        }
        return entries.sorted { $0.createdAt < $1.createdAt }
    }

    func delete(localId: UUID) {
        try? fm.removeItem(at: entryDir(localId))
    }

    func readSidecar(localId: UUID, fileName: String) -> Data? {
        try? Data(contentsOf: entryDir(localId).appendingPathComponent(fileName))
    }

    var count: Int { loadAll().count }
}
