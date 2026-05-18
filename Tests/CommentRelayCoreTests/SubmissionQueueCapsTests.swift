import XCTest
@testable import CommentRelayCore

final class SubmissionQueueCapsTests: XCTestCase {
    private func tmp() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("crqc-\(UUID())")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true); return u
    }
    private func sub() -> CommentRelaySubmission {
        CommentRelaySubmission(formId: "f", userIdentifier: "u", platform: .ios,
            fields: [.text(fieldId: "1", value: "hi")], osVersion: nil, deviceModel: nil,
            appVersion: nil, sdkVersion: nil, locale: nil, contactPreference: nil,
            contactDetails: nil, sessionId: nil)
    }

    func testRejectsOversizeFile() async {
        let q = SubmissionQueue(directory: tmp(), maxEntries: 50, maxAge: 9_999_999)
        let big = CommentRelayQueuedAttachment(fieldId: "2", fileName: "b",
            contentType: "image/png", data: Data(count: 10_000_001))
        do { _ = try await q.enqueue(sub(), attachments: [big]); XCTFail("should reject") }
        catch let e as CommentRelayError { guard case .badRequest = e else { return XCTFail("wrong: \(e)") } }
        catch { XCTFail("wrong error type") }
    }

    func testRejectsDisallowedMIME() async {
        let q = SubmissionQueue(directory: tmp(), maxEntries: 50, maxAge: 9_999_999)
        let bad = CommentRelayQueuedAttachment(fieldId: "2", fileName: "b",
            contentType: "application/zip", data: Data([1]))
        do { _ = try await q.enqueue(sub(), attachments: [bad]); XCTFail("should reject") }
        catch let e as CommentRelayError { guard case .badRequest = e else { return XCTFail("wrong: \(e)") } }
        catch { XCTFail("wrong error type") }
    }

    func testRejectsMoreThan3FilesPerField() async {
        let q = SubmissionQueue(directory: tmp(), maxEntries: 50, maxAge: 9_999_999)
        let atts = (0..<4).map { CommentRelayQueuedAttachment(fieldId: "2", fileName: "f\($0)",
            contentType: "image/png", data: Data([1])) }
        do { _ = try await q.enqueue(sub(), attachments: atts); XCTFail("should reject") }
        catch let e as CommentRelayError { guard case .badRequest = e else { return XCTFail("wrong: \(e)") } }
        catch { XCTFail("wrong error type") }
    }

    func testEvictsOldestWhenOverCapacity() async throws {
        let dir = tmp()
        let q = SubmissionQueue(directory: dir, maxEntries: 2, maxAge: 9_999_999)
        let a = try await q.enqueue(sub(), attachments: []); try await Task.sleep(nanoseconds: 5_000_000)
        _ = try await q.enqueue(sub(), attachments: []); try await Task.sleep(nanoseconds: 5_000_000)
        _ = try await q.enqueue(sub(), attachments: [])
        let all = await q.loadAll()
        XCTAssertEqual(all.count, 2)
        XCTAssertFalse(all.map(\.localId).contains(a)) // oldest evicted
    }

    func testPruneAgedOut() async throws {
        let dir = tmp()
        let q = SubmissionQueue(directory: dir, maxEntries: 50, maxAge: 0) // everything immediately aged
        _ = try await q.enqueue(sub(), attachments: [])
        await q.pruneExpired()
        let all = await q.loadAll()
        XCTAssertTrue(all.isEmpty)
    }
}
