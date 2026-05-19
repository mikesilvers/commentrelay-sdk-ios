import XCTest
@testable import CommentRelayCore

final class ConfigurationOfflineTests: XCTestCase {
    func testDefaults() {
        let c = CommentRelayConfiguration(baseURL: URL(string: "https://x")!, apiKey: "k")
        XCTAssertTrue(c.offlineQueueingEnabled)
        XCTAssertEqual(c.maxQueuedSubmissions, 50)
        XCTAssertEqual(c.maxQueueAge, 30 * 24 * 60 * 60)
    }

    func testOverrides() {
        let c = CommentRelayConfiguration(baseURL: URL(string: "https://x")!, apiKey: "k",
                                          offlineQueueingEnabled: false,
                                          maxQueuedSubmissions: 5,
                                          maxQueueAge: 60)
        XCTAssertFalse(c.offlineQueueingEnabled)
        XCTAssertEqual(c.maxQueuedSubmissions, 5)
        XCTAssertEqual(c.maxQueueAge, 60)
    }
}
