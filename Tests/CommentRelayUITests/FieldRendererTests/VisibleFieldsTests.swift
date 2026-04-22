// Tests/CommentRelayUITests/FieldRendererTests/VisibleFieldsTests.swift
import XCTest
import CommentRelayCore
@testable import CommentRelayUI

final class VisibleFieldsTests: XCTestCase {
    func test_flatFields_allVisible_atDepthZero() {
        let a = FakeField.textbox(id: "a", sortOrder: 1)
        let b = FakeField.textbox(id: "b", sortOrder: 2)
        let result = visibleFields(in: [b, a], boolValues: [:])
        XCTAssertEqual(result.map(\.field.id), ["a", "b"])
        XCTAssertTrue(result.allSatisfy { $0.depth == 0 })
    }

    func test_trueFalseChild_hiddenWhenParentOff() {
        let parent = FakeField.trueFalse(id: "p", sortOrder: 0)
        let child = FakeField.email(id: "c", required: false, sortOrder: 1, parentId: "p")
        let result = visibleFields(in: [parent, child], boolValues: [:])
        XCTAssertEqual(result.map(\.field.id), ["p"])
    }

    func test_trueFalseChild_visibleWhenParentOn_atDepthOne() {
        let parent = FakeField.trueFalse(id: "p", sortOrder: 0)
        let child = FakeField.email(id: "c", required: false, sortOrder: 1, parentId: "p")
        let result = visibleFields(in: [parent, child], boolValues: ["p": true])
        XCTAssertEqual(result.map(\.field.id), ["p", "c"])
        XCTAssertEqual(result[1].depth, 1)
    }

    func test_nonTrueFalseParent_neverGatesChildren() {
        // A textbox with `parent_field_id` children must never show them —
        // only `true_false` fields can carry a conditional toggle.
        let parent = FakeField.textbox(id: "p", sortOrder: 0)
        let child = FakeField.email(id: "c", required: false, sortOrder: 1, parentId: "p")
        let result = visibleFields(in: [parent, child], boolValues: ["p": true])
        XCTAssertEqual(result.map(\.field.id), ["p"])
    }

    func test_twoLevelNesting_bothParentsMustBeOn() {
        let root = FakeField.trueFalse(id: "root", sortOrder: 0)
        let mid = FakeField.trueFalse(id: "mid", sortOrder: 0, parentId: "root")
        let leaf = FakeField.email(id: "leaf", required: false, sortOrder: 0, parentId: "mid")

        // Only root on: mid appears, leaf doesn't.
        let r1 = visibleFields(in: [root, mid, leaf], boolValues: ["root": true])
        XCTAssertEqual(r1.map(\.field.id), ["root", "mid"])

        // Root + mid on: all three appear with depths 0,1,2.
        let r2 = visibleFields(in: [root, mid, leaf], boolValues: ["root": true, "mid": true])
        XCTAssertEqual(r2.map(\.field.id), ["root", "mid", "leaf"])
        XCTAssertEqual(r2.map(\.depth), [0, 1, 2])
    }

    func test_orphanedChild_isIgnored() {
        // Child references a parent that doesn't exist in the field list.
        let child = FakeField.email(id: "c", required: false, sortOrder: 1, parentId: "missing")
        let result = visibleFields(in: [child], boolValues: [:])
        XCTAssertTrue(result.isEmpty)
    }
}
