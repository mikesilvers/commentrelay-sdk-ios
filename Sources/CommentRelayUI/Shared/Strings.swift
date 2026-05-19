// Sources/CommentRelayUI/Shared/Strings.swift
import Foundation
import CommentRelayCore

enum Strings {
    static func string(_ key: String, locale: Locale = .current) -> String {
        if let registered = CommentRelayLocalization.registeredBundle(for: locale) {
            let value = registered.localizedString(forKey: key, value: key, table: nil)
            if value != key { return value }
        }
        let host = Bundle.main.localizedString(forKey: key, value: key, table: nil)
        if host != key { return host }
        return Bundle.module.localizedString(forKey: key, value: key, table: nil)
    }

    // Convenience accessors — one per key to catch typos at compile time.
    static var sheetTitle: String { string("crl.sheet.title") }
    static var sheetCancel: String { string("crl.sheet.cancel") }
    static var pickerTitle: String { string("crl.picker.title") }
    static var pickerEmpty: String { string("crl.picker.empty") }
    static var formSubmit: String { string("crl.form.submit") }
    static var formSending: String { string("crl.form.sending") }
    static var formRequired: String { string("crl.form.required") }
    static var formOptional: String { string("crl.form.optional") }
    static var contactHeader: String { string("crl.contact.header") }
    static var contactNone: String { string("crl.contact.none") }
    static var contactEmail: String { string("crl.contact.email") }
    static var contactText: String { string("crl.contact.text") }
    static var contactPhoneCall: String { string("crl.contact.phone_call") }
    static var contactDetailsPlaceholder: String { string("crl.contact.details_placeholder") }
    static var progressTitle: String { string("crl.progress.title") }
    static var thanksTitle: String { string("crl.thanks.title") }
    static var thanksBody: String { string("crl.thanks.body") }
    static var thanksViewHistory: String { string("crl.thanks.view_history") }
    static var thanksDone: String { string("crl.thanks.done") }
    static var historyTitle: String { string("crl.history.title") }
    static var historyEmptyIdentified: String { string("crl.history.empty_identified") }
    static var historyEmptyAnonymous: String { string("crl.history.empty_anonymous") }
    static var historyNotesHeader: String { string("crl.history.notes_header") }
    static var draftRestoreTitle: String { string("crl.draft.restore_title") }
    static var draftRestoreBody: String { string("crl.draft.restore_body") }
    static var draftResume: String { string("crl.draft.resume") }
    static var draftStartOver: String { string("crl.draft.start_over") }
    static var errorGeneric: String { string("crl.error.generic") }
    static var errorPaymentRequired: String { string("crl.error.payment_required") }
    static var errorRateLimited: String { string("crl.error.rate_limited") }
    static var errorUploadFailed: String { string("crl.error.upload_failed") }
    static var photoAdd: String { string("crl.photo.add") }
    static var photoRemove: String { string("crl.photo.remove") }
    static var attachmentAdd: String { string("crl.attachment.add") }

    static func characterCount(_ current: Int, _ max: Int) -> String {
        String(format: string("crl.form.character_count_format"), locale: .current, current, max)
    }

    static func progressFile(_ name: String) -> String {
        String(format: string("crl.progress.file_format"), locale: .current, name)
    }

    static func smileyLabel(position: Int) -> String {
        switch position {
        case 1: return string("crl.rating.smiley_very_unhappy")
        case 2: return string("crl.rating.smiley_unhappy")
        case 3: return string("crl.rating.smiley_neutral")
        case 4: return string("crl.rating.smiley_happy")
        case 5: return string("crl.rating.smiley_very_happy")
        default: return ""
        }
    }
}
