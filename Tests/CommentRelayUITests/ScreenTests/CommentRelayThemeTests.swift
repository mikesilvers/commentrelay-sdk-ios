import XCTest
import SwiftUI
import ViewInspector
@testable import CommentRelayUI

final class CommentRelayThemeTests: XCTestCase {
    func test_default_values() {
        let theme = CommentRelayTheme.default
        XCTAssertEqual(theme.cornerRadius, 12)
    }

    func test_environment_injection_carriesThroughHierarchy() throws {
        let custom = CommentRelayTheme(accentColor: .purple, cornerRadius: 24)
        let sut = Text("t").environment(\.commentRelayTheme, custom)
        let extracted = try sut.inspect().text().environment(\.commentRelayTheme)
        XCTAssertEqual(extracted.cornerRadius, 24)
    }
}
