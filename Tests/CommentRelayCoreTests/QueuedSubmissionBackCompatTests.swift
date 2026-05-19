import XCTest
@testable import CommentRelayCore

final class QueuedSubmissionBackCompatTests: XCTestCase {
    private func sampleSubmissionJSON() -> String {
        #"{"form_id":"f","user_identifier":"u","platform":"ios","fields":[]}"#
    }

    func test_decodes_legacy_entry_without_new_keys() throws {
        let json = """
        {"localId":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
         "submission":\(sampleSubmissionJSON()),
         "phase":"needsSubmit","attachments":[],"attemptCount":2,
         "createdAt":768000000.0}
        """
        let e = try JSONDecoder().decode(QueuedSubmission.self, from: Data(json.utf8))
        XCTAssertNil(e.failedAt)
        XCTAssertNil(e.lastAttemptAt)
        XCTAssertNil(e.errorCategory)
        XCTAssertEqual(e.attemptCount, 2)
        XCTAssertNil(e.lastError)
        XCTAssertNil(e.nextEarliestAttempt)
    }

    func test_roundtrips_new_fields() throws {
        let json = """
        {"localId":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
         "submission":\(sampleSubmissionJSON()),
         "phase":"needsSubmit","attachments":[],"attemptCount":1,
         "createdAt":768000000.0,"failedAt":768000050.0,
         "lastAttemptAt":768000040.0,"errorCategory":"server"}
        """
        let e = try JSONDecoder().decode(QueuedSubmission.self, from: Data(json.utf8))
        let back = try JSONEncoder().encode(e)
        let e2 = try JSONDecoder().decode(QueuedSubmission.self, from: back)
        XCTAssertEqual(e2.errorCategory, "server")
        XCTAssertEqual(e2.failedAt, e.failedAt)
        XCTAssertEqual(e2.lastAttemptAt, e.lastAttemptAt)
        XCTAssertEqual(e2, e)
    }
}
