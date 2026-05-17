import XCTest
import CommentRelayCore
@testable import CommentRelayUI

final class RatingPayloadTests: XCTestCase {
    private func smileyForm() throws -> CommentRelayForm {
        let json = """
        {
          "id": "form-1", "title": "T", "show_in_picker": true,
          "response_limit_count": 0, "response_limit_type": "lifetime",
          "response_limit_window_minutes": null, "more_feedback_prompt": "",
          "is_active": true, "sort_order": 1,
          "fields": [{
            "id": "rate-1", "field_type": "smiley_rating", "label": "Mood",
            "is_required": true, "is_gate": false, "sort_order": 1, "max_files": null,
            "options": [
              {"position": 1, "label": "Sad", "svg": "<svg/>"},
              {"position": 3, "label": "Neutral", "svg": "<svg/>"},
              {"position": 5, "label": "Happy", "svg": "<svg/>"}
            ]
          }]
        }
        """
        return try JSONDecoder().decode(CommentRelayForm.self, from: Data(json.utf8))
    }

    func testRatingPayloadIncludesLabel() throws {
        let vm = FeedbackFormViewModel(form: try smileyForm(),
                                       userIdentifier: "u", platform: .ios, sdkVersion: nil)
        vm.setInt("rate-1", 3)
        let submission = vm.buildSubmission()
        let body = try JSONEncoder().encode(submission)
        let s = String(data: body, encoding: .utf8)!
        XCTAssertTrue(s.contains("\\\"position\\\":3"), "missing position; body=\(s)")
        XCTAssertTrue(s.contains("\\\"label\\\":\\\"Neutral\\\""), "missing label; body=\(s)")
    }

    func testRatingPayloadFallsBackWhenNoOption() throws {
        let vm = FeedbackFormViewModel(form: try smileyForm(),
                                       userIdentifier: "u", platform: .ios, sdkVersion: nil)
        vm.setInt("rate-1", 99) // no matching option/label
        let submission = vm.buildSubmission()
        let body = try JSONEncoder().encode(submission)
        let s = String(data: body, encoding: .utf8)!
        XCTAssertTrue(s.contains("\\\"position\\\":99"), "missing position; body=\(s)")
        XCTAssertFalse(s.contains("\\\"label\\\""), "label must be absent when unknown; body=\(s)")
    }
}
