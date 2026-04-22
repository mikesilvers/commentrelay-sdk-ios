// Tests/CommentRelayUITests/FieldRendererTests/SmileyPathParserTests.swift
import XCTest
import SwiftUI
@testable import CommentRelayUI

final class SmileyPathParserTests: XCTestCase {
    func test_parses_veryUnhappy_mouth() {
        // M8 17 + relative cubic to (16, 17) via controls (9.5,15) and (14.5,15)
        let path = SmileyPathParser.parse(d: "M8 17c1.5-2 6.5-2 8 0")
        XCTAssertNotNil(path)
        XCTAssertFalse(path!.isEmpty)
    }

    func test_parses_unhappy_mouth() {
        let path = SmileyPathParser.parse(d: "M9 16c1-1 5-1 6 0")
        XCTAssertNotNil(path)
    }

    func test_parses_happy_mouth() {
        let path = SmileyPathParser.parse(d: "M9 14c1 1 5 1 6 0")
        XCTAssertNotNil(path)
    }

    func test_parses_veryHappy_mouth() {
        let path = SmileyPathParser.parse(d: "M8 14c1.5 2 6.5 2 8 0")
        XCTAssertNotNil(path)
    }

    func test_returnsNil_forUnknownCommand() {
        XCTAssertNil(SmileyPathParser.parse(d: "M8 17q1 2 3 4"))
    }

    func test_returnsNil_forMissingNumbers() {
        XCTAssertNil(SmileyPathParser.parse(d: "M8"))
    }

    func test_returnsNil_forGarbage() {
        XCTAssertNil(SmileyPathParser.parse(d: "not a path"))
    }

    func test_emptyStringReturnsEmptyPath() {
        let path = SmileyPathParser.parse(d: "")
        XCTAssertNotNil(path)
        XCTAssertTrue(path!.isEmpty)
    }
}
