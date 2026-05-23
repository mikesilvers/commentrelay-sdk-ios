import Foundation

actor ConfigCache {
    struct Snapshot: Codable, Sendable {
        let schemaVersion: Int
        let hash: String
        let forms: [CommentRelayForm]
    }

    /// Bump whenever the cached form shape changes (e.g. a new CommentRelayForm
    /// field). Existing installs then discard their stale cache and refetch,
    /// instead of serving forms that lack the new field. (CRLBS-128.)
    private static let currentSchemaVersion = 1

    private let fileURL: URL
    private let fm = FileManager.default

    init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("config.json")
    }

    /// Defaults to `Application Support/CommentRelay/`.
    static func defaultDirectory(apiKeyFingerprint: String) throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory,
                                               in: .userDomainMask,
                                               appropriateFor: nil,
                                               create: true)
        let dir = base.appendingPathComponent("CommentRelay").appendingPathComponent(apiKeyFingerprint)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func read() -> Snapshot? {
        guard let data = try? Data(contentsOf: fileURL),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data),
              snap.schemaVersion == Self.currentSchemaVersion else { return nil }
        return snap
    }

    func write(hash: String, forms: [CommentRelayForm]) {
        let snap = Snapshot(schemaVersion: Self.currentSchemaVersion, hash: hash, forms: forms)
        guard let data = try? JSONEncoder().encode(snap) else { return }
        try? fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    func clear() {
        try? fm.removeItem(at: fileURL)
    }
}
