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

    // MARK: - Security / correctness (Task 4)

    func testRejectsAttachmentWithPathSeparatorInName() async throws {
        let dir = tmp()
        let q = SubmissionQueue(directory: dir, maxEntries: 50, maxAge: 9_999_999)

        // Case 1: parent-directory traversal
        let traversal = CommentRelayQueuedAttachment(fieldId: "1", fileName: "../escape.bin",
                                                     contentType: "application/octet-stream",
                                                     data: Data([0xFF]))
        do {
            _ = try await q.enqueue(sub(), attachments: [traversal])
            XCTFail("Expected badRequest for traversal fileName, but enqueue succeeded")
        } catch CommentRelayError.badRequest {
            // correct
        }
        // The traversal target must not exist
        let escapedFile = dir.appendingPathComponent("queue/escape.bin")
        XCTAssertFalse(FileManager.default.fileExists(atPath: escapedFile.path),
                       "Traversal must not have written outside the entry dir")

        // Case 2: embedded forward slash
        let slashed = CommentRelayQueuedAttachment(fieldId: "1", fileName: "a/b.bin",
                                                   contentType: "application/octet-stream",
                                                   data: Data([0xAB]))
        do {
            _ = try await q.enqueue(sub(), attachments: [slashed])
            XCTFail("Expected badRequest for slashed fileName, but enqueue succeeded")
        } catch CommentRelayError.badRequest {
            // correct
        }
    }

    func testRejectsDuplicateSidecarFileNames() async throws {
        let dir = tmp()
        let q = SubmissionQueue(directory: dir, maxEntries: 50, maxAge: 9_999_999)
        let att1 = CommentRelayQueuedAttachment(fieldId: "f1", fileName: "dup.bin",
                                                contentType: "application/octet-stream",
                                                data: Data([0x01]))
        let att2 = CommentRelayQueuedAttachment(fieldId: "f2", fileName: "dup.bin",
                                                contentType: "application/octet-stream",
                                                data: Data([0x02]))
        do {
            _ = try await q.enqueue(sub(), attachments: [att1, att2])
            XCTFail("Expected badRequest for duplicate fileName, but enqueue succeeded")
        } catch CommentRelayError.badRequest {
            // correct
        }
        // No partial entry dir should remain and loadAll should be empty
        let all = await q.loadAll()
        XCTAssertTrue(all.isEmpty, "No entry should be persisted after a validation failure")
        let queueDir = dir.appendingPathComponent("queue")
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: queueDir.path)) ?? []
        XCTAssertTrue(contents.isEmpty, "Entry folder must not remain after rejected enqueue")
    }

    func testAcceptsPlainFileName() async throws {
        let dir = tmp()
        let q = SubmissionQueue(directory: dir, maxEntries: 50, maxAge: 9_999_999)
        let att = CommentRelayQueuedAttachment(fieldId: "3", fileName: "photo.jpg",
                                               contentType: "image/jpeg",
                                               data: Data([0xDE, 0xAD]))
        let id = try await q.enqueue(sub(), attachments: [att])
        let bytes = await q.readSidecar(localId: id, fileName: "photo.jpg")
        XCTAssertEqual(bytes, Data([0xDE, 0xAD]),
                       "Plain fileName must be accepted and sidecar must be readable")
    }
}
