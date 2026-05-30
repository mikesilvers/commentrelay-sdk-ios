import XCTest
@testable import CommentRelayCore

final class AttributionDecodingTests: XCTestCase {
    private func decode(_ json: String) throws -> DecodedConfigResponse {
        try JSONDecoder().decode(DecodedConfigResponse.self, from: Data(json.utf8))
    }

    func test_updated_withAttribution_true_andURL() throws {
        let d = try decode(#"""
        {"current":false,"hash":"h1","forms":[],
         "show_attribution":true,
         "attribution_url":"https://api.commentrelay.com/r/powered-by?p=proj_1"}
        """#)
        XCTAssertEqual(d.response, .updated(hash: "h1", forms: []))
        XCTAssertTrue(d.attribution.showAttribution)
        XCTAssertEqual(d.attribution.attributionURL,
                       URL(string: "https://api.commentrelay.com/r/powered-by?p=proj_1"))
    }

    func test_attribution_false_hasNoLink() throws {
        let d = try decode(#"{"current":false,"hash":"h","forms":[],"show_attribution":false}"#)
        XCTAssertFalse(d.attribution.showAttribution)
        XCTAssertNil(d.attribution.resolvedLink)
    }

    func test_fieldsAbsent_defaultsToHidden() throws {
        let d = try decode(#"{"current":false,"hash":"h","forms":[]}"#)
        XCTAssertEqual(d.attribution, .hidden)
    }

    func test_current_response_stillCarriesAttribution() throws {
        let d = try decode(#"{"current":true,"show_attribution":true,"attribution_url":"https://api.commentrelay.com/r/powered-by?p=p2"}"#)
        XCTAssertEqual(d.response, .current)
        XCTAssertEqual(d.attribution.resolvedLink,
                       URL(string: "https://api.commentrelay.com/r/powered-by?p=p2"))
    }

    func test_malformedURL_yieldsNil_notThrow() throws {
        let d = try decode(#"{"current":false,"hash":"h","forms":[],"show_attribution":true,"attribution_url":""}"#)
        XCTAssertTrue(d.attribution.showAttribution)
        XCTAssertNil(d.attribution.attributionURL)
        XCTAssertNil(d.attribution.resolvedLink)
    }
}
