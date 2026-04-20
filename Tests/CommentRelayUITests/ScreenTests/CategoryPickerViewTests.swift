import XCTest
import SwiftUI
import ViewInspector
import CommentRelayCore
@testable import CommentRelayUI

final class CategoryPickerViewTests: XCTestCase {
    func test_filtersOut_showInPickerFalse() throws {
        let raw = #"""
        [
          {"id":"a","title":"Bug","show_in_picker":true,"response_limit_count":null,"response_limit_type":null,"response_limit_window_days":null,"more_feedback_prompt":null,"is_active":true,"sort_order":1,"fields":[]},
          {"id":"b","title":"Hidden","show_in_picker":false,"response_limit_count":null,"response_limit_type":null,"response_limit_window_days":null,"more_feedback_prompt":null,"is_active":true,"sort_order":2,"fields":[]}
        ]
        """#
        let categories = try JSONDecoder().decode([CommentRelayCategory].self, from: Data(raw.utf8))

        let sut = CategoryPickerView(categories: categories, onSelect: { _ in })
        XCTAssertNoThrow(try sut.inspect().find(text: "Bug"))
        XCTAssertThrowsError(try sut.inspect().find(text: "Hidden"))
    }

    func test_emptyCategories_rendersEmptyState() throws {
        let sut = CategoryPickerView(categories: [], onSelect: { _ in })
        XCTAssertNoThrow(try sut.inspect().find(text: Strings.pickerEmpty))
    }
}
