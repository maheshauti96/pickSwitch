import Foundation

/// Runs independent blocking operations in parallel, but only accepts results that
/// arrive before one shared deadline.
///
/// Dispatch has no safe way to cancel a block that is already inside a synchronous C
/// API. Returning at the deadline while those blocks retain a stack-local result buffer
/// would therefore be a use-after-return race. The heap storage below stays alive until
/// the last block releases it, and `close` makes every late submission a no-op.
struct BoundedConcurrentResult<Value> {
    let valuesByIndex: [Int: Value]
    let unfinishedIndices: Set<Int>
}

enum BoundedConcurrentCollector {

    static func collect<Value>(
        count: Int,
        timeout: TimeInterval,
        queue: DispatchQueue,
        operation: @escaping (_ index: Int, _ deadline: DispatchTime) -> Value
    ) -> BoundedConcurrentResult<Value> {
        collect(
            count: count,
            timeout: timeout,
            submit: { work in queue.async { work() } },
            operation: operation
        )
    }

    /// Submission is injectable so the deadline and late-result behaviour can be
    /// exercised with dedicated test threads instead of occupying libdispatch's shared
    /// worker pool. Production uses the queue overload above.
    static func collect<Value>(
        count: Int,
        timeout: TimeInterval,
        submit: (_ work: @escaping () -> Void) -> Void,
        operation: @escaping (_ index: Int, _ deadline: DispatchTime) -> Value
    ) -> BoundedConcurrentResult<Value> {
        guard count > 0 else {
            return BoundedConcurrentResult(valuesByIndex: [:], unfinishedIndices: [])
        }

        let deadline = DispatchTime.now() + max(0, timeout)
        let storage = Storage<Value>()
        let group = DispatchGroup()

        for index in 0..<count {
            group.enter()
            submit {
                defer { group.leave() }

                // A saturated queue may not start every item before the caller's
                // deadline. Do not begin stale blocking work merely to discard it.
                guard DispatchTime.now().uptimeNanoseconds < deadline.uptimeNanoseconds else {
                    return
                }

                let value = operation(index, deadline)
                storage.store(value, at: index, before: deadline)
            }
        }

        _ = group.wait(timeout: deadline)
        return storage.close(expectedCount: count)
    }
}

/// Admits at most one long-running operation for a key at a time.
///
/// A deadline limits how long the caller waits; it cannot stop a synchronous C call
/// that is already running. Keeping that call single-flight means repeated callers
/// degrade immediately instead of creating an ever-growing pile of blocked workers.
final class SingleFlightGate<Key: Hashable>: @unchecked Sendable {
    private let lock = NSLock()
    private var activeKeys: Set<Key> = []

    func claim(_ key: Key) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeKeys.insert(key).inserted
    }

    func release(_ key: Key) {
        lock.lock()
        activeKeys.remove(key)
        lock.unlock()
    }

    var activeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return activeKeys.count
    }
}

private extension BoundedConcurrentCollector {

    final class Storage<Value>: @unchecked Sendable {
        private let lock = NSLock()
        private var isAcceptingResults = true
        private var valuesByIndex: [Int: Value] = [:]

        func store(_ value: Value, at index: Int, before deadline: DispatchTime) {
            lock.lock()
            defer { lock.unlock() }

            guard isAcceptingResults,
                  DispatchTime.now().uptimeNanoseconds < deadline.uptimeNanoseconds
            else { return }
            valuesByIndex[index] = value
        }

        func close(expectedCount: Int) -> BoundedConcurrentResult<Value> {
            lock.lock()
            defer { lock.unlock() }

            isAcceptingResults = false
            let completed = Set(valuesByIndex.keys)
            let unfinished = Set(0..<expectedCount).subtracting(completed)
            return BoundedConcurrentResult(
                valuesByIndex: valuesByIndex,
                unfinishedIndices: unfinished
            )
        }
    }
}
