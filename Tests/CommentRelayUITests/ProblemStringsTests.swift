import XCTest
import CommentRelayCore
@testable import CommentRelayUI

final class ProblemStringsTests: XCTestCase {
    func test_problem_strings_resolve_non_empty() {
        for s in [Strings.problemQueuedChip, Strings.problemFailedChip,
                  Strings.problemTryAgain, Strings.problemRemove,
                  Strings.problemRemoveConfirmTitle, Strings.problemRemoveConfirm,
                  Strings.problemHistoryUnavailable] {
            XCTAssertFalse(s.isEmpty)
            XCTAssertFalse(s.hasPrefix("crl.problem."), "string did not resolve: \(s)")
        }
        XCTAssertFalse(Strings.problemAttempts(3).isEmpty)
        XCTAssertFalse(Strings.problemAttempts(3).hasPrefix("crl.problem."))
    }
    func test_friendlyError_maps_categories() {
        XCTAssertEqual(Strings.friendlyError(.rateLimited), Strings.errorRateLimited)
        XCTAssertEqual(Strings.friendlyError(.paymentRequired), Strings.errorPaymentRequired)
        XCTAssertEqual(Strings.friendlyError(.uploadFailed), Strings.errorUploadFailed)
        XCTAssertEqual(Strings.friendlyError(.uploadUrlExpired), Strings.errorUploadFailed)
        XCTAssertEqual(Strings.friendlyError(.server), Strings.errorGeneric)
        XCTAssertEqual(Strings.friendlyError(.transport), Strings.errorGeneric)
        XCTAssertEqual(Strings.friendlyError(.unknown), Strings.errorGeneric)
    }

    func test_errorUnauthorized_resolves_non_empty() {
        let s = Strings.errorUnauthorized
        XCTAssertFalse(s.isEmpty)
        XCTAssertNotEqual(s, "crl.error.unauthorized", "string did not resolve")
    }

    func test_friendlyError_maps_unauthorized_to_dedicated_message_and_unexpectedStatus_to_generic() {
        XCTAssertEqual(Strings.friendlyError(.unauthorized), Strings.errorUnauthorized)
        XCTAssertEqual(Strings.friendlyError(.unexpectedStatus), Strings.errorGeneric)
    }
}
