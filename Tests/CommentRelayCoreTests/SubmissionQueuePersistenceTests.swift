import XCTest
@testable import CommentRelayCore

final class SubmissionQueuePersistenceTests: XCTestCase {
    private func tmp() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("crq-\(UUID())")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    private func sub(_ form: String = "f") -> CommentRelaySubmission {
        CommentRelaySubmission(formId: form, userIdentifier: "u", platform: .ios,
            fields: [.text(fieldId: "1", value: "hi")], osVersion: nil, deviceModel: nil,
            appVersion: nil, sdkVersion: nil, locale: nil, contactPreference: nil,
            contactDetails: nil, sessionId: nil)
    }

    func testEnqueuePersistsEntryAndSidecar() async throws {
        let dir = tmp()
        let q = SubmissionQueue(directory: dir, maxEntries: 50, maxAge: 9_999_999)
        let att = CommentRelayQueuedAttachment(fieldId: "2", fileName: "a.bin",
                                               contentType: "application/pdf", data: Data([1,2,3]))
        let id = try await q.enqueue(sub(), attachments: [att])
        let entryURL = dir.appendingPathComponent("queue/\(id)/entry.json")
        let sidecarURL = dir.appendingPathComponent("queue/\(id)/a.bin")
        XCTAssertTrue(FileManager.default.fileExists(atPath: entryURL.path))
        XCTAssertEqual(try Data(contentsOf: sidecarURL), Data([1,2,3]))
    }

    func testLoadAllReturnsFIFOByCreatedAt() async throws {
        let dir = tmp()
        let q = SubmissionQueue(directory: dir, maxEntries: 50, maxAge: 9_999_999)
        let a = try await q.enqueue(sub("a"), attachments: [])
        try await Task.sleep(nanoseconds: 10_000_000)
        let b = try await q.enqueue(sub("b"), attachments: [])
        let all = await q.loadAll()
        XCTAssertEqual(all.map(\.localId), [a, b])
    }

    func testDeleteRemovesFolder() async throws {
        let dir = tmp()
        let q = SubmissionQueue(directory: dir, maxEntries: 50, maxAge: 9_999_999)
        let id = try await q.enqueue(sub(), attachments: [])
        await q.delete(localId: id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("queue/\(id)").path))
    }

    func testReadSidecarReturnsBytes() async throws {
        let dir = tmp()
        let q = SubmissionQueue(directory: dir, maxEntries: 50, maxAge: 9_999_999)
        let att = CommentRelayQueuedAttachment(fieldId: "2", fileName: "x.txt",
                                               contentType: "text/plain", data: Data("hey".utf8))
        let id = try await q.enqueue(sub(), attachments: [att])
        let bytes = await q.readSidecar(localId: id, fileName: "x.txt")
        XCTAssertEqual(bytes, Data("hey".utf8))
    }
}
