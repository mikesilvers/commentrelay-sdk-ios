// Tests/CommentRelayUITests/ScreenTests/CommentRelayViewTests.swift
import XCTest
import SwiftUI
import ViewInspector
import CommentRelayCore
@testable import CommentRelayUI

@MainActor
final class CommentRelayViewTests: XCTestCase {
    func test_rendersNavigationStack_onInit() throws {
        let config = CommentRelayConfiguration(apiKey: "k", baseURL: URL(string: "http://x")!)
        let sut = CommentRelayView(configuration: config)
        XCTAssertNoThrow(try sut.inspect().find(ViewType.NavigationStack.self))
    }
}
