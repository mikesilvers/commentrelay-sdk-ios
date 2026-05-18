import Foundation
import Network

protocol Reachability: Sendable {
    var isConnected: Bool { get }
    var changes: AsyncStream<Bool> { get }
}

/// `NWPathMonitor`-backed reachability. `isConnected` is updated on a private queue.
final class NetworkReachability: Reachability, @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.commentrelay.reachability")
    private let lock = NSLock()
    private var _isConnected = false
    private var continuations: [UUID: AsyncStream<Bool>.Continuation] = [:]

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let connected = path.status == .satisfied
            self.lock.lock()
            self._isConnected = connected
            let conts = Array(self.continuations.values)
            self.lock.unlock()
            conts.forEach { $0.yield(connected) }
        }
        monitor.start(queue: queue)
    }

    var isConnected: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isConnected
    }

    var changes: AsyncStream<Bool> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock(); continuations[id] = continuation; lock.unlock()
            continuation.onTermination = { [weak self] _ in
                self?.lock.lock(); self?.continuations[id] = nil; self?.lock.unlock()
            }
        }
    }

    deinit { monitor.cancel() }
}

/// Injectable test double.
final class FakeReachability: Reachability, @unchecked Sendable {
    private let lock = NSLock()
    private var _isConnected: Bool
    private var continuations: [UUID: AsyncStream<Bool>.Continuation] = [:]

    init(initial: Bool) { _isConnected = initial }

    var isConnected: Bool { lock.lock(); defer { lock.unlock() }; return _isConnected }

    var changes: AsyncStream<Bool> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock(); continuations[id] = continuation; lock.unlock()
            continuation.onTermination = { [weak self] _ in
                self?.lock.lock(); self?.continuations[id] = nil; self?.lock.unlock()
            }
        }
    }

    func set(_ connected: Bool) {
        lock.lock(); _isConnected = connected; let conts = Array(continuations.values); lock.unlock()
        conts.forEach { $0.yield(connected) }
    }
}
