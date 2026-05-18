import XCTest
@testable import CommentRelayCore

final class ReachabilityTests: XCTestCase {
    func testFakeEmitsAndReportsState() async {
        let fake = FakeReachability(initial: false)
        XCTAssertFalse(fake.isConnected)
        actor Collector { var values: [Bool] = []; func append(_ v: Bool) { values.append(v) } }
        let collector = Collector()
        let task = Task {
            for await v in fake.changes {
                await collector.append(v)
                if await collector.values.count == 2 { break }
            }
        }
        fake.set(true)
        fake.set(false)
        _ = await task.value
        let received = await collector.values
        XCTAssertEqual(received, [true, false])
    }
}
