// Tests/CommentRelayUITests/FieldRendererTests/SmileySVGParserTests.swift
import XCTest
@testable import CommentRelayUI

final class SmileySVGParserTests: XCTestCase {
    func test_parses_veryUnhappy_colorsAndMouth() throws {
        let parsed = try XCTUnwrap(SmileySVGParser.parse(svg: SmileySVGFixtures.veryUnhappy))
        XCTAssertEqual(parsed.faceFillHex, "#FF4444")
        XCTAssertEqual(parsed.faceStrokeHex, "#CC0000")
        XCTAssertEqual(parsed.featureHex, "#CC0000")
        guard case .path(let d) = parsed.mouth else { return XCTFail("expected path mouth") }
        XCTAssertEqual(d, "M8 17c1.5-2 6.5-2 8 0")
    }

    func test_parses_unhappy_colorsAndMouth() throws {
        let parsed = try XCTUnwrap(SmileySVGParser.parse(svg: SmileySVGFixtures.unhappy))
        XCTAssertEqual(parsed.faceFillHex, "#FF8844")
        XCTAssertEqual(parsed.faceStrokeHex, "#CC5500")
        XCTAssertEqual(parsed.featureHex, "#CC5500")
        guard case .path(let d) = parsed.mouth else { return XCTFail("expected path mouth") }
        XCTAssertEqual(d, "M9 16c1-1 5-1 6 0")
    }

    func test_parses_neutral_usesLineMouth() throws {
        let parsed = try XCTUnwrap(SmileySVGParser.parse(svg: SmileySVGFixtures.neutral))
        XCTAssertEqual(parsed.faceFillHex, "#FFCC44")
        XCTAssertEqual(parsed.faceStrokeHex, "#CC9900")
        XCTAssertEqual(parsed.featureHex, "#CC9900")
        guard case .line(let x1, let y1, let x2, let y2) = parsed.mouth else {
            return XCTFail("expected line mouth")
        }
        XCTAssertEqual(x1, 8.5, accuracy: 0.001)
        XCTAssertEqual(y1, 15, accuracy: 0.001)
        XCTAssertEqual(x2, 15.5, accuracy: 0.001)
        XCTAssertEqual(y2, 15, accuracy: 0.001)
    }

    func test_parses_happy_colorsAndMouth() throws {
        let parsed = try XCTUnwrap(SmileySVGParser.parse(svg: SmileySVGFixtures.happy))
        XCTAssertEqual(parsed.faceFillHex, "#88CC44")
        XCTAssertEqual(parsed.faceStrokeHex, "#559900")
        guard case .path(let d) = parsed.mouth else { return XCTFail("expected path mouth") }
        XCTAssertEqual(d, "M9 14c1 1 5 1 6 0")
    }

    func test_parses_veryHappy_colorsAndMouth() throws {
        let parsed = try XCTUnwrap(SmileySVGParser.parse(svg: SmileySVGFixtures.veryHappy))
        XCTAssertEqual(parsed.faceFillHex, "#44BB44")
        XCTAssertEqual(parsed.faceStrokeHex, "#228822")
        guard case .path(let d) = parsed.mouth else { return XCTFail("expected path mouth") }
        XCTAssertEqual(d, "M8 14c1.5 2 6.5 2 8 0")
    }

    func test_returnsNil_forEmptyString() {
        XCTAssertNil(SmileySVGParser.parse(svg: ""))
    }

    func test_returnsNil_forMalformedXML() {
        XCTAssertNil(SmileySVGParser.parse(svg: "<svg><circle"))
    }

    func test_returnsNil_forPlaceholderSvg() {
        // The <svg/> placeholder used in some test helpers has no face circle.
        XCTAssertNil(SmileySVGParser.parse(svg: "<svg/>"))
    }

    func test_returnsNil_whenPathUnparseable() {
        // face + eyes valid, but mouth `d` uses an unsupported command ('q').
        let svg = ##"<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="10" fill="#FF0000" stroke="#000000" stroke-width="1"/><circle cx="8.5" cy="9.5" r="1.5" fill="#000000"/><circle cx="15.5" cy="9.5" r="1.5" fill="#000000"/><path d="M8 17q1 2 3 4" stroke="#000000" stroke-width="1.5" fill="none"/></svg>"##
        XCTAssertNil(SmileySVGParser.parse(svg: svg))
    }
}
