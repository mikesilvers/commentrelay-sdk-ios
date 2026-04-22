// Sources/CommentRelayCore/Internal/DraftStore.swift
import Foundation

public actor DraftStore {
    public struct Draft: Codable, Sendable, Equatable {
        public let formId: String
        public let fieldValues: [String: String]
        public let updatedAt: Date
        public init(formId: String, fieldValues: [String: String], updatedAt: Date) {
            self.formId = formId; self.fieldValues = fieldValues; self.updatedAt = updatedAt
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
        pending[draft.formId] = draft
        pendingTasks[draft.formId]?.cancel()
        let debounce = self.debounce
        let formId = draft.formId
        pendingTasks[formId] = Task { [weak self] in
            if debounce > 0 {
                try? await Task.sleep(nanoseconds: UInt64(debounce * 1_000_000_000))
            }
            guard let self, !Task.isCancelled else { return }
            await self.flush(formId: formId)
        }
    }

    func load(formId: String) -> Draft? {
        if let p = pending[formId] { return p }
        return peekOnDisk(formId: formId)
    }

    func peekOnDisk(formId: String) -> Draft? {
        guard let data = try? Data(contentsOf: url(for: formId)) else { return nil }
        return try? JSONDecoder().decode(Draft.self, from: data)
    }

    func delete(formId: String) {
        pending.removeValue(forKey: formId)
        pendingTasks[formId]?.cancel()
        pendingTasks.removeValue(forKey: formId)
        try? fm.removeItem(at: url(for: formId))
    }

    private func flush(formId: String) {
        guard let draft = pending[formId] else { return }
        if let data = try? JSONEncoder().encode(draft) {
            try? data.write(to: url(for: formId), options: .atomic)
        }
        pending.removeValue(forKey: formId)
        pendingTasks.removeValue(forKey: formId)
    }

    private func url(for formId: String) -> URL {
        directory.appendingPathComponent("\(formId).json")
    }
}

public typealias CommentRelayDraft = DraftStore.Draft
