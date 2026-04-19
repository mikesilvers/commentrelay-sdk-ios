// Tests/CommentRelayCoreTests/DraftStoreTests.swift
import XCTest
@testable import CommentRelayCore

final class DraftStoreTests: XCTestCase {
    private var tempDir: URL!
    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("crl-draft-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: tempDir) }

    func test_saveLoad_roundTrip() async throws {
        let store = DraftStore(directory: tempDir, debounce: 0)
        let draft = DraftStore.Draft(categoryId: "cat1", fieldValues: ["f1": "hello"], updatedAt: Date())
        await store.save(draft)
        try await Task.sleep(nanoseconds: 50_000_000)
        let loaded = await store.load(categoryId: "cat1")
        XCTAssertEqual(loaded?.fieldValues["f1"], "hello")
    }

    func test_debounce_coalescesRapidWrites() async throws {
        let store = DraftStore(directory: tempDir, debounce: 0.2)
        for i in 0..<5 {
            await store.save(.init(categoryId: "cat1", fieldValues: ["f": "\(i)"], updatedAt: Date()))
        }
        // not yet written to disk
        let beforeFlush = await store.peekOnDisk(categoryId: "cat1")?.fieldValues["f"]
        XCTAssertNil(beforeFlush)
        try await Task.sleep(nanoseconds: 400_000_000)
        let afterFlush = await store.peekOnDisk(categoryId: "cat1")?.fieldValues["f"]
        XCTAssertEqual(afterFlush, "4")
    }

    func test_delete_removesDraft() async throws {
        let store = DraftStore(directory: tempDir, debounce: 0)
        await store.save(.init(categoryId: "cat1", fieldValues: ["f": "x"], updatedAt: Date()))
        try await Task.sleep(nanoseconds: 50_000_000)
        await store.delete(categoryId: "cat1")
        let afterDelete = await store.load(categoryId: "cat1")
        XCTAssertNil(afterDelete)
    }
}
