import XCTest
import SwiftUI
import ViewInspector
@testable import CommentRelayUI

// Note: ViewInspector (this version) cannot resolve `Circle`/`Capsule`/`Ellipse` used inside a
// `.background(...)` by view type, so these tests assert the *behavioral* contract that differs
// per shape — which title/glyph is rendered, the tap action, render-success across all three
// shapes, and the size metrics — rather than introspecting the clip shape directly. The shape
// drawing itself is exercised by `swift build` compiling all three branches.
@MainActor
final class CommentRelayConfigurableButtonTests: XCTestCase {

    func test_capsule_rendersTitle() throws {
        let sut = CommentRelayConfigurableButton("Send", shape: .capsule) {}
        XCTAssertNoThrow(try sut.inspect().find(text: "Send"))
    }

    func test_oval_rendersTitle() throws {
        let sut = CommentRelayConfigurableButton("Rate us", shape: .oval) {}
        XCTAssertNoThrow(try sut.inspect().find(text: "Rate us"))
    }

    func test_round_withSystemImage_showsImageNotTitle() throws {
        let sut = CommentRelayConfigurableButton(
            "Feedback", shape: .round, systemImage: "bubble.left"
        ) {}
        XCTAssertNoThrow(try sut.inspect().find(ViewType.Image.self))
        // The full title is not rendered for the round shape when an icon is supplied.
        XCTAssertThrowsError(try sut.inspect().find(text: "Feedback"))
    }

    func test_round_withoutImage_showsFirstGlyph() throws {
        let sut = CommentRelayConfigurableButton("Feedback", shape: .round) {}
        // First character of the title becomes the glyph; the full title is not shown.
        XCTAssertNoThrow(try sut.inspect().find(text: "F"))
        XCTAssertThrowsError(try sut.inspect().find(text: "Feedback"))
    }

    func test_tap_invokesAction() throws {
        var tapped = false
        let sut = CommentRelayConfigurableButton("Send", shape: .capsule) { tapped = true }
        try sut.inspect().find(ViewType.Button.self).tap()
        XCTAssertTrue(tapped)
    }

    func test_defaultColorAndExplicitColorBothRender() throws {
        // nil color falls back to the theme accent; explicit color is accepted. Assert both
        // variants build and render their label (fill-color introspection is brittle in
        // ViewInspector, so we don't read the fill value).
        let themed = CommentRelayConfigurableButton("Send", shape: .capsule, color: nil) {}
        XCTAssertNoThrow(try themed.inspect().find(text: "Send"))

        let explicit = CommentRelayConfigurableButton("Send", shape: .capsule, color: .green) {}
        XCTAssertNoThrow(try explicit.inspect().find(text: "Send"))
    }

    func test_allShapesRender() throws {
        for shape in [CommentRelayButtonShape.round, .oval, .capsule] {
            let sut = CommentRelayConfigurableButton("Go", shape: shape) {}
            XCTAssertNoThrow(try sut.inspect().find(ViewType.Button.self),
                             "shape \(shape) failed to render a button")
        }
    }

    func test_round_diameterScalesWithSize() {
        // The round shape sets an explicit frame from the size; small and large must differ,
        // and ordering is monotonic so larger sizes are visibly larger.
        XCTAssertLessThan(
            CommentRelayButtonSize.small.roundDiameter,
            CommentRelayButtonSize.medium.roundDiameter
        )
        XCTAssertLessThan(
            CommentRelayButtonSize.medium.roundDiameter,
            CommentRelayButtonSize.large.roundDiameter
        )
    }
}
