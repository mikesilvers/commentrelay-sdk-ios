import Foundation

/// Intercepts URLSession requests so tests can assert on requests and return canned responses.
/// Usage: set `MockURLProtocol.handler` before the test, register via a URLSessionConfiguration
/// with `protocolClasses = [MockURLProtocol.self]`.
final class MockURLProtocol: URLProtocol {
    /// Handler the test installs. Receives the request and returns (response, body) or throws.
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    /// Records the requests that came through — tests can inspect this.
    static var requests: [URLRequest] = []

    static func reset() {
        handler = nil
        requests = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: NSError(
                domain: "MockURLProtocol", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No handler set"]))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
