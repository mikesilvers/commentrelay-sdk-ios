import Foundation

actor BackgroundUploadManager {
    struct Payload: Sendable {
        let submissionId: UUID
        let target: CommentRelaySubmissionReceipt.UploadTarget
        let data: Data
        let contentType: String
    }

    private let transport: UploadTransport
    private let finalizeHandler: @Sendable (UUID) async throws -> Void
    private var inFlight: [UUID: Set<String>] = [:]

    init(transport: UploadTransport, finalize: @escaping @Sendable (UUID) async throws -> Void) {
        self.transport = transport
        self.finalizeHandler = finalize
    }

    func enqueue(_ payloads: [Payload]) async throws {
        let grouped = Dictionary(grouping: payloads, by: { $0.submissionId })
        for (subId, group) in grouped {
            inFlight[subId] = Set(group.map { $0.target.fileName })
            for payload in group {
                do {
                    try await transport.put(data: payload.data, to: payload.target.uploadUrl, contentType: payload.contentType)
                    inFlight[subId]?.remove(payload.target.fileName)
                } catch let crErr as CommentRelayError {
                    // Pass CommentRelayErrors (e.g. .forbidden) through unwrapped so callers
                    // can classify them correctly (CRLBS-116). Tradeoff: this bypasses the
                    // `.uploadFailed` envelope, so its submissionId/fileName diagnostic context
                    // is not attached. Acceptable while `.forbidden` is the only CommentRelayError
                    // `transport.put` throws (caller has the receipt + a message); revisit if the
                    // transport starts surfacing other CommentRelayError cases here.
                    throw crErr
                } catch {
                    throw CommentRelayError.uploadFailed(submissionId: subId,
                                                         fileName: payload.target.fileName,
                                                         underlying: error)
                }
            }
            if inFlight[subId]?.isEmpty == true {
                inFlight.removeValue(forKey: subId)
                try await finalizeHandler(subId)
            }
        }
    }
}

public struct CommentRelayFilePayload: Sendable {
    public let target: CommentRelaySubmissionReceipt.UploadTarget
    public let data: Data
    public let contentType: String
    public init(target: CommentRelaySubmissionReceipt.UploadTarget, data: Data, contentType: String) {
        self.target = target; self.data = data; self.contentType = contentType
    }
}
