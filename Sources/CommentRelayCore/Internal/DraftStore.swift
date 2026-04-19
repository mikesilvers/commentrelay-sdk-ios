// Sources/CommentRelayCore/Internal/DraftStore.swift
import Foundation

actor DraftStore {
    public struct Draft: Codable, Sendable, Equatable {
        public let categoryId: String
        public let fieldValues: [String: String]
        public let updatedAt: Date
        public init(categoryId: String, fieldValues: [String: String], updatedAt: Date) {
            self.categoryId = categoryId; self.fieldValues = fieldValues; self.updatedAt = updatedAt
        }
    }

    private let directory: URL
    private let debounce: TimeInterval
    private var pending: [String: Draft] = [:]
    private var pendingTasks: [String: Task<Void, Never>] = [:]
    private let fm = FileManager.default

    init(directory: URL, debounce: TimeInterval = 0.5) {
        self.directory = directory
        self.debounce = debounce
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func save(_ draft: Draft) {
        pending[draft.categoryId] = draft
        pendingTasks[draft.categoryId]?.cancel()
        let debounce = self.debounce
        let categoryId = draft.categoryId
        pendingTasks[categoryId] = Task { [weak self] in
            if debounce > 0 {
                try? await Task.sleep(nanoseconds: UInt64(debounce * 1_000_000_000))
            }
            guard let self, !Task.isCancelled else { return }
            await self.flush(categoryId: categoryId)
        }
    }

    func load(categoryId: String) -> Draft? {
        if let p = pending[categoryId] { return p }
        return peekOnDisk(categoryId: categoryId)
    }

    func peekOnDisk(categoryId: String) -> Draft? {
        guard let data = try? Data(contentsOf: url(for: categoryId)) else { return nil }
        return try? JSONDecoder().decode(Draft.self, from: data)
    }

    func delete(categoryId: String) {
        pending.removeValue(forKey: categoryId)
        pendingTasks[categoryId]?.cancel()
        pendingTasks.removeValue(forKey: categoryId)
        try? fm.removeItem(at: url(for: categoryId))
    }

    private func flush(categoryId: String) {
        guard let draft = pending[categoryId] else { return }
        if let data = try? JSONEncoder().encode(draft) {
            try? data.write(to: url(for: categoryId), options: .atomic)
        }
        pending.removeValue(forKey: categoryId)
        pendingTasks.removeValue(forKey: categoryId)
    }

    private func url(for categoryId: String) -> URL {
        directory.appendingPathComponent("\(categoryId).json")
    }
}
