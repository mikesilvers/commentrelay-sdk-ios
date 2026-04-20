import Foundation

protocol UploadTransport: Sendable {
    func put(data: Data, to url: URL, contentType: String) async throws
}

struct URLSessionUploadTransport: UploadTransport {
    let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func put(data: Data, to url: URL, contentType: String) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")
        do {
            let (_, response) = try await session.upload(for: request, from: data)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw CommentRelayError.server(message: "upload failed")
            }
        } catch let urlError as URLError {
            throw CommentRelayError.transport(urlError)
        }
    }
}
