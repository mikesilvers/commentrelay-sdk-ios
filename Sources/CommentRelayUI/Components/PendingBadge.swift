import SwiftUI

/// Minimal, platform-neutral pending-count badge. Hidden when count == 0.
public struct PendingBadge: View {
    public let count: Int
    public init(count: Int) { self.count = count }
    public var body: some View {
        Group {
            if count > 0 {
                Text("\(count)")
                    .font(.caption2).bold()
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(.red))
                    .foregroundStyle(.white)
                    .accessibilityLabel(Text("\(count) pending feedback submissions"))
            }
        }
    }
}
