import XCTest
import SwiftUI
import ViewInspector
@testable import CommentRelayUI

final class PendingBadgeTests: XCTestCase {
    func testHiddenWhenZero() throws {
        let v = PendingBadge(count: 0)
        XCTAssertThrowsError(try v.inspect().find(text: "0"))
    }
    func testShowsCountWhenPositive() throws {
        let v = PendingBadge(count: 3)
        XCTAssertNoThrow(try v.inspect().find(text: "3"))
    }
}
