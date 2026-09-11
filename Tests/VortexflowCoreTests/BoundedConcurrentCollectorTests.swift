import Foundation
import Testing
@testable import VortexflowCore

@Suite("Bounded concurrent collection")
struct BoundedConcurrentCollectorTests {

    private func submitOnDedicatedThread(_ work: @escaping () -> Void) {
        let thread = Thread(block: work)
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    @Test("A blocked worker cannot hold the caller past the shared deadline")
    func blockedWorkerCannotHoldCaller() {
        let releaseSlowWorker = DispatchSemaphore(value: 0)
        let slowWorkerStarted = DispatchSemaphore(value: 0)
        let slowWorkerFinished = DispatchSemaphore(value: 0)

        let start = DispatchTime.now()
        let result = BoundedConcurrentCollector.collect(
            count: 2,
            timeout: 0.2,
            submit: submitOnDedicatedThread
        ) { index, _ in
            if index == 0 {
                slowWorkerStarted.signal()
                releaseSlowWorker.wait()
                slowWorkerFinished.signal()
                return "late"
            }
            return "responsive"
        }
        let elapsed = Double(
            DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
        ) / 1_000_000

        #expect(elapsed < 1_000, "the deadline returned after \(elapsed) ms")
        #expect(slowWorkerStarted.wait(timeout: .now()) == .success)
        #expect(result.valuesByIndex[1] == "responsive")
        #expect(result.valuesByIndex[0] == nil)
        #expect(result.unfinishedIndices == [0])

        // The worker is deliberately released only after the caller has its immutable
        // snapshot. Its late answer must not appear in that or any later presentation.
        releaseSlowWorker.signal()
        #expect(slowWorkerFinished.wait(timeout: .now() + 1) == .success)
        #expect(result.valuesByIndex[0] == nil)
    }

    @Test("Completed results retain their input positions")
    func completedResultsRetainInputPositions() {
        let result = BoundedConcurrentCollector.collect(
            count: 4,
            timeout: 1,
            submit: submitOnDedicatedThread
        ) { index, _ in
            10 - index
        }

        #expect(result.unfinishedIndices.isEmpty)
        #expect((0..<4).compactMap { result.valuesByIndex[$0] } == [10, 9, 8, 7])
    }

    @Test("Repeated deadlines keep blocked work single-flight")
    func repeatedDeadlinesKeepBlockedWorkSingleFlight() {
        let gate = SingleFlightGate<String>()
        #expect(gate.claim("wedged-app"))
        #expect(gate.activeCount == 1)

        // These model rapid presentations while the original AX call is still stuck:
        // none can admit a second blocking operation for that process.
        for _ in 0..<1_000 {
            #expect(!gate.claim("wedged-app"))
        }
        #expect(gate.activeCount == 1)

        gate.release("wedged-app")
        #expect(gate.activeCount == 0)
        #expect(gate.claim("wedged-app"))
        gate.release("wedged-app")
    }
}
