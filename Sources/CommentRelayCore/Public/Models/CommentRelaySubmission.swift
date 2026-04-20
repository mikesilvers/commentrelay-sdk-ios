import Foundation

public struct CommentRelaySubmission: Codable, Sendable, Equatable {
    public struct FileMetadata: Codable, Sendable, Equatable {
        public let name: String
        public let type: String
        public let size: Int
        public init(name: String, type: String, size: Int) {
            self.name = name; self.type = type; self.size = size
        }
    }

    public enum FieldValue: Codable, Sendable, Equatable {
        case text(fieldId: String, value: String)
        case files(fieldId: String, metadata: [FileMetadata])

        private enum Keys: String, CodingKey { case fieldId = "field_id", value, fileMetadata = "file_metadata" }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            let id = try c.decode(String.self, forKey: .fieldId)
            if let value = try c.decodeIfPresent(String.self, forKey: .value) {
                self = .text(fieldId: id, value: value)
            } else {
                let m = try c.decode([FileMetadata].self, forKey: .fileMetadata)
                self = .files(fieldId: id, metadata: m)
            }
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: Keys.self)
            switch self {
            case .text(let id, let v):
                try c.encode(id, forKey: .fieldId)
                try c.encode(v, forKey: .value)
            case .files(let id, let m):
                try c.encode(id, forKey: .fieldId)
                try c.encode(m, forKey: .fileMetadata)
            }
        }
    }

    public let categoryId: String
    public let userIdentifier: String
    public let platform: Platform
    public let fields: [FieldValue]
    public let osVersion: String?
    public let deviceModel: String?
    public let appVersion: String?
    public let sdkVersion: String?
    public let locale: String?
    public let contactPreference: ContactPreference?
    public let contactDetails: String?
    public let sessionId: UUID?

    enum CodingKeys: String, CodingKey {
        case categoryId = "category_id"
        case userIdentifier = "user_identifier"
        case platform, fields
        case osVersion = "os_version"
        case deviceModel = "device_model"
        case appVersion = "app_version"
        case sdkVersion = "sdk_version"
        case locale
        case contactPreference = "contact_preference"
        case contactDetails = "contact_details"
        case sessionId = "session_id"
    }

    public init(categoryId: String, userIdentifier: String, platform: Platform, fields: [FieldValue],
                osVersion: String? = nil, deviceModel: String? = nil, appVersion: String? = nil,
                sdkVersion: String? = nil, locale: String? = nil,
                contactPreference: ContactPreference? = nil, contactDetails: String? = nil,
                sessionId: UUID? = nil) {
        self.categoryId = categoryId
        self.userIdentifier = userIdentifier
        self.platform = platform
        self.fields = fields
        self.osVersion = osVersion
        self.deviceModel = deviceModel
        self.appVersion = appVersion
        self.sdkVersion = sdkVersion
        self.locale = locale
        self.contactPreference = contactPreference
        self.contactDetails = contactDetails
        self.sessionId = sessionId
    }
}
