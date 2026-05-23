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
        let form = CommentRelayForm(id: "f1", title: "Bug", clientFormId: nil, showInPicker: true, responseLimitCount: nil, responseLimitType: nil, responseLimitWindowMinutes: nil, moreFeedbackPrompt: nil, isActive: true, sortOrder: 1, fields: [])
        await cache.write(hash: "abc", forms: [form])
        let snap = await cache.read()
        XCTAssertNotNil(snap)
        XCTAssertEqual(snap?.hash, "abc")
        XCTAssertEqual(snap?.forms.first?.id, "f1")
    }

    func test_survivesNewInstance() async throws {
        let cacheA = ConfigCache(directory: tempDir)
        await cacheA.write(hash: "h1", forms: [])
        let cacheB = ConfigCache(directory: tempDir)
        let snap = await cacheB.read()
        XCTAssertNotNil(snap)
        XCTAssertEqual(snap?.hash, "h1")
    }

    func test_discardsCache_withoutSchemaVersion() async throws {
        // Simulates a cache written by a pre-CRLBS-128 build (no schemaVersion).
        let legacy = Data(#"{"hash":"old","forms":[]}"#.utf8)
        try legacy.write(to: tempDir.appendingPathComponent("config.json"), options: .atomic)
        let snap = await ConfigCache(directory: tempDir).read()
        XCTAssertNil(snap, "a cache without a schemaVersion must be discarded")
    }

    func test_discardsCache_withWrongSchemaVersion() async throws {
        let future = Data(#"{"schemaVersion":999,"hash":"x","forms":[]}"#.utf8)
        try future.write(to: tempDir.appendingPathComponent("config.json"), options: .atomic)
        let snap = await ConfigCache(directory: tempDir).read()
        XCTAssertNil(snap, "a cache with a mismatched schemaVersion must be discarded")
    }
}
