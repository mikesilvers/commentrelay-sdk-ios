import XCTest
@testable import CommentRelayCore

final class CommentRelayTests: XCTestCase {
    func test_version_isNonEmpty() {
        XCTAssertFalse(CommentRelay.version.isEmpty)
    }
}
