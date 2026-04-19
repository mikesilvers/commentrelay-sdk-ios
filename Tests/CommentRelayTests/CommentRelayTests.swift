import XCTest
@testable import CommentRelay

final class CommentRelayTests: XCTestCase {
    func test_version_isNonEmpty() {
        XCTAssertFalse(CommentRelay.version.isEmpty)
    }
}
