// Tests/CommentRelayCoreTests/SessionStoreTests.swift
import XCTest
@testable import CommentRelayCore

final class SessionStoreTests: XCTestCase {
    func test_hostSupplied_wins() {
        let store = SessionStore(service: "crl.test.\(UUID().uuidString)", hostSupplied: "host-user-1")
        XCTAssertEqual(store.effectiveIdentifier, "host-user-1")
        XCTAssertFalse(store.isAnonymous)
    }

    func test_anonymousId_isStableAcrossInstances() {
        let service = "crl.test.\(UUID().uuidString)"
        defer { _ = SessionStore(service: service, hostSupplied: nil).resetAnonymous() }

        let a = SessionStore(service: service, hostSupplied: nil)
        let b = SessionStore(service: service, hostSupplied: nil)
        XCTAssertEqual(a.effectiveIdentifier, b.effectiveIdentifier)
        XCTAssertTrue(a.isAnonymous)
    }

    func test_reset_generatesNewId() {
        let service = "crl.test.\(UUID().uuidString)"
        let store = SessionStore(service: service, hostSupplied: nil)
        let first = store.effectiveIdentifier
        store.resetAnonymous()
        let second = store.effectiveIdentifier
        XCTAssertNotEqual(first, second)
    }
}
