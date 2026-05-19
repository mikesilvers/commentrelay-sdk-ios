import XCTest
@testable import CommentRelayCore

final class FormByNameTests: XCTestCase {
    private func tmp() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("fbn-\(UUID())")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true); return u
    }
    private func client(_ s: URLSession, _ d: URL) -> CommentRelayClient {
        CommentRelayClient(configuration: CommentRelayConfiguration(
            baseURL: URL(string: "https://example.test")!, apiKey: "k"),
            session: s, cacheDirectory: d, keychainService: "svc-\(UUID())")
    }

    // JSON for a single visible form with title "Bug Report" (is_active:true, show_in_picker:true)
    private let bugReportJSON = """
    {"current":false,"hash":"h1","forms":[{"id":"f1","title":"Bug Report","show_in_picker":true,"response_limit_count":null,"response_limit_type":null,"response_limit_window_minutes":null,"more_feedback_prompt":null,"is_active":true,"sort_order":1,"fields":[]}]}
    """

    override func setUp() {
        super.setUp()
        URLProtocolStub.error = nil
        URLProtocolStub.responder = nil
        URLProtocolStub.asyncResponder = nil
    }

    override func tearDown() {
        URLProtocolStub.error = nil
        URLProtocolStub.responder = nil
        URLProtocolStub.asyncResponder = nil
        super.tearDown()
    }

    // 1. Returns a visible form by name, case-insensitively
    func testReturnsVisibleFormByNameCaseInsensitive() async throws {
        URLProtocolStub.responder = { _ in (Data(self.bugReportJSON.utf8), 200) }
        let c = client(URLProtocolStub.makeSession(), tmp())

        let lower = try await c.form(named: "bug report")
        XCTAssertEqual(lower?.title, "Bug Report")

        let upper = try await c.form(named: "BUG REPORT")
        XCTAssertEqual(upper?.title, "Bug Report")
    }

    // 2. Returns nil for an unknown name
    func testReturnsNilForUnknownName() async throws {
        URLProtocolStub.responder = { _ in (Data(self.bugReportJSON.utf8), 200) }
        let c = client(URLProtocolStub.makeSession(), tmp())

        let result = try await c.form(named: "Nope")
        XCTAssertNil(result)
    }

    // 3. Hidden form (show_in_picker:false) is never returned even by exact name
    func testDoesNotReturnHiddenFormEvenByExactName() async throws {
        let json = """
        {"current":false,"hash":"h2","forms":[{"id":"f2","title":"Secret","show_in_picker":false,"response_limit_count":null,"response_limit_type":null,"response_limit_window_minutes":null,"more_feedback_prompt":null,"is_active":true,"sort_order":1,"fields":[]}]}
        """
        URLProtocolStub.responder = { _ in (Data(json.utf8), 200) }
        let c = client(URLProtocolStub.makeSession(), tmp())

        let result = try await c.form(named: "Secret")
        XCTAssertNil(result)
    }

    // 4. Inactive form (is_active:false) is never returned even by exact name
    func testDoesNotReturnInactiveFormEvenByExactName() async throws {
        let json = """
        {"current":false,"hash":"h3","forms":[{"id":"f3","title":"Old","show_in_picker":true,"response_limit_count":null,"response_limit_type":null,"response_limit_window_minutes":null,"more_feedback_prompt":null,"is_active":false,"sort_order":1,"fields":[]}]}
        """
        URLProtocolStub.responder = { _ in (Data(json.utf8), 200) }
        let c = client(URLProtocolStub.makeSession(), tmp())

        let result = try await c.form(named: "Old")
        XCTAssertNil(result)
    }

    // 5. Resolves from cache when offline (proves offline/effectiveConfig path)
    func testResolvesFromCacheWhenOffline() async throws {
        let dir = tmp()
        let json = """
        {"current":false,"hash":"h4","forms":[{"id":"f4","title":"Cached","show_in_picker":true,"response_limit_count":null,"response_limit_type":null,"response_limit_window_minutes":null,"more_feedback_prompt":null,"is_active":true,"sort_order":1,"fields":[]}]}
        """
        // Seed cache with a successful fetch
        URLProtocolStub.error = nil
        URLProtocolStub.responder = { _ in (Data(json.utf8), 200) }
        let c = client(URLProtocolStub.makeSession(), dir)
        _ = try await c.fetchConfig(cachedHash: nil)

        // Now go offline
        URLProtocolStub.error = URLError(.notConnectedToInternet)

        // form(named:) must still resolve from cache
        let result = try await c.form(named: "cached")
        XCTAssertEqual(result?.title, "Cached")
    }
}
