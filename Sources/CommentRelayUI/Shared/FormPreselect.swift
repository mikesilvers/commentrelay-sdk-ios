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

    /// Resolves the preselected form.
    ///
    /// `.id` is a deep link: it matches the form's UUID **or** its
    /// `client_form_id` slug, and opens that form even when it is hidden from
    /// the picker (`show_in_picker:false`). An inactive form is never surfaced.
    /// `.title` stays picker-visible-only — a fuzzy title must not surface a
    /// hidden form. (Partial reversal of CRLBS-115 for the id path only.)
    func match(in forms: [CommentRelayForm]) -> CommentRelayForm? {
        switch self {
        case .id(let id):
            return forms.first { $0.isActive && ($0.id == id || $0.clientFormId == id) }
        case .title(let title):
            let needle = title.lowercased()
            return forms.filter { $0.isPickerVisible }.first { $0.title.lowercased() == needle }
        }
    }
}
