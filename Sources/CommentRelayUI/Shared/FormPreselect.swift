// Sources/CommentRelayUI/Shared/FormPreselect.swift
import CommentRelayCore

/// Describes a single form the integrator wants to jump straight to,
/// bypassing the picker. If both an ID and a title are supplied, the ID wins.
enum FormPreselect: Equatable {
    case id(String)
    case title(String)

    init?(formId: String?, formTitle: String?) {
        if let formId {
            self = .id(formId)
        } else if let formTitle {
            self = .title(formTitle)
        } else {
            return nil
        }
    }

    /// Matches case-insensitively on title.
    ///
    /// Only forms that would be visible in the picker (`isActive && showInPicker`)
    /// are eligible: a preselect must never surface a form the end user is not
    /// allowed to see, even when targeted explicitly by id or title.
    func match(in forms: [CommentRelayForm]) -> CommentRelayForm? {
        let selectable = forms.filter { $0.isPickerVisible }
        switch self {
        case .id(let id):
            return selectable.first { $0.id == id }
        case .title(let title):
            let needle = title.lowercased()
            return selectable.first { $0.title.lowercased() == needle }
        }
    }
}
