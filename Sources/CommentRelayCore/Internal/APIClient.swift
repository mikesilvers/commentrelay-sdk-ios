import Foundation

struct APIClient: Sendable {
    let baseURL: URL
    let apiKey: String
    let session: URLSession

    init(baseURL: URL, apiKey: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
    }

    func getHealth() async throws -> Bool {
        let url = baseURL.appendingPathComponent("health")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            if (200..<300).contains(http.statusCode) { return true }
            if http.statusCode >= 500 { return false }
            throw ErrorMapper.map(response: http, data: data)
        } catch let urlError as URLError {
            throw CommentRelayError.transport(urlError)
        }
    }

    func send<Response: Decodable>(method: String, path: String, queryItems: [URLQueryItem]? = nil, body: Data? = nil, userIdentifier: String? = nil, decodingAs: Response.Type, decoder: JSONDecoder = APIClient.defaultDecoder()) async throws -> Response {
        let rawURL = baseURL.appendingPathComponent(path)
        let finalURL: URL
        if let queryItems, !queryItems.isEmpty {
            var components = URLComponents(url: rawURL, resolvingAgainstBaseURL: false) ?? URLComponents()
            components.queryItems = queryItems
            finalURL = components.url ?? rawURL
        } else {
            finalURL = rawURL
        }
        var request = URLRequest(url: finalURL)
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let userIdentifier {
            request.setValue(userIdentifier, forHTTPHeaderField: "x-user-identifier")
        }
        request.httpBody = body
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw CommentRelayError.transport(urlError)
        }
        guard let http = response as? HTTPURLResponse else {
            throw CommentRelayError.server(message: "invalid response")
        }
        if !(200..<300).contains(http.statusCode) {
            throw ErrorMapper.map(response: http, data: data)
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw CommentRelayError.decoding(error)
        }
    }

    static func defaultDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    static func defaultEncoder() -> JSONEncoder {
        JSONEncoder()
    }
}
