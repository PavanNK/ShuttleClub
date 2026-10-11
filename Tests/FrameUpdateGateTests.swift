import Foundation
import Testing
@testable import ShuttleClub

@MainActor @Suite
struct FrameUpdateGateTests {
    @Test func queuedBurstPreservesElapsedTimeWithOneTaskAndReportsReadyOnce() async {
        var frames: [Double] = []
        var readyCount = 0
        var delivered: CheckedContinuation<Void, Never>?
        let gate = FrameUpdateGate(onFrame: { delta in
            frames.append(delta)
            delivered?.resume(); delivered = nil
        }, onReady: { readyCount += 1 })
        for _ in 0..<1_000 { gate.submit(delta: 1 / 90) }
        #expect(gate.statistics == .init(submittedFrames: 1_000, scheduledTasks: 1,
                                       deliveredUpdates: 0, pendingUpdates: 1))
        await withCheckedContinuation { delivered = $0 }
        #expect(frames.count == 1 && abs(frames[0] - 1_000 / 90) < 0.000001)
        #expect(readyCount == 1 && gate.statistics.pendingUpdates == 0)
        gate.submit(delta: 0.007); gate.submit(delta: 0.013)
        await withCheckedContinuation { delivered = $0 }
        #expect(frames.count == 2 && abs(frames[1] - 0.02) < 0.0000001)
        #expect(readyCount == 1 && gate.statistics.scheduledTasks == 2)
        gate.cancel()
    }

    @Test func backgroundProducerAccumulatesAnInterruptionWithoutClamping() async throws {
        var elapsed: Double?
        var delivered: CheckedContinuation<Void, Never>?
        let gate = FrameUpdateGate(onFrame: { delta in
            elapsed = delta
            delivered?.resume(); delivered = nil
        })
        defer { gate.cancel() }
        try enqueueBackgroundBurst(gate)
        #expect(gate.statistics.submittedFrames == 30 && gate.statistics.scheduledTasks == 1)
        await withCheckedContinuation { delivered = $0 }
        #expect(abs((elapsed ?? 0) - 1 / 3) < 0.000001)
        #expect((elapsed ?? 0) > 0.1)
    }

    /// Intentionally synchronous: the background producer can enqueue all its
    /// frames while MainActor stays occupied, before the async test yields.
    /// Swift disallows a blocking semaphore wait directly in async functions.
    private func enqueueBackgroundBurst(_ gate: FrameUpdateGate) throws {
        let producerFinished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            for _ in 0..<30 { gate.submit(delta: 1 / 90) }
            gate.submit(delta: .nan); gate.submit(delta: -.infinity); gate.submit(delta: -1)
            producerFinished.signal()
        }
        try #require(producerFinished.wait(timeout: .now() + 2) == .success)
    }

    @Test func cancellingQueuedSceneCannotRunItsUpdateOrReadyOnTheReplacement() async {
        var oldUpdates = 0, oldReady = 0, newUpdates = 0, newReady = 0
        var delivered: CheckedContinuation<Void, Never>?
        let old = FrameUpdateGate(onFrame: { _ in oldUpdates += 1 }, onReady: { oldReady += 1 })
        old.submit(delta: 0.04); old.cancel(); old.submit(delta: 0.04)
        let replacement = FrameUpdateGate(onFrame: { _ in
            newUpdates += 1
            delivered?.resume(); delivered = nil
        }, onReady: { newReady += 1 })
        replacement.submit(delta: 0.01)
        await withCheckedContinuation { delivered = $0 }
        // The old task may still be on the executor, but its cancelled ticket
        // has no handlers and can never commit work, regardless of run order.
        for _ in 0..<3 { await Task.yield() }
        #expect(oldUpdates == 0 && oldReady == 0 && old.statistics.pendingUpdates == 0)
        #expect(newUpdates == 1 && newReady == 1)
        #expect(old.statistics.submittedFrames == 1)
        replacement.cancel()
    }

    @Test func teardownInsideFirstFrameSuppressesItsReadyCallback() async {
        var gate: FrameUpdateGate?
        var readyCount = 0
        var delivered: CheckedContinuation<Void, Never>?
        gate = FrameUpdateGate(onFrame: { _ in
            gate?.cancel()
            delivered?.resume(); delivered = nil
        }, onReady: { readyCount += 1 })
        gate?.submit(delta: 0)
        await withCheckedContinuation { delivered = $0 }
        #expect(readyCount == 0 && gate?.statistics.deliveredUpdates == 1)
        gate = nil
    }
}
