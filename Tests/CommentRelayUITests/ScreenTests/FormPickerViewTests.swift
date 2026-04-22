import XCTest
import SwiftUI
import ViewInspector
import CommentRelayCore
@testable import CommentRelayUI

final class FormPickerViewTests: XCTestCase {
    func test_filtersOut_showInPickerFalse() throws {
        let raw = #"""
        [
          {"id":"a","title":"Bug","show_in_picker":true,"response_limit_count":null,"response_limit_type":null,"response_limit_window_minutes":null,"more_feedback_prompt":null,"is_active":true,"sort_order":1,"fields":[]},
          {"id":"b","title":"Hidden","show_in_picker":false,"response_limit_count":null,"response_limit_type":null,"response_limit_window_minutes":null,"more_feedback_prompt":null,"is_active":true,"sort_order":2,"fields":[]}
        ]
        """#
        let forms = try JSONDecoder().decode([CommentRelayForm].self, from: Data(raw.utf8))

        let sut = FormPickerView(forms: forms, onSelect: { _ in })
        XCTAssertNoThrow(try sut.inspect().find(text: "Bug"))
        XCTAssertThrowsError(try sut.inspect().find(text: "Hidden"))
    }

    func test_emptyForms_rendersEmptyState() throws {
        let sut = FormPickerView(forms: [], onSelect: { _ in })
        XCTAssertNoThrow(try sut.inspect().find(text: Strings.pickerEmpty))
    }
}
