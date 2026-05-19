# macOS feedback sheet: auto-size & resizable

## Problem
On macOS the CommentRelay feedback sheet opens collapsed to roughly a single
line, forcing the user to scroll inside it. Cause: SwiftUI `.sheet` on macOS
sizes to the content's ideal size and is not user-resizable by default.
`CommentRelayView` is a `NavigationStack` wrapping a `ScrollView` form with no
intrinsic size, so the sheet collapses and its inner `ScrollView` scrolls.
Reproduced via the macOS sample app ("Send feedback").

## Fix
In the SDK launcher `Sources/CommentRelayUI/Launchers/CommentRelaySheetModifier.swift`,
wrap the presented `CommentRelayView` in a macOS-only frame:

- `minWidth: 420, idealWidth: 480`
- `minHeight: 520, idealHeight: 640`
- Guarded by `#if os(macOS)` — iOS/iPadOS/visionOS unchanged.

macOS sheets honor an explicit frame: it opens auto-sized to the ideal size
(options fit, no forced scrolling) and stays drag-resizable down to the min.
No public API change; no behavior change off macOS.

## Alternatives rejected
- Fixing only in the sample app's `ContentView`: leaves the broken macOS UX
  shipped to every SDK consumer.
- `presentationDetents`: iOS-only, no effect on macOS.

## Verification
`swift build`, then run the macOS sample and confirm the feedback sheet opens
fully sized and is drag-resizable.
