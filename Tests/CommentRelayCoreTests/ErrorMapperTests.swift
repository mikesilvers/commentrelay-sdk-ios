import XCTest
@testable import CommentRelayCore

final class ErrorMapperTests: XCTestCase {
    private func response(_ code: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://example.com")!,
                        statusCode: code,
                        httpVersion: nil,
                        headerFields: headers)!
    }
    private let emptyBody = Data()

    func test_enumerated_4xx_map_to_specific_cases() {
        guard case .badRequest = ErrorMapper.map(response: response(400), data: emptyBody) else {
            return XCTFail("400 should map to .badRequest")
        }
        guard case .unauthorized = ErrorMapper.map(response: response(401), data: emptyBody) else {
            return XCTFail("401 should map to .unauthorized")
        }
        guard case .paymentRequired = ErrorMapper.map(response: response(402), data: emptyBody) else {
            return XCTFail("402 should map to .paymentRequired")
        }
        guard case .forbidden = ErrorMapper.map(response: response(403), data: emptyBody) else {
            return XCTFail("403 should map to .forbidden")
        }
        guard case .notFound = ErrorMapper.map(response: response(404), data: emptyBody) else {
            return XCTFail("404 should map to .notFound")
        }
        guard case .conflict = ErrorMapper.map(response: response(409), data: emptyBody) else {
            return XCTFail("409 should map to .conflict")
        }
    }

    func test_429_maps_to_rateLimited_with_retry_after() {
        let result = ErrorMapper.map(response: response(429, headers: ["Retry-After": "5"]), data: emptyBody)
        guard case .rateLimited(let after) = result else {
            return XCTFail("429 should map to .rateLimited, got \(result)")
        }
        XCTAssertEqual(after, 5)
    }

    func test_429_without_retry_after_is_nil() {
        let result = ErrorMapper.map(response: response(429), data: emptyBody)
        guard case .rateLimited(let after) = result else {
            return XCTFail("429 should map to .rateLimited, got \(result)")
        }
        XCTAssertNil(after)
    }

    func test_5xx_maps_to_server() {
        for code in [500, 502, 503, 504, 599] {
            if case .server = ErrorMapper.map(response: response(code), data: emptyBody) {} else {
                XCTFail("\(code) should map to .server")
            }
        }
    }

    func test_other_4xx_maps_to_unexpectedStatus() {
        for code in [405, 410, 415, 418, 422, 451] {
            let result = ErrorMapper.map(response: response(code), data: emptyBody)
            guard case .unexpectedStatus(let statusCode, _) = result else {
                return XCTFail("\(code) should map to .unexpectedStatus, got \(result)")
            }
            XCTAssertEqual(statusCode, code, "preserved status code")
        }
    }

    func test_out_of_range_status_maps_to_unexpectedStatus() {
        // Status codes outside 500..<600 (e.g. 600+) must fall through to .unexpectedStatus,
        // not .server. Guards against an off-by-one in the range bound.
        let result = ErrorMapper.map(response: response(600), data: emptyBody)
        guard case .unexpectedStatus(let statusCode, _) = result else {
            return XCTFail("600 should map to .unexpectedStatus, got \(result)")
        }
        XCTAssertEqual(statusCode, 600)
    }

    func test_envelope_message_is_used_when_present() {
        let body = #"{"error":{"code":"X","message":"forbidden detail"}}"#.data(using: .utf8)!
        let result = ErrorMapper.map(response: response(403), data: body)
        guard case .forbidden(let msg) = result else {
            return XCTFail("expected .forbidden")
        }
        XCTAssertEqual(msg, "forbidden detail")
    }

    func test_fallback_message_when_body_is_not_envelope() {
        let result = ErrorMapper.map(response: response(404), data: Data("not json".utf8))
        guard case .notFound(let msg) = result else {
            return XCTFail("expected .notFound")
        }
        XCTAssertEqual(msg, "HTTP 404")
    }
}
