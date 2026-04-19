import XCTest
@testable import CommentRelayCore

final class ConfigCacheTests: XCTestCase {
    private var tempDir: URL!
    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("crl-cache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: tempDir) }

    func test_emptyOnFirstRead() async {
        let cache = ConfigCache(directory: tempDir)
        let snap = await cache.read()
        XCTAssertNil(snap)
    }

    func test_writeThenReadRoundTrip() async throws {
        let cache = ConfigCache(directory: tempDir)
        let cat = CommentRelayCategory(id: "c1", title: "Bug", showInPicker: true, responseLimitCount: nil, responseLimitType: nil, responseLimitWindowDays: nil, moreFeedbackPrompt: nil, isActive: true, sortOrder: 1, fields: [])
        await cache.write(hash: "abc", categories: [cat])
        let snap = await cache.read()
        XCTAssertNotNil(snap)
        XCTAssertEqual(snap?.hash, "abc")
        XCTAssertEqual(snap?.categories.first?.id, "c1")
    }

    func test_survivesNewInstance() async throws {
        let cacheA = ConfigCache(directory: tempDir)
        await cacheA.write(hash: "h1", categories: [])
        let cacheB = ConfigCache(directory: tempDir)
        let snap = await cacheB.read()
        XCTAssertNotNil(snap)
        XCTAssertEqual(snap?.hash, "h1")
    }
}
