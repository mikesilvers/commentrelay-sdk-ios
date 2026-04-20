// Sources/CommentRelayUI/Shared/ContactPreferenceSection.swift
import SwiftUI
import CommentRelayCore

public struct ContactPreferenceSection: View {
    @Binding public var preference: ContactPreference
    @Binding public var details: String

    public init(preference: Binding<ContactPreference>, details: Binding<String>) {
        self._preference = preference
        self._details = details
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Strings.contactHeader)
                .font(.headline)

            Picker(Strings.contactHeader, selection: $preference) {
                Text(Strings.contactNone).tag(ContactPreference.none)
                Text(Strings.contactEmail).tag(ContactPreference.email)
                Text(Strings.contactText).tag(ContactPreference.text)
                Text(Strings.contactPhoneCall).tag(ContactPreference.phoneCall)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if preference != .none {
                TextField(Strings.contactDetailsPlaceholder, text: $details)
                    .textFieldStyle(.roundedBorder)
                    #if canImport(UIKit)
                    .textInputAutocapitalization(preference == .email ? .never : .sentences)
                    .autocorrectionDisabled(preference != .text)
                    .keyboardType(preference == .email ? .emailAddress : (preference == .phoneCall || preference == .text ? .phonePad : .default))
                    #endif
            }
        }
    }
}
