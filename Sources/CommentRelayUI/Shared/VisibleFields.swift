// Sources/CommentRelayUI/Shared/VisibleFields.swift
import CommentRelayCore

struct VisibleField: Equatable {
    let field: CommentRelayField
    let depth: Int
}

/// Flattens `fields` into a depth-annotated list honouring the API's
/// conditional-field rule: a child field (`parent_field_id != nil`) only
/// renders when its parent is a `true_false` field that's currently toggled
/// on in `boolValues`. Orphans (whose parent isn't in the list) are dropped.
func visibleFields(in fields: [CommentRelayField], boolValues: [String: Bool]) -> [VisibleField] {
    let sorted = fields.sorted { $0.sortOrder < $1.sortOrder }
    let roots = sorted.filter { $0.parentFieldId == nil }
    let childrenByParent = Dictionary(grouping: sorted.filter { $0.parentFieldId != nil }) { $0.parentFieldId! }

    var result: [VisibleField] = []
    func emit(_ field: CommentRelayField, depth: Int) {
        result.append(VisibleField(field: field, depth: depth))
        guard field.fieldType == .trueFalse, boolValues[field.id] == true else { return }
        for kid in childrenByParent[field.id] ?? [] {
            emit(kid, depth: depth + 1)
        }
    }
    for root in roots { emit(root, depth: 0) }
    return result
}
