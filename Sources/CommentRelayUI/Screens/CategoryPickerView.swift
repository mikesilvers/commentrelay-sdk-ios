import SwiftUI
import CommentRelayCore

public struct CategoryPickerView: View {
    public let categories: [CommentRelayCategory]
    public let onSelect: @Sendable (CommentRelayCategory) -> Void

    public init(categories: [CommentRelayCategory], onSelect: @escaping @Sendable (CommentRelayCategory) -> Void) {
        self.categories = categories
        self.onSelect = onSelect
    }

    private var visible: [CommentRelayCategory] {
        categories
            .filter { $0.isActive && $0.showInPicker }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    public var body: some View {
        Group {
            if visible.isEmpty {
                EmptyStateView(
                    systemImage: "tray",
                    title: Strings.pickerTitle,
                    message: Strings.pickerEmpty
                )
            } else {
                List {
                    ForEach(visible) { category in
                        CategoryRow(category: category) {
                            onSelect(category)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(Strings.pickerTitle)
    }
}

private struct CategoryRow: View {
    let category: CommentRelayCategory
    let onTap: @Sendable () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(category.title)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
    }
}
