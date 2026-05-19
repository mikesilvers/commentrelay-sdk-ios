import XCTest
@testable import CommentRelayCore

final class ConfigurationOfflineTests: XCTestCase {
    func testDefaults() {
        let c = CommentRelayConfiguration(apiKey: "k", baseURL: URL(string: "https://x")!)
        XCTAssertTrue(c.offlineQueueingEnabled)
        XCTAssertEqual(c.maxQueuedSubmissions, 50)
        XCTAssertEqual(c.maxQueueAge, 30 * 24 * 60 * 60)
    }

    func testOverrides() {
        let c = CommentRelayConfiguration(apiKey: "k", baseURL: URL(string: "https://x")!,
                                          offlineQueueingEnabled: false,
                                          maxQueuedSubmissions: 5,
                                          maxQueueAge: 60)
        XCTAssertFalse(c.offlineQueueingEnabled)
        XCTAssertEqual(c.maxQueuedSubmissions, 5)
        XCTAssertEqual(c.maxQueueAge, 60)
    }

    // TDD: these tests fail until productionBaseURL constant and apiKey-first init exist.

    func testProductionBaseURLConstant() {
        XCTAssertEqual(
            CommentRelayConfiguration.productionBaseURL,
            URL(string: "https://api.commentrelay.com")!
        )
    }

    func testDefaultBaseURLIsProduction() {
        let c = CommentRelayConfiguration(apiKey: "k")
        XCTAssertEqual(c.baseURL, CommentRelayConfiguration.productionBaseURL)
        XCTAssertEqual(c.baseURL, URL(string: "https://api.commentrelay.com")!)
    }

    func testExplicitBaseURLOverridesDefault() {
        let custom = URL(string: "https://staging.example.com")!
        let c = CommentRelayConfiguration(apiKey: "k", baseURL: custom)
        XCTAssertEqual(c.baseURL, custom)
    }
}
