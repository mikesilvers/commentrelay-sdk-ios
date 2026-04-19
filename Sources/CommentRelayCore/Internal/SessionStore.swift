// Sources/CommentRelayCore/Internal/SessionStore.swift
import Foundation
import Security

final class SessionStore: @unchecked Sendable {
    private let service: String
    private let account = "anonymousId"
    private let hostSupplied: String?

    init(service: String, hostSupplied: String?) {
        self.service = service
        self.hostSupplied = hostSupplied
    }

    var isAnonymous: Bool { hostSupplied == nil }

    var effectiveIdentifier: String {
        if let hostSupplied { return hostSupplied }
        if let existing = readKeychain() { return existing }
        let generated = UUID().uuidString
        writeKeychain(generated)
        return generated
    }

    @discardableResult
    func resetAnonymous() -> String {
        deleteKeychain()
        return effectiveIdentifier
    }

    // MARK: - Keychain

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func readKeychain() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, let s = String(data: data, encoding: .utf8) else {
            return nil
        }
        return s
    }

    private func writeKeychain(_ value: String) {
        var attrs = baseQuery()
        attrs[kSecValueData as String] = Data(value.utf8)
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemDelete(baseQuery() as CFDictionary)
        SecItemAdd(attrs as CFDictionary, nil)
    }

    private func deleteKeychain() {
        SecItemDelete(baseQuery() as CFDictionary)
    }
}
