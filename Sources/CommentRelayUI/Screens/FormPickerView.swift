import SwiftUI
import CommentRelayCore

public struct FormPickerView: View {
    public let forms: [CommentRelayForm]
    public let onSelect: @Sendable (CommentRelayForm) -> Void

    public init(forms: [CommentRelayForm], onSelect: @escaping @Sendable (CommentRelayForm) -> Void) {
        self.forms = forms
        self.onSelect = onSelect
    }

    private var visible: [CommentRelayForm] {
        forms
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
                    ForEach(visible) { form in
                        FormRow(form: form) {
                            onSelect(form)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(Strings.pickerTitle)
    }
}

private struct FormRow: View {
    let form: CommentRelayForm
    let onTap: @Sendable () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(form.title)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
    }
}
