// Sources/CommentRelayCore/Internal/LocalizationBundle.swift
import Foundation

public enum CommentRelayLocalization {
    nonisolated(unsafe) private static var registered: [String: Bundle] = [:]
    private static let lock = NSLock()

    public static func register(locale: Locale, bundle: Bundle) {
        lock.lock(); defer { lock.unlock() }
        registered[locale.identifier] = bundle
    }

    static func registeredBundle(for locale: Locale) -> Bundle? {
        lock.lock(); defer { lock.unlock() }
        if let b = registered[locale.identifier] { return b }
        if let languageCode = locale.language.languageCode?.identifier,
           let b = registered[languageCode] {
            return b
        }
        return nil
    }

    static func resetForTesting() {
        lock.lock(); defer { lock.unlock() }
        registered.removeAll()
    }
}

final class LocalizationBundle: Sendable {
    static let shared = LocalizationBundle()
    private init() {}

    func string(forKey key: String, locale: Locale = .current) -> String {
        if let registered = CommentRelayLocalization.registeredBundle(for: locale) {
            let value = registered.localizedString(forKey: key, value: key, table: nil)
            if value != key { return value }
        }
        let host = Bundle.main.localizedString(forKey: key, value: key, table: nil)
        if host != key { return host }
        // Plan A ships no localized resources; Plan B adds `CommentRelayUI` bundle with en/es-419.
        // Until then: return the key itself so missing lookups are visibly unlocalised rather than crashing.
        return key
    }
}
