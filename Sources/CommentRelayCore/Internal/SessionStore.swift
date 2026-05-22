// Sources/CommentRelayCore/Internal/SessionStore.swift
import Foundation
import Security

/// Abstraction over the three Keychain operations SessionStore performs.
/// Production uses `SystemKeychain` (real `SecItem*`); tests inject an
/// in-memory double. SPM iOS test bundles run without a host app, so the real
/// Keychain doesn't persist there — the seam keeps the identifier logic
/// testable on every platform (CRLBS-124).
protocol KeychainBacking: Sendable {
    func read(service: String, account: String) -> String?
    func write(_ value: String, service: String, account: String)
    func delete(service: String, account: String)
}

/// Real Keychain backing. Holds no mutable state, so it is `Sendable` directly.
struct SystemKeychain: KeychainBacking {
    private func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func read(service: String, account: String) -> String? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, let s = String(data: data, encoding: .utf8) else {
            return nil
        }
        return s
    }

    func write(_ value: String, service: String, account: String) {
        var attrs = baseQuery(service: service, account: account)
        attrs[kSecValueData as String] = Data(value.utf8)
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
        SecItemAdd(attrs as CFDictionary, nil)
    }

    func delete(service: String, account: String) {
        SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
    }
}

final class SessionStore: @unchecked Sendable {
    private let service: String
    private let account = "anonymousId"
    private let hostSupplied: String?
    private let keychain: KeychainBacking

    init(service: String, hostSupplied: String?, keychain: KeychainBacking = SystemKeychain()) {
        self.service = service
        self.hostSupplied = hostSupplied
        self.keychain = keychain
    }

    var isAnonymous: Bool { hostSupplied == nil }

    var effectiveIdentifier: String {
        if let hostSupplied { return hostSupplied }
        if let existing = keychain.read(service: service, account: account) { return existing }
        let generated = UUID().uuidString
        keychain.write(generated, service: service, account: account)
        return generated
    }

    @discardableResult
    func resetAnonymous() -> String {
        keychain.delete(service: service, account: account)
        return effectiveIdentifier
    }
}
