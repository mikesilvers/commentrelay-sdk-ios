import XCTest
@testable import CommentRelayUI

final class PackageResolvesTests: XCTestCase {
    func test_moduleLoads() {
        _ = CommentRelayUI.self
    }
}
