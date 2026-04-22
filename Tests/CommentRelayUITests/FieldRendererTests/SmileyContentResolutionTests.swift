// Tests/CommentRelayUITests/FieldRendererTests/SmileyContentResolutionTests.swift
import XCTest
import CommentRelayCore
@testable import CommentRelayUI

final class SmileyContentResolutionTests: XCTestCase {
    func test_content_usesParsedSVG_whenValid() {
        let field = FakeField.smileyRatingWithRealSVG()
        let content = SmileyContent.resolve(position: 1, options: field.options)
        guard case .parsed(let p) = content else {
            return XCTFail("expected parsed, got \(content)")
        }
        XCTAssertEqual(p.faceFillHex, "#FF4444")
    }

    func test_content_fallsBack_forPlaceholderSVG() {
        let field = FakeField.smileyRating()  // "<svg/>" placeholder
        let content = SmileyContent.resolve(position: 1, options: field.options)
        guard case .fallback(let pos) = content else {
            return XCTFail("expected fallback, got \(content)")
        }
        XCTAssertEqual(pos, 1)
    }

    func test_content_fallsBack_whenOptionsNil() {
        let field = FakeField.smileyRatingNoOptions()
        let content = SmileyContent.resolve(position: 3, options: field.options)
        guard case .fallback = content else {
            return XCTFail("expected fallback, got \(content)")
        }
    }

    func test_content_fallsBack_whenPositionMissing() {
        let field = FakeField.smileyRatingWithRealSVG()
        let content = SmileyContent.resolve(position: 99, options: field.options)
        guard case .fallback = content else {
            return XCTFail("expected fallback for unknown position")
        }
    }
}
