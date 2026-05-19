// Tests/CommentRelayUITests/ScreenTests/SubmitOutcomeRouteMappingTests.swift
// CRLBS-119: a queued (not-yet-delivered) submission must never be presented
// as a delivered "thank you" success.
import XCTest
import CommentRelayCore
@testable import CommentRelayUI

final class SubmitOutcomeRouteMappingTests: XCTestCase {
    private func makeReceipt() throws -> CommentRelaySubmissionReceipt {
        let json = #"{"submissionId":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","hasUploads":false,"uploadUrls":[]}"#
        return try JSONDecoder().decode(CommentRelaySubmissionReceipt.self, from: Data(json.utf8))
    }

    func test_queued_is_not_presented_as_delivered() {
        let route = CommentRelayView.route(for: .queued(localId: UUID()), hasUserIdentifier: true)
        XCTAssertEqual(route, .queuedSaved)
        if case .thanks = route {
            XCTFail("queued must never route to .thanks — that falsely claims delivery")
        }
    }

    func test_submitted_routes_to_thanks_reflecting_identifier() throws {
        XCTAssertEqual(
            CommentRelayView.route(for: .submitted(try makeReceipt()), hasUserIdentifier: true),
            .thanks(showHistory: true))
        XCTAssertEqual(
            CommentRelayView.route(for: .submitted(try makeReceipt()), hasUserIdentifier: false),
            .thanks(showHistory: false))
    }
}
