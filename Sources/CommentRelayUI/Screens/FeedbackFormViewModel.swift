// Sources/CommentRelayUI/Screens/FeedbackFormViewModel.swift
import SwiftUI
import CommentRelayCore

@Observable
public final class FeedbackFormViewModel {
    public let form: CommentRelayForm
    public let userIdentifier: String
    public let platform: Platform
    public let sdkVersion: String?

    public var textValues: [String: String] = [:]
    public var boolValues: [String: Bool] = [:]
    public var intValues: [String: Int] = [:]
    public var photoValues: [String: [PhotoAttachment]] = [:]
    public var contactPreference: ContactPreference = .none
    public var contactDetails: String = ""

    public init(form: CommentRelayForm, userIdentifier: String, platform: Platform, sdkVersion: String?) {
        self.form = form
        self.userIdentifier = userIdentifier
        self.platform = platform
        self.sdkVersion = sdkVersion
    }

    public func setText(_ fieldId: String, _ value: String) { textValues[fieldId] = value }
    public func setBool(_ fieldId: String, _ value: Bool) { boolValues[fieldId] = value }
    public func setInt(_ fieldId: String, _ value: Int?) {
        if let value { intValues[fieldId] = value } else { intValues.removeValue(forKey: fieldId) }
    }
    public func setPhotos(_ fieldId: String, _ value: [PhotoAttachment]) { photoValues[fieldId] = value }

    /// IDs of the fields the user can currently see, per `visibleFields` — i.e. root fields plus the
    /// children of any true/false gate that is switched on.
    ///
    /// Validation and submission MUST both be scoped to this set. Rendering already was; when the other
    /// two were not, a form with a *required* child under an *off* gate was permanently unsubmittable,
    /// because the blocking field was invisible and could not be filled. That is not a hypothetical —
    /// it shipped, and made both of CrimeCode's feedback forms impossible to send.
    private var visibleFieldIds: Set<String> {
        Set(visibleFields(in: form.fields, boolValues: boolValues).map(\.field.id))
    }

    public var isSubmittable: Bool {
        let visible = visibleFieldIds
        for field in form.fields where field.isRequired && visible.contains(field.id) {
            switch field.fieldType {
            case .textbox, .email, .phone, .numeric:
                let v = textValues[field.id] ?? ""
                if v.trimmingCharacters(in: .whitespaces).isEmpty { return false }
            case .trueFalse:
                _ = boolValues[field.id] ?? false
            case .smileyRating, .colorScale:
                if intValues[field.id] == nil { return false }
            case .photo, .attachment:
                if (photoValues[field.id] ?? []).isEmpty { return false }
            case .informational, .unknown:
                continue
            }
        }
        if contactPreference != .none, contactDetails.trimmingCharacters(in: .whitespaces).isEmpty {
            return false
        }
        return true
    }

    private struct RatingValue: Encodable {
        let position: Int
        let label: String?
    }

    public func buildSubmission() -> CommentRelaySubmission {
        var fieldValues: [CommentRelaySubmission.FieldValue] = []
        // Only submit what the user can see. Values entered under a gate that was later switched back off
        // have been WITHDRAWN, and transmitting them anyway would send data the user deliberately
        // retracted — typically the contact details behind a "do you want us to contact you" toggle.
        let visible = visibleFieldIds
        for field in form.fields.sorted(by: { $0.sortOrder < $1.sortOrder }) where visible.contains(field.id) {
            switch field.fieldType {
            case .textbox, .email, .phone, .numeric:
                let v = textValues[field.id] ?? ""
                if !v.isEmpty { fieldValues.append(.text(fieldId: field.id, value: v)) }
            case .trueFalse:
                let v = boolValues[field.id] ?? false
                fieldValues.append(.text(fieldId: field.id, value: v ? "true" : "false"))
            case .smileyRating, .colorScale:
                if let v = intValues[field.id] {
                    let label = field.options?.first(where: { $0.position == v })?.label
                    let rating = RatingValue(position: v, label: label)
                    if let data = try? JSONEncoder().encode(rating),
                       let payload = String(data: data, encoding: .utf8) {
                        fieldValues.append(.text(fieldId: field.id, value: payload))
                    } else {
                        fieldValues.append(.text(fieldId: field.id, value: #"{"position":\#(v)}"#))
                    }
                }
            case .photo, .attachment:
                let atts = photoValues[field.id] ?? []
                if !atts.isEmpty {
                    let meta = atts.map { CommentRelaySubmission.FileMetadata(name: $0.name, type: $0.mimeType, size: $0.size) }
                    fieldValues.append(.files(fieldId: field.id, metadata: meta))
                }
            case .informational, .unknown:
                continue
            }
        }
        return CommentRelaySubmission(
            formId: form.id,
            userIdentifier: userIdentifier,
            platform: platform,
            fields: fieldValues,
            sdkVersion: sdkVersion,
            contactPreference: contactPreference == .none ? nil : contactPreference,
            contactDetails: contactPreference == .none ? nil : contactDetails
        )
    }

    /// All staged photo/attachment payloads as queueable attachments (for submit's offline queue).
    public func queuedAttachments() -> [CommentRelayQueuedAttachment] {
        photoValues.flatMap { fieldId, photos in
            photos.map { photo in
                CommentRelayQueuedAttachment(fieldId: fieldId, fileName: photo.name,
                                             contentType: photo.mimeType, data: photo.data)
            }
        }
    }

    /// Returns all photo/attachment payloads keyed by their field, for the client's uploadFiles call after submit.
    public func filePayloads(for receipt: CommentRelaySubmissionReceipt) -> [CommentRelayFilePayload] {
        var result: [CommentRelayFilePayload] = []
        for target in receipt.uploadUrls {
            guard let atts = photoValues[target.fieldId] else { continue }
            if let att = atts.first(where: { $0.name == target.fileName }) {
                result.append(CommentRelayFilePayload(target: target, data: att.data, contentType: att.mimeType))
            }
        }
        return result
    }
}
