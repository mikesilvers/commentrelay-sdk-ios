# Spec: CRLBS-155 — configurable button component (iOS SDK)

**Type:** Story | **Complexity:** Medium
**Repo:** commentrelay-sdk-ios | **Branch:** feature/CRLBS-155-configurable-button
**Build verification:** `swift build` + `swift test`

## Requirements
Reusable public SwiftUI button in CommentRelayUI/Components/ configurable by shape, color,
title, size — building block for future SDK launcher/CTA buttons. This ticket = component +
tests only; wiring into a feature is separate.

## Public API (house style: public struct, Sendable enums, defaults, theme fallback)
- enum CommentRelayButtonShape: Sendable { round, oval, capsule }
- enum CommentRelayButtonSize: Sendable { small, medium, large }
- struct CommentRelayConfigurableButton: View
  init(_ title: String = "", shape: = .capsule, size: = .medium, color: Color? = nil,
       systemImage: String? = nil, action: @escaping () -> Void)

## Behavior
- round: fixed-diameter Circle (from size); renders systemImage else first char of title; title
  NOT used to size the circle.
- oval: true Ellipse, sized to the title (label+padding = content box, ellipse circumscribes).
- capsule: SwiftUI Capsule (pill), sized to the title.
- color: fills shape; nil -> @Environment(\.commentRelayTheme).accentColor. Foreground white
  (matches PendingBadge).
- size: small/medium/large drives font + padding + round diameter (one source of truth).
- tap runs `action` (plain closure; presentation-agnostic — does NOT open the feedback sheet,
  unlike the existing CommentRelayButton launcher).
- a11y: accessibilityIdentifier("crl.configurable_button"); label = title (or accessibilityLabel
  when icon-only); buttonStyle(.plain) so our shape/fill is the visual.

## Files
- New: Sources/CommentRelayUI/Components/CommentRelayConfigurableButton.swift (enums + view)
- New: Tests/CommentRelayUITests/ScreenTests/CommentRelayConfigurableButtonTests.swift
- No changes to Package.swift, theme, or existing components.

## Tests (ViewInspector/XCTest, matching PendingBadgeTests)
- Title renders for capsule & oval; tap invokes action.
- Round with systemImage renders image and NOT the title text; round w/o image shows glyph.
- Each shape renders its clip shape (Circle/Ellipse/Capsule).
- color nil -> theme accent; explicit color applied.
- Size variants differ (distinct round diameter small vs large).

## NOT changing / out of scope
- Existing CommentRelayButton launcher (kept as-is).
- Wiring into any real launcher/feature (future ticket).
- No new theme fields; no docs (SDK has no openapi).

## Risks
- Swift 6 / iOS 18 min — Ellipse, Capsule, .continuous available.
- True-ellipse oval can clip wide titles at extreme aspect ratios; padding tuned for normal titles.
- ViewInspector finds shapes/text, not pixel geometry; size assertions check the explicit .frame
  on .round, not rendered ellipse bounds.
