import XCTest
@testable import CommentRelayCore

final class CommentRelayFormDecodingTests: XCTestCase {
    func test_decodes_clientFormId_whenPresent() throws {
        let json = Data("""
        {"id":"f1","title":"Bug","client_form_id":"check-how-they-feel",
         "show_in_picker":true,"is_active":true,"sort_order":0,"fields":[]}
        """.utf8)
        let form = try JSONDecoder().decode(CommentRelayForm.self, from: json)
        XCTAssertEqual(form.clientFormId, "check-how-they-feel")
    }

    func test_clientFormId_isNil_whenAbsent() throws {
        let json = Data("""
        {"id":"f1","title":"Bug","show_in_picker":true,"is_active":true,
         "sort_order":0,"fields":[]}
        """.utf8)
        let form = try JSONDecoder().decode(CommentRelayForm.self, from: json)
        XCTAssertNil(form.clientFormId)
    }
}
