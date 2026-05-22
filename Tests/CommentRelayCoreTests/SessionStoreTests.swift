// Tests/CommentRelayCoreTests/SessionStoreTests.swift
import XCTest
@testable import CommentRelayCore

/// In-memory KeychainBacking double (CRLBS-124). Mirrors the real Keychain's
/// process-wide-shared, thread-safe semantics so a single instance shared
/// between two SessionStores behaves like the real shared Keychain — without
/// the SPM-iOS-test-bundle limitation that breaks the real one.
final class InMemoryKeychain: KeychainBacking, @unchecked Sendable {
    private let lock = NSLock()
    private var store: [String: String] = [:]
    private func key(_ service: String, _ account: String) -> String { "\(service)\u{0}\(account)" }

    func read(service: String, account: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return store[key(service, account)]
    }
    func write(_ value: String, service: String, account: String) {
        lock.lock(); defer { lock.unlock() }
        store[key(service, account)] = value
    }
    func delete(service: String, account: String) {
        lock.lock(); defer { lock.unlock() }
        store[key(service, account)] = nil
    }
}

final class SessionStoreTests: XCTestCase {
    func test_hostSupplied_wins() {
        let store = SessionStore(
            service: "crl.test.\(UUID().uuidString)",
            hostSupplied: "host-user-1",
            keychain: InMemoryKeychain())
        XCTAssertEqual(store.effectiveIdentifier, "host-user-1")
        XCTAssertFalse(store.isAnonymous)
    }

    func test_anonymousId_isStableAcrossInstances() {
        let service = "crl.test.\(UUID().uuidString)"
        let backing = InMemoryKeychain()   // shared between both stores
        let a = SessionStore(service: service, hostSupplied: nil, keychain: backing)
        let b = SessionStore(service: service, hostSupplied: nil, keychain: backing)
        XCTAssertEqual(a.effectiveIdentifier, b.effectiveIdentifier)
        XCTAssertTrue(a.isAnonymous)
    }

    func test_anonymousId_persists_after_write() {
        let service = "crl.test.\(UUID().uuidString)"
        let backing = InMemoryKeychain()
        let first = SessionStore(service: service, hostSupplied: nil, keychain: backing).effectiveIdentifier
        // A fresh store on the same backing must read the persisted id, not regenerate.
        let second = SessionStore(service: service, hostSupplied: nil, keychain: backing).effectiveIdentifier
        XCTAssertEqual(first, second)
    }

    func test_reset_generatesNewId() {
        let service = "crl.test.\(UUID().uuidString)"
        let backing = InMemoryKeychain()
        let store = SessionStore(service: service, hostSupplied: nil, keychain: backing)
        let firstId = store.effectiveIdentifier
        store.resetAnonymous()
        let secondId = store.effectiveIdentifier
        XCTAssertNotEqual(firstId, secondId)
    }
}
