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
        XCTAssertEqual(all.first?.attemptCount, 1, "markFailed must count the terminal attempt")
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
    // Hermetic client: FakeReachability(initial: false) prevents any connectivity-restored
    // flush triggers from firing after construction. The caller must `await c.flushQueue()`
    // once (while the queue is empty) to drain/serialize the unconditional init-trigger flush
    // as a no-op before enqueuing test entries — same pattern as FlushTriggerTests.
    private func makeClient() async -> CommentRelayClient {
        let cfg = CommentRelayConfiguration(apiKey: "k", baseURL: URL(string: "https://example.invalid")!)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("crl-\(UUID().uuidString)")
        let c = CommentRelayClient(configuration: cfg, session: .shared,
                                   cacheDirectory: dir, keychainService: "t-\(UUID())",
                                   reachability: FakeReachability(initial: false))
        // Drain the unconditional init-trigger flushQueue() as a no-op while queue is empty.
        await c.flushQueue()
        return c
    }

    func test_submissionProblems_reports_failed_and_queued() async throws {
        let c = await makeClient()
        let q = await c._testQueue
        let idFailed = try await q.enqueue(try sub(), attachments: [])
        _ = try await q.enqueue(try sub(), attachments: [])
        await q.markFailed(localId: idFailed, category: "badRequest",
                           detail: #"badRequest(message: "Invalid field_id for form")"#)
        let problems = await c.submissionProblems()
        XCTAssertEqual(problems.count, 2)
        let failed = problems.first { $0.id == idFailed }
        XCTAssertEqual(failed?.kind, .failed)
        XCTAssertEqual(failed?.category, .badRequest)
        XCTAssertEqual(problems.filter { $0.kind == .queuedRetrying }.count, 1)
    }

    func test_deleteProblemSubmission_removes_entry() async throws {
        let c = await makeClient()
        let q = await c._testQueue
        let id = try await q.enqueue(try sub(), attachments: [])
        await c.deleteProblemSubmission(id: id)
        let n = await q.count
        XCTAssertEqual(n, 0)
        let empty = await c.submissionProblems()
        XCTAssertTrue(empty.isEmpty)
    }

    func test_retrySubmission_unfails_and_makes_eligible() async throws {
        let c = await makeClient()
        let q = await c._testQueue
        let id = try await q.enqueue(try sub(), attachments: [])
        await q.markFailed(localId: id, category: "server", detail: "server(message: \"HTTP 500\")")
        await c.retrySubmission(id: id)
        let e = await q.loadAll().first { $0.localId == id }
        XCTAssertNotNil(e)
        XCTAssertNil(e?.failedAt)
        let rc = await q.retryingCount
        XCTAssertEqual(rc, 1, "entry should be counted as retrying after retrySubmission")
    }
}

extension SubmissionProblemsTests {
    func test_category_maps_from_commentRelayError() {
        XCTAssertEqual(CommentRelaySubmissionProblem.Category(.server(message: "x")), .server)
        XCTAssertEqual(CommentRelaySubmissionProblem.Category(.forbidden(message: "x")), .forbidden)
        XCTAssertEqual(CommentRelaySubmissionProblem.Category(.rateLimited(retryAfter: nil)), .rateLimited)
        XCTAssertEqual(CommentRelaySubmissionProblem.Category(.badRequest(message: "x")), .badRequest)
        XCTAssertEqual(CommentRelaySubmissionProblem.Category(.unauthorized(message: "x")), .unauthorized)
        XCTAssertEqual(CommentRelaySubmissionProblem.Category(.unexpectedStatus(statusCode: 418, message: "x")), .unexpectedStatus)
    }

    func test_category_token_roundtrips_and_defaults_to_unknown() {
        let all: [CommentRelaySubmissionProblem.Category] = [
            .server, .transport, .rateLimited, .forbidden, .badRequest,
            .paymentRequired, .notFound, .decoding, .conflict,
            .uploadFailed, .uploadUrlExpired, .unauthorized, .unexpectedStatus, .unknown
        ]
        for c in all {
            XCTAssertEqual(CommentRelaySubmissionProblem.Category(token: c.rawValue), c,
                           "round-trip failed for \(c)")
        }
        XCTAssertEqual(CommentRelaySubmissionProblem.Category(token: nil), .unknown)
        XCTAssertEqual(CommentRelaySubmissionProblem.Category(token: "garbage"), .unknown)
    }
}
