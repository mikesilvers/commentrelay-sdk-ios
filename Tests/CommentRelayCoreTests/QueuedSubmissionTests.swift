import XCTest
@testable import CommentRelayCore

final class QueuedSubmissionTests: XCTestCase {
    private func sub() -> CommentRelaySubmission {
        CommentRelaySubmission(formId: "f", userIdentifier: "u", platform: .ios,
            fields: [.text(fieldId: "1", value: "hi")], osVersion: nil, deviceModel: nil,
            appVersion: nil, sdkVersion: nil, locale: nil, contactPreference: nil,
            contactDetails: nil, sessionId: nil)
    }

    func testRoundTripsThroughJSON() throws {
        let q = QueuedSubmission(
            localId: UUID(), submission: sub(), phase: .needsSubmit,
            serverSubmissionId: nil,
            attachments: [QueuedFileRef(fieldId: "2", fileName: "a.png", contentType: "image/png", size: 3)],
            attemptCount: 0, nextEarliestAttempt: nil, createdAt: Date(timeIntervalSince1970: 1),
            lastError: nil)
        let data = try JSONEncoder().encode(q)
        let back = try JSONDecoder().decode(QueuedSubmission.self, from: data)
        XCTAssertEqual(back, q)
        XCTAssertEqual(back.phase, .needsSubmit)
    }

    func testPhaseEncodesStably() throws {
        let data = try JSONEncoder().encode(QueuedSubmission.Phase.needsFinalize)
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"needsFinalize\"")
    }
}
