// Tests/CommentRelayCoreTests/LocalizationBundleTests.swift
import XCTest
@testable import CommentRelayCore

final class LocalizationBundleTests: XCTestCase {
    override func setUp() { CommentRelayLocalization.resetForTesting() }
    override func tearDown() { CommentRelayLocalization.resetForTesting() }

    func test_missingKey_fallsBackToKey() {
        let s = LocalizationBundle.shared.string(forKey: "crl.totally.missing.key")
        XCTAssertEqual(s, "crl.totally.missing.key")
    }

    func test_registeredBundle_takesPrecedence() throws {
        let tempBundlePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("crl-bundle-\(UUID().uuidString)").appendingPathComponent("en.lproj")
        try FileManager.default.createDirectory(at: tempBundlePath, withIntermediateDirectories: true)
        let stringsURL = tempBundlePath.appendingPathComponent("Localizable.strings")
        try #""crl.greeting"="hello from registered";"#.write(to: stringsURL, atomically: true, encoding: .utf8)
        let bundle = Bundle(url: tempBundlePath.deletingLastPathComponent())!
        CommentRelayLocalization.register(locale: Locale(identifier: "en"), bundle: bundle)

        XCTAssertEqual(LocalizationBundle.shared.string(forKey: "crl.greeting"), "hello from registered")
    }
}
