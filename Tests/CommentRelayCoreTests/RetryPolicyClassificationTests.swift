import XCTest
@testable import CommentRelayCore

final class RetryPolicyClassificationTests: XCTestCase {
    func test_retryable_cases() {
        // .server and .transport retry with nil retry-after.
        switch RetryPolicy.classify(.server(message: "x")) {
        case .retry(let after): XCTAssertNil(after)
        default: XCTFail("expected .retry")
        }
        let urlErr = URLError(.notConnectedToInternet)
        switch RetryPolicy.classify(.transport(urlErr)) {
        case .retry(let after): XCTAssertNil(after)
        default: XCTFail("expected .retry")
        }
        // .rateLimited carries Retry-After through.
        switch RetryPolicy.classify(.rateLimited(retryAfter: 7)) {
        case .retry(let after): XCTAssertEqual(after, 7)
        default: XCTFail("expected .retry")
        }
    }

    func test_pause_case() {
        guard case .pause = RetryPolicy.classify(.forbidden(message: "x")) else {
            return XCTFail("expected .pause")
        }
    }

    func test_terminal_cases_including_new_ones() {
        let terminals: [CommentRelayError] = [
            .badRequest(message: "x"),
            .paymentRequired(message: "x"),
            .notFound(message: "x"),
            .decoding(NSError(domain: "x", code: 1)),
            .conflict(message: "x"),
            .uploadFailed(submissionId: UUID(), fileName: "f", underlying: NSError(domain: "x", code: 1)),
            .uploadUrlExpired(submissionId: UUID()),
            // CRLBS-120: new terminal cases
            .unauthorized(message: "x"),
            .unexpectedStatus(statusCode: 418, message: "x"),
        ]
        for err in terminals {
            XCTAssertEqual(RetryPolicy.classify(err), .terminal, "\(err) should be terminal")
        }
    }
}
