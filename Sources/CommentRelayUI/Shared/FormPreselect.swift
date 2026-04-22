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
    func match(in forms: [CommentRelayForm]) -> CommentRelayForm? {
        switch self {
        case .id(let id):
            return forms.first { $0.id == id }
        case .title(let title):
            let needle = title.lowercased()
            return forms.first { $0.title.lowercased() == needle }
        }
    }
}
