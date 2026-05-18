import Foundation

public struct CommentRelayQueuedAttachment: Sendable, Equatable {
    public let fieldId: String
    public let fileName: String
    public let contentType: String
    public let data: Data
    public init(fieldId: String, fileName: String, contentType: String, data: Data) {
        self.fieldId = fieldId; self.fileName = fileName
        self.contentType = contentType; self.data = data
    }
}
