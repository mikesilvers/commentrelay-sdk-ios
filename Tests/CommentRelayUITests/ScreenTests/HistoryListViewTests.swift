import XCTest
import SwiftUI
import ViewInspector
import CommentRelayCore
@testable import CommentRelayUI

final class HistoryListViewTests: XCTestCase {
    private func history(entries: Int, anonymous: Bool) -> CommentRelayHistory {
        var items = ""
        for i in 0..<entries {
            items += #"{"id":"\#(UUID().uuidString)","form_id":"c","form_title":"Bug","status":"complete","created_at":"2026-03-19T10:30:0\#(i)Z","notes":[]}"#
            if i < entries - 1 { items += "," }
        }
        let raw = #"{"anonymousUser":\#(anonymous),"submissions":[\#(items)]}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try! decoder.decode(CommentRelayHistory.self, from: Data(raw.utf8))
    }

    func test_anonymousEmpty_rendersAnonymousCopy() throws {
        let sut = HistoryListView(history: history(entries: 0, anonymous: true), onSelect: { _ in })
        XCTAssertNoThrow(try sut.inspect().find(text: Strings.historyEmptyAnonymous))
    }

    func test_identifiedEmpty_rendersIdentifiedCopy() throws {
        let sut = HistoryListView(history: history(entries: 0, anonymous: false), onSelect: { _ in })
        XCTAssertNoThrow(try sut.inspect().find(text: Strings.historyEmptyIdentified))
    }

    func test_nonEmpty_rendersOneRowPerEntry() throws {
        let h = history(entries: 2, anonymous: false)
        let sut = HistoryListView(history: h, onSelect: { _ in })
        let buttons = try sut.inspect().findAll(ViewType.Button.self)
        XCTAssertGreaterThanOrEqual(buttons.count, 2)
    }
}
