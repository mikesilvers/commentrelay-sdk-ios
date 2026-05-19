import XCTest
@testable import CommentRelayCore

final class SubmissionProblemsTests: XCTestCase {
    private func makeQueue() -> SubmissionQueue {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("crl-\(UUID().uuidString)")
        return SubmissionQueue(directory: dir, maxEntries: 50, maxAge: 86_400)
    }
    private func sub() throws -> CommentRelaySubmission {
        try JSONDecoder().decode(CommentRelaySubmission.self,
            from: Data(#"{"form_id":"f","user_identifier":"u","platform":"ios","fields":[]}"#.utf8))
    }

    func test_markFailed_sets_failedAt_and_excludes_from_retryingCount() async throws {
        let q = makeQueue()
        let id = try await q.enqueue(try sub(), attachments: [])
        let before = await q.retryingCount
        XCTAssertEqual(before, 1)
        await q.markFailed(localId: id, category: "server", detail: #"server(message: "HTTP 500")"#)
        let all = await q.loadAll()
        XCTAssertNotNil(all.first?.failedAt)
        XCTAssertNotNil(all.first?.lastAttemptAt)
        XCTAssertEqual(all.first?.errorCategory, "server")
        XCTAssertEqual(all.first?.lastError, #"server(message: "HTTP 500")"#)
        let after = await q.retryingCount
        XCTAssertEqual(after, 0)            // failed ⇒ not "retrying"
        let total = await q.count
        XCTAssertEqual(total, 1)            // still retained
    }

    func test_markFailed_is_noop_for_unknown_id() async throws {
        let q = makeQueue()
        await q.markFailed(localId: UUID(), category: "server", detail: "x")
        let n = await q.count
        XCTAssertEqual(n, 0)
    }
}

extension SubmissionProblemsTests {
    func test_category_maps_from_commentRelayError() {
        XCTAssertEqual(CommentRelaySubmissionProblem.Category(.server(message: "x")), .server)
        XCTAssertEqual(CommentRelaySubmissionProblem.Category(.forbidden(message: "x")), .forbidden)
        XCTAssertEqual(CommentRelaySubmissionProblem.Category(.rateLimited(retryAfter: nil)), .rateLimited)
        XCTAssertEqual(CommentRelaySubmissionProblem.Category(.badRequest(message: "x")), .badRequest)
    }

    func test_category_token_roundtrips_and_defaults_to_unknown() {
        let all: [CommentRelaySubmissionProblem.Category] = [
            .server, .transport, .rateLimited, .forbidden, .badRequest,
            .paymentRequired, .notFound, .decoding, .conflict,
            .uploadFailed, .uploadUrlExpired, .unknown
        ]
        for c in all {
            XCTAssertEqual(CommentRelaySubmissionProblem.Category(token: c.rawValue), c,
                           "round-trip failed for \(c)")
        }
        XCTAssertEqual(CommentRelaySubmissionProblem.Category(token: nil), .unknown)
        XCTAssertEqual(CommentRelaySubmissionProblem.Category(token: "garbage"), .unknown)
    }
}
