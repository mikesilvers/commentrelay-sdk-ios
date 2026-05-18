import Foundation

/// Simple URLProtocol stub for tests that need to simulate network success/failure.
/// API:
///   - Set `URLProtocolStub.error` to a `URLError` to fail all requests with that error.
///   - Set `URLProtocolStub.responder` to a closure returning `(Data, Int)` (body, statusCode)
///     to return a canned HTTP response.
///   - Call `URLProtocolStub.makeSession()` to get a URLSession that routes through this stub.
///   - Reset both statics in setUp()/tearDown().
final class URLProtocolStub: URLProtocol {
    nonisolated(unsafe) static var error: URLError?
    nonisolated(unsafe) static var responder: ((URLRequest) -> (Data, Int))?

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let err = Self.error {
            client?.urlProtocol(self, didFailWithError: err)
            return
        }
        let (data, statusCode) = Self.responder?(request) ?? (Data(), 200)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
