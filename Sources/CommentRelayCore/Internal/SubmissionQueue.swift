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

    /// Caps enforced by the caller (Task 5). Persists entry.json + one sidecar per attachment.
    func enqueue(_ submission: CommentRelaySubmission,
                 attachments: [CommentRelayQueuedAttachment]) throws -> UUID {
        let id = UUID()
        let dir = entryDir(id)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for att in attachments {
            try att.data.write(to: dir.appendingPathComponent(att.fileName), options: .atomic)
        }
        let refs = attachments.map {
            QueuedFileRef(fieldId: $0.fieldId, fileName: $0.fileName,
                          contentType: $0.contentType, size: $0.data.count)
        }
        let entry = QueuedSubmission(
            localId: id, submission: submission,
            phase: .needsSubmit,
            serverSubmissionId: nil, attachments: refs,
            attemptCount: 0, nextEarliestAttempt: nil, createdAt: Date(), lastError: nil)
        try persist(entry)
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
