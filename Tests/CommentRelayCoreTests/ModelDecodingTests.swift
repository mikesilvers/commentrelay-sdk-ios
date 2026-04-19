import XCTest
@testable import CommentRelayCore

final class ModelDecodingTests: XCTestCase {
    private let decoder = JSONDecoder()

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
}
