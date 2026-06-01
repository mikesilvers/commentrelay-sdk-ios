# Implementation Plan: CRLBS-155

**Approach:** One new file (two Sendable enums + public struct CommentRelayConfigurableButton:
View) + one new test file. No edits to existing code.

## New file 1: Sources/CommentRelayUI/Components/CommentRelayConfigurableButton.swift
Enums:
- public enum CommentRelayButtonShape: Sendable { round, oval, capsule }
- public enum CommentRelayButtonSize: Sendable { small, medium, large } with internal metrics:
  font (.subheadline/.body/.title3), hPadding (12/16/22), vPadding (8/11/15),
  roundDiameter (36/44/56).
View:
- private title/shape/size/color/systemImage/action; @Environment(\.commentRelayTheme) theme.
- init(_ title="", shape: = .capsule, size: = .medium, color: Color? = nil, systemImage: String? = nil, action).
- fillColor = color ?? theme.accentColor.
- body: Button(action:){ content }.buttonStyle(.plain).accessibilityIdentifier("crl.configurable_button").
- content @ViewBuilder by shape:
  - round: roundLabel (Image(systemName:) if systemImage else Text(first char of title)) in
    .frame(width/height: roundDiameter), .background(Circle().fill(fillColor)), white fg. Title not rendered.
  - capsule: Text(title).font(size.font).padding(h/v).background(Capsule().fill(fillColor)).white fg.
  - oval: same label/padding as capsule but .background(Ellipse().fill(fillColor)).
- a11y: round+systemImage (icon-only) -> .accessibilityLabel(Text(title)) when title non-empty.
- Doc comments incl. oval-clipping + round-glyph notes.

## New file 2: Tests/CommentRelayUITests/ScreenTests/CommentRelayConfigurableButtonTests.swift
@MainActor XCTestCase, @testable import CommentRelayUI, ViewInspector. Cases:
1 capsule renders title; 2 oval renders title + Ellipse; 3 capsule finds Capsule; 4 round+image
shows Image not title + Circle; 5 round w/o image shows first glyph; 6 tap invokes action;
7 default(nil)+explicit color both render; 8 round small vs large diameter differs.
Fallback if ViewInspector can't resolve a shape type under modifier order: assert
render-success + title/image/glyph behavior (substantive contract); note any fallback in
completion summary, do not silently weaken.

## Build verification
swift build then swift test (full suite), both succeed. Per-file commits.

## NOT changing
Package.swift, CommentRelayTheme, existing components/launcher, resources.

## Risks
ViewInspector shape resolution under chained modifiers finicky (mitigation above).
iOS 18 / Swift 6 — all shape APIs available.
