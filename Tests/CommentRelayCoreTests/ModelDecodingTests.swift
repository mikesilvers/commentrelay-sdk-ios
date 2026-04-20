import XCTest
@testable import CommentRelayCore

final class ModelDecodingTests: XCTestCase {
    private var decoder = JSONDecoder()

    override func setUp() {
        super.setUp()
        decoder.dateDecodingStrategy = .iso8601
    }

    func test_fieldType_roundTripsAllTenCases() throws {
        let raw = #"["textbox","true_false","numeric","photo","attachment","informational","email","phone","smiley_rating","color_scale"]"#
        let types = try decoder.decode([FieldType].self, from: Data(raw.utf8))
        XCTAssertEqual(types, [.textbox, .trueFalse, .numeric, .photo, .attachment, .informational, .email, .phone, .smileyRating, .colorScale])
    }

    func test_fieldType_unknownValueDecodesToUnknown() throws {
        let data = Data(#""martian""#.utf8)
        XCTAssertEqual(try decoder.decode(FieldType.self, from: data), .unknown)
    }

    func test_fieldOption_smileyAndColorBothDecode() throws {
        let smiley = #"{"position":3,"label":"neutral","svg":"<svg/>"}"#
        let color = """
        {"position":1,"color":"#FF0000","label":"Poor"}
        """
        let s = try decoder.decode(FieldOption.self, from: Data(smiley.utf8))
        let c = try decoder.decode(FieldOption.self, from: Data(color.utf8))
        XCTAssertEqual(s.position, 3)
        XCTAssertEqual(s.label, "neutral")
        XCTAssertEqual(s.svg, "<svg/>")
        XCTAssertNil(s.color)
        XCTAssertEqual(c.color, "#FF0000")
        XCTAssertNil(c.svg)
    }

    func test_field_decodesTextbox() throws {
        let raw = #"""
        {"id":"f1","field_type":"textbox","label":"Describe","is_required":true,"is_gate":false,"sort_order":1,"max_files":null}
        """#
        let f = try decoder.decode(CommentRelayField.self, from: Data(raw.utf8))
        XCTAssertEqual(f.id, "f1")
        XCTAssertEqual(f.fieldType, .textbox)
        XCTAssertEqual(f.label, "Describe")
        XCTAssertTrue(f.isRequired)
        XCTAssertFalse(f.isGate)
        XCTAssertEqual(f.sortOrder, 1)
        XCTAssertNil(f.maxFiles)
    }

    func test_category_decodesFullConfigPayload() throws {
        let raw = #"""
        {
          "current": false,
          "hash": "abc123",
          "categories": [{
            "id": "cat1",
            "title": "Bug Report",
            "show_in_picker": true,
            "response_limit_count": 5,
            "response_limit_type": "per_session",
            "response_limit_window_days": null,
            "more_feedback_prompt": "Tell us more",
            "is_active": true,
            "sort_order": 1,
            "fields": []
          }]
        }
        """#
        let result = try decoder.decode(CommentRelayConfigResponse.self, from: Data(raw.utf8))
        guard case .updated(let hash, let categories) = result else { return XCTFail() }
        XCTAssertEqual(hash, "abc123")
        XCTAssertEqual(categories.first?.id, "cat1")
        XCTAssertEqual(categories.first?.title, "Bug Report")
        XCTAssertEqual(categories.first?.responseLimitType, .perSession)
    }

    func test_category_decodesCurrentResponse() throws {
        let raw = #"{"current":true}"#
        let result = try decoder.decode(CommentRelayConfigResponse.self, from: Data(raw.utf8))
        guard case .current = result else { return XCTFail() }
    }

    func test_submission_encodesInAPIShape() throws {
        let submission = CommentRelaySubmission(
            categoryId: "cat1",
            userIdentifier: "user-123",
            platform: .ios,
            fields: [.text(fieldId: "f1", value: "bug"), .files(fieldId: "f2", metadata: [
                .init(name: "s.png", type: "image/png", size: 123)
            ])],
            osVersion: "18.0",
            deviceModel: "iPhone 16",
            appVersion: "2.1.0",
            sdkVersion: "0.0.1",
            locale: "en_US",
            contactPreference: .email,
            contactDetails: "a@b.c",
            sessionId: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        )
        let data = try JSONEncoder().encode(submission)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["category_id"] as? String, "cat1")
        XCTAssertEqual(json["user_identifier"] as? String, "user-123")
        XCTAssertEqual(json["platform"] as? String, "ios")
        XCTAssertEqual(json["contact_preference"] as? String, "email")
        let fields = try XCTUnwrap(json["fields"] as? [[String: Any]])
        XCTAssertEqual(fields.count, 2)
        XCTAssertEqual(fields[0]["value"] as? String, "bug")
        let meta = try XCTUnwrap(fields[1]["file_metadata"] as? [[String: Any]])
        XCTAssertEqual(meta.first?["name"] as? String, "s.png")
    }

    func test_receipt_decodes() throws {
        let raw = """
        {"submissionId":"11111111-1111-1111-1111-111111111111","hasUploads":true,"uploadUrls":[
          {"fieldId":"f2","fileName":"s.png","uploadUrl":"https://s3/upload"}]}
        """
        let receipt = try decoder.decode(CommentRelaySubmissionReceipt.self, from: Data(raw.utf8))
        XCTAssertEqual(receipt.submissionId.uuidString.lowercased(), "11111111-1111-1111-1111-111111111111")
        XCTAssertTrue(receipt.hasUploads)
        XCTAssertEqual(receipt.uploadUrls.first?.fileName, "s.png")
    }

    func test_history_decodesIdentified() throws {
        let raw = #"""
        {"submissions":[{
          "id":"22222222-2222-2222-2222-222222222222",
          "category_id":"cat1",
          "category_title":"Bug Report",
          "status":"complete",
          "created_at":"2026-03-19T10:30:00Z",
          "notes":[{"id":"n1","content":"Fixed in v2","created_at":"2026-03-19T12:00:00Z"}]
        }]}
        """#
        let h = try decoder.decode(CommentRelayHistory.self, from: Data(raw.utf8))
        XCTAssertFalse(h.isAnonymous)
        XCTAssertEqual(h.submissions.count, 1)
        XCTAssertEqual(h.submissions.first?.notes.first?.content, "Fixed in v2")
    }

    func test_history_decodesAnonymous() throws {
        let raw = #"{"anonymousUser":true,"submissions":[]}"#
        let h = try decoder.decode(CommentRelayHistory.self, from: Data(raw.utf8))
        XCTAssertTrue(h.isAnonymous)
        XCTAssertTrue(h.submissions.isEmpty)
    }
}
