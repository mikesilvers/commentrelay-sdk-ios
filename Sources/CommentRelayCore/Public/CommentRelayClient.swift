// Sources/CommentRelayCore/Public/CommentRelayClient.swift
import Foundation

public actor CommentRelayClient {
    public let configuration: CommentRelayConfiguration

    private let api: APIClient
    private let configCache: ConfigCache
    private let sessionStore: SessionStore
    private let draftStore: DraftStore
    private(set) public var isEnabled: Bool = true

    public init(configuration: CommentRelayConfiguration, session: URLSession = .shared) {
        let fingerprint = Self.fingerprint(apiKey: configuration.apiKey)
        let dir = (try? ConfigCache.defaultDirectory(apiKeyFingerprint: fingerprint))
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("CommentRelay/\(fingerprint)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.configuration = configuration
        self.api = APIClient(baseURL: configuration.baseURL, apiKey: configuration.apiKey, session: session)
        self.configCache = ConfigCache(directory: dir)
        self.sessionStore = SessionStore(service: "com.commentrelay.sdk.\(fingerprint)", hostSupplied: configuration.userIdentifier)
        self.draftStore = DraftStore(directory: dir.appendingPathComponent("drafts"))
    }

    // Test-only escape hatch keeping the test suite hermetic.
    init(configuration: CommentRelayConfiguration,
         session: URLSession,
         cacheDirectory: URL,
         keychainService: String) {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        self.configuration = configuration
        self.api = APIClient(baseURL: configuration.baseURL, apiKey: configuration.apiKey, session: session)
        self.configCache = ConfigCache(directory: cacheDirectory)
        self.sessionStore = SessionStore(service: keychainService, hostSupplied: configuration.userIdentifier)
        self.draftStore = DraftStore(directory: cacheDirectory.appendingPathComponent("drafts"))
    }

    public func ping() async throws -> Bool {
        try ensureEnabled()
        return try await api.getHealth()
    }

    public func fetchConfig(cachedHash: String?) async throws -> CommentRelayConfigResponse {
        try ensureEnabled()
        let basePath = "sdk/v1/config"
        let queryItems: [URLQueryItem]? = cachedHash.map { [URLQueryItem(name: "hash", value: $0)] }
        let response: CommentRelayConfigResponse = try await api.send(
            method: "GET", path: basePath, queryItems: queryItems, decodingAs: CommentRelayConfigResponse.self)
        if case .updated(let hash, let categories) = response {
            await configCache.write(hash: hash, categories: categories)
        }
        return response
    }

    // MARK: - Internal helpers

    private func ensureEnabled() throws {
        if !isEnabled {
            throw CommentRelayError.forbidden(message: "client disabled after 403 — call reset()")
        }
    }

    @inline(__always)
    fileprivate func disable() { isEnabled = false }

    private static func fingerprint(apiKey: String) -> String {
        let digest = apiKey.unicodeScalars.reduce(into: UInt64(5381)) { acc, scalar in
            acc = (acc &* 33) &+ UInt64(scalar.value)
        }
        return String(digest, radix: 16)
    }
}
