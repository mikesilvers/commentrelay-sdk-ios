// Tests/CommentRelayUITests/ScreenTests/ContactPreferenceSectionTests.swift
import XCTest
import SwiftUI
import ViewInspector
import CommentRelayCore
@testable import CommentRelayUI

final class ContactPreferenceSectionTests: XCTestCase {
    func test_detailsHidden_whenPreferenceIsNone() throws {
        var pref: ContactPreference = .none
        var details = ""
        let sut = ContactPreferenceSection(
            preference: Binding(get: { pref }, set: { pref = $0 }),
            details: Binding(get: { details }, set: { details = $0 })
        )
        XCTAssertThrowsError(try sut.inspect().find(ViewType.TextField.self))
    }

    func test_detailsVisible_whenPreferenceIsEmail() throws {
        var pref: ContactPreference = .email
        var details = "a@b.c"
        let sut = ContactPreferenceSection(
            preference: Binding(get: { pref }, set: { pref = $0 }),
            details: Binding(get: { details }, set: { details = $0 })
        )
        XCTAssertNoThrow(try sut.inspect().find(ViewType.TextField.self))
    }
}
