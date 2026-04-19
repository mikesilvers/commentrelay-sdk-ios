import XCTest
@testable import CommentRelayCore

final class BackgroundUploadManagerTests: XCTestCase {
    actor FakeTransport: UploadTransport {
        var puts: [(URL, Data)] = []
        var shouldThrow: Bool = false
        var attempt = 0
        func put(data: Data, to url: URL, contentType: String) async throws {
            attempt += 1
            if shouldThrow { throw URLError(.timedOut) }
            puts.append((url, data))
        }
    }

    actor Recorder {
        var ids: [UUID] = []
        func record(_ id: UUID) { ids.append(id) }
        func snapshot() -> [UUID] { ids }
    }

    func test_happyPath_uploadsAllAndFinalizes() async throws {
        let transport = FakeTransport()
        let recorder = Recorder()
        let manager = BackgroundUploadManager(transport: transport) { id in await recorder.record(id) }
        let subId = UUID()
        let target = CommentRelaySubmissionReceipt.UploadTarget(fieldId: "f", fileName: "a.png", uploadUrl: URL(string: "https://s3/u/a")!)
        let payload = BackgroundUploadManager.Payload(submissionId: subId, target: target, data: Data([1, 2, 3]), contentType: "image/png")
        try await manager.enqueue([payload])
        let finalized = await recorder.snapshot()
        XCTAssertEqual(finalized, [subId])
        let count = await transport.puts.count
        XCTAssertEqual(count, 1)
    }

    func test_partialFailure_doesNotFinalize() async throws {
        let transport = FakeTransport()
        await transport.setShouldThrow(true)
        let recorder = Recorder()
        let manager = BackgroundUploadManager(transport: transport) { id in await recorder.record(id) }
        let subId = UUID()
        let target = CommentRelaySubmissionReceipt.UploadTarget(fieldId: "f", fileName: "a.png", uploadUrl: URL(string: "https://s3/u/a")!)
        let payload = BackgroundUploadManager.Payload(submissionId: subId, target: target, data: Data([1]), contentType: "image/png")
        do {
            try await manager.enqueue([payload])
            XCTFail()
        } catch {
            let finalized = await recorder.snapshot()
            XCTAssertTrue(finalized.isEmpty)
        }
    }
}

extension BackgroundUploadManagerTests.FakeTransport {
    func setShouldThrow(_ value: Bool) { shouldThrow = value }
}
