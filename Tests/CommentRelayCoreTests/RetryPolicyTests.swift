import XCTest
@testable import CommentRelayCore

final class RetryPolicyTests: XCTestCase {
    func testClassification() {
        XCTAssertEqual(RetryPolicy.classify(.transport(URLError(.notConnectedToInternet))), .retry(nil))
        XCTAssertEqual(RetryPolicy.classify(.server(message: "x")), .retry(nil))
        XCTAssertEqual(RetryPolicy.classify(.rateLimited(retryAfter: 12)), .retry(12))
        XCTAssertEqual(RetryPolicy.classify(.badRequest(message: "x")), .terminal)
        XCTAssertEqual(RetryPolicy.classify(.paymentRequired(message: "x")), .terminal)
        XCTAssertEqual(RetryPolicy.classify(.notFound(message: "x")), .terminal)
        XCTAssertEqual(RetryPolicy.classify(.forbidden(message: "x")), .pause)
    }

    func testBackoffCapsAt30AndUsesRetryAfterWhenLarger() {
        XCTAssertEqual(RetryPolicy.backoff(attempt: 1, retryAfter: nil), 1)
        XCTAssertEqual(RetryPolicy.backoff(attempt: 5, retryAfter: nil), 16)
        XCTAssertEqual(RetryPolicy.backoff(attempt: 7, retryAfter: nil), 30) // 2^6=64 capped
        XCTAssertEqual(RetryPolicy.backoff(attempt: 1, retryAfter: 45), 45)  // retryAfter wins
        XCTAssertEqual(RetryPolicy.backoff(attempt: 7, retryAfter: 5), 30)   // max(cap, retryAfter)
    }
}
