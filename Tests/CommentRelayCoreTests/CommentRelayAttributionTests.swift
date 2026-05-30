import XCTest
@testable import CommentRelayCore

final class CommentRelayAttributionTests: XCTestCase {
    private let url = URL(string: "https://api.commentrelay.com/r/powered-by?p=proj_1")!

    func test_resolvedLink_isURL_whenShowingAndURLPresent() {
        let a = CommentRelayAttribution(showAttribution: true, attributionURL: url)
        XCTAssertEqual(a.resolvedLink, url)
    }

    func test_resolvedLink_isNil_whenNotShowing() {
        let a = CommentRelayAttribution(showAttribution: false, attributionURL: url)
        XCTAssertNil(a.resolvedLink)
    }

    func test_resolvedLink_isNil_whenShowingButNoURL() {
        let a = CommentRelayAttribution(showAttribution: true, attributionURL: nil)
        XCTAssertNil(a.resolvedLink)
    }

    func test_hidden_isNotShowing() {
        XCTAssertNil(CommentRelayAttribution.hidden.resolvedLink)
        XCTAssertFalse(CommentRelayAttribution.hidden.showAttribution)
    }
}
