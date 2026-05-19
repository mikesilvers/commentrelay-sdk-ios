// Tests/CommentRelayUITests/ScreenTests/CommentRelayButtonTests.swift
import XCTest
import SwiftUI
import ViewInspector
import CommentRelayCore
@testable import CommentRelayUI

@MainActor
final class CommentRelayButtonTests: XCTestCase {
    func test_rendersLabelClosure() throws {
        let config = CommentRelayConfiguration(apiKey: "k", baseURL: URL(string: "http://x")!)
        let sut = CommentRelayButton(configuration: config) {
            Text("Send feedback")
        }
        XCTAssertNoThrow(try sut.inspect().find(text: "Send feedback"))
    }
}
