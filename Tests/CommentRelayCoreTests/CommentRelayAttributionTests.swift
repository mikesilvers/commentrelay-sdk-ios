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

    func test_resolvedLink_isNil_forNonHTTPSScheme() {
        let http = CommentRelayAttribution(
            showAttribution: true,
            attributionURL: URL(string: "http://api.commentrelay.com/r/powered-by"))
        XCTAssertNil(http.resolvedLink, "http must be rejected")

        let js = CommentRelayAttribution(
            showAttribution: true,
            attributionURL: URL(string: "javascript:alert(1)"))
        XCTAssertNil(js.resolvedLink, "non-https scheme must be rejected")
    }

    func test_resolvedLink_isNil_forHTTPSWithoutHost() {
        let a = CommentRelayAttribution(
            showAttribution: true,
            attributionURL: URL(string: "https:///nohost"))
        XCTAssertNil(a.resolvedLink, "https with empty host must be rejected")
    }
}
