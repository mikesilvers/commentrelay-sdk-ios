import XCTest
@testable import CommentRelayCore

final class ReachabilityTests: XCTestCase {
    func testFakeEmitsAndReportsState() async {
        let fake = FakeReachability(initial: false)
        XCTAssertFalse(fake.isConnected)

        actor Collector { var values: [Bool] = []; func append(_ v: Bool) { values.append(v) } }
        let collector = Collector()

        // Capture the stream before starting the Task. The AsyncStream builder
        // closure runs synchronously here, registering the continuation with
        // FakeReachability immediately — before any call to fake.set(_:).
        let stream = fake.changes

        let (readyStream, readyContinuation) = AsyncStream<Void>.makeStream()

        let task = Task {
            // Signal that the continuation is registered (it already was, above).
            readyContinuation.yield(())
            for await v in stream {
                await collector.append(v)
                if await collector.values.count == 2 { break }
            }
        }

        // Wait until the consuming task is actively iterating the stream before firing events.
        var readyIterator = readyStream.makeAsyncIterator()
        _ = await readyIterator.next()

        fake.set(true)
        fake.set(false)
        _ = await task.value

        let received = await collector.values
        XCTAssertEqual(received, [true, false])
    }
}
