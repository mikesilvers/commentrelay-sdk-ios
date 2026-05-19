import XCTest
@testable import CommentRelayCore

final class CommentRelayConfigurationTests: XCTestCase {
    func test_defaults_autoPopulateMetadata() {
        let c = CommentRelayConfiguration(
            apiKey: "crk_test_abc",
            baseURL: URL(string: "https://api.example.com")!)
        XCTAssertFalse(c.effectiveSDKVersion.isEmpty)
        XCTAssertFalse(c.effectiveOSVersion.isEmpty)
        XCTAssertFalse(c.effectiveDeviceModel.isEmpty)
        XCTAssertEqual(c.effectiveSDKVersion, CommentRelay.version)
    }

    func test_overrides_winOverAutoPopulated() {
        let c = CommentRelayConfiguration(
            apiKey: "k",
            baseURL: URL(string: "https://api.example.com")!,
            sdkVersionOverride: "9.9.9",
            osVersionOverride: "42.0",
            deviceModelOverride: "MyFakePhone",
            appVersionOverride: "1.2.3")
        XCTAssertEqual(c.effectiveSDKVersion, "9.9.9")
        XCTAssertEqual(c.effectiveOSVersion, "42.0")
        XCTAssertEqual(c.effectiveDeviceModel, "MyFakePhone")
        XCTAssertEqual(c.effectiveAppVersion, "1.2.3")
    }
}
