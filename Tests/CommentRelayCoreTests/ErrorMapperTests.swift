import XCTest
@testable import CommentRelayCore

final class ErrorMapperTests: XCTestCase {
    private func mapError(status: Int, body: String = #"{"error":{"code":"X","message":"msg"}}"#, headers: [String: String] = [:]) -> CommentRelayError {
        let url = URL(string: "https://example.com")!
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        return ErrorMapper.map(response: response, data: Data(body.utf8))
    }

    func test_400_mapsToBadRequest() {
        guard case .badRequest(let m) = mapError(status: 400) else { return XCTFail() }
        XCTAssertEqual(m, "msg")
    }
    func test_402_mapsToPaymentRequired() {
        guard case .paymentRequired = mapError(status: 402) else { return XCTFail() }
    }
    func test_403_mapsToForbidden() {
        guard case .forbidden = mapError(status: 403) else { return XCTFail() }
    }
    func test_404_mapsToNotFound() {
        guard case .notFound = mapError(status: 404) else { return XCTFail() }
    }
    func test_409_mapsToConflict() {
        guard case .conflict = mapError(status: 409) else { return XCTFail() }
    }
    func test_429_parsesRetryAfter() {
        guard case .rateLimited(let retry) = mapError(status: 429, headers: ["Retry-After": "3"]) else { return XCTFail() }
        XCTAssertEqual(retry, 3)
    }
    func test_429_noHeader_retryAfterNil() {
        guard case .rateLimited(let retry) = mapError(status: 429) else { return XCTFail() }
        XCTAssertNil(retry)
    }
    func test_500_mapsToServer() {
        guard case .server = mapError(status: 500) else { return XCTFail() }
    }
    func test_unknownStatus_fallsBackToServer() {
        guard case .server = mapError(status: 418) else { return XCTFail() }
    }
    func test_unparseableBody_usesStatusText() {
        guard case .badRequest(let m) = mapError(status: 400, body: "not json") else { return XCTFail() }
        XCTAssertEqual(m, "HTTP 400")
    }
}
