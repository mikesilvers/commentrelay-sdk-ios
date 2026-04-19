import XCTest
@testable import CommentRelayCore

final class CommentRelayErrorTests: XCTestCase {
    func test_allCases_instantiateAndDescribe() {
        let cases: [CommentRelayError] = [
            .badRequest(message: "bad"),
            .paymentRequired(message: "billing"),
            .forbidden(message: "key revoked"),
            .notFound(message: "category"),
            .conflict(message: "limit"),
            .rateLimited(retryAfter: 2),
            .server(message: "boom"),
            .transport(URLError(.notConnectedToInternet)),
            .decoding(NSError(domain: "test", code: 0)),
            .uploadFailed(submissionId: UUID(), fileName: "a.png", underlying: NSError(domain: "s3", code: 1)),
            .uploadUrlExpired(submissionId: UUID()),
        ]
        XCTAssertEqual(cases.count, 11)
        for error in cases {
            XCTAssertFalse(String(describing: error).isEmpty)
        }
    }

    func test_isTerminal_trueOnlyForForbidden() {
        XCTAssertTrue(CommentRelayError.forbidden(message: "x").isTerminal)
        XCTAssertFalse(CommentRelayError.server(message: "x").isTerminal)
        XCTAssertFalse(CommentRelayError.rateLimited(retryAfter: nil).isTerminal)
    }
}
