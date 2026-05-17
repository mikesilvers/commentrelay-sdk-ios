import XCTest
@testable import CommentRelayCore

final class PlatformTests: XCTestCase {
    func testPlatformCurrentMatchesCompiledOS() {
        #if os(iOS)
        XCTAssertEqual(Platform.current, .ios)
        #elseif os(macOS)
        XCTAssertEqual(Platform.current, .macos)
        #else
        XCTAssertEqual(Platform.current, .other)
        #endif
    }

    func testMacosEncodesToWireValue() throws {
        let data = try JSONEncoder().encode(Platform.macos)
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"macos\"")
    }
}
