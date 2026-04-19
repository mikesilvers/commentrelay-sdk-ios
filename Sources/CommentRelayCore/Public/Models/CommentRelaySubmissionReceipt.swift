import Foundation

public struct CommentRelaySubmissionReceipt: Codable, Sendable, Equatable {
    public struct UploadTarget: Codable, Sendable, Equatable {
        public let fieldId: String
        public let fileName: String
        public let uploadUrl: URL
    }

    public let submissionId: UUID
    public let hasUploads: Bool
    public let uploadUrls: [UploadTarget]
}
