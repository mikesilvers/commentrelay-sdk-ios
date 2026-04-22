import XCTest
import SwiftUI
import ViewInspector
import CommentRelayCore
@testable import CommentRelayUI

final class HistoryDetailViewTests: XCTestCase {
    func test_rendersNotesHeader_whenNotesPresent() throws {
        let raw = #"""
        {"id":"22222222-2222-2222-2222-222222222222","form_id":"c","form_title":"Bug","status":"complete","created_at":"2026-03-19T10:30:00Z","notes":[
          {"id":"n1","content":"Fixed in v2","created_at":"2026-03-19T12:00:00Z"}]}
        """#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entry = try decoder.decode(CommentRelayHistoryEntry.self, from: Data(raw.utf8))
        let sut = HistoryDetailView(entry: entry)
        XCTAssertNoThrow(try sut.inspect().find(text: Strings.historyNotesHeader))
        XCTAssertNoThrow(try sut.inspect().find(text: "Fixed in v2"))
    }
}
