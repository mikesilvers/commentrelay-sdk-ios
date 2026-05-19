// Tests/CommentRelayCoreTests/DraftAPITests.swift
import XCTest
@testable import CommentRelayCore

final class DraftAPITests: XCTestCase {
    private func makeClient() async throws -> CommentRelayClient {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("crl-draft-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let config = CommentRelayConfiguration(
            apiKey: "crk_test_abc",
            baseURL: URL(string: "http://localhost:3000")!,
            userIdentifier: "test-user")
        return CommentRelayClient(configuration: config, session: .shared, cacheDirectory: dir, keychainService: "crl.test.\(UUID().uuidString)")
    }

    func test_saveLoadDelete_roundTrip() async throws {
        let client = try await makeClient()
        await client.saveDraft(formId: "cat1", fieldValues: ["f1": "hello"])
        // DraftStore default debounce is 0.5s; wait long enough for the flush.
        try await Task.sleep(nanoseconds: 700_000_000)
        let loaded = await client.loadDraft(formId: "cat1")
        XCTAssertEqual(loaded?.fieldValues["f1"], "hello")

        await client.deleteDraft(formId: "cat1")
        let afterDelete = await client.loadDraft(formId: "cat1")
        XCTAssertNil(afterDelete)
    }
}
