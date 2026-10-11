import Foundation

/// Coalesces RealityKit callbacks without assuming which thread emits them.
/// Every mutable field is protected by the lock; handlers run only on MainActor.
final class FrameUpdateGate: @unchecked Sendable {
    struct Statistics: Equatable, Sendable {
        let submittedFrames: Int
        let scheduledTasks: Int
        let deliveredUpdates: Int
        let pendingUpdates: Int
    }

    private let lock = NSLock()
    private var active = true
    private var generation: UInt = 0
    private var accumulatedDelta: Double = 0
    private var pendingTask: Task<Void, Never>?
    private var pending = false
    private var submittedFrames = 0
    private var scheduledTasks = 0
    private var deliveredUpdates = 0
    private var onFrame: (@MainActor @Sendable (Double) -> Void)?
    private var onReady: (@MainActor @Sendable () -> Void)?

    @MainActor
    init(onFrame: @escaping @MainActor @Sendable (Double) -> Void,
         onReady: @escaping @MainActor @Sendable () -> Void = {}) {
        self.onFrame = onFrame
        self.onReady = onReady
    }

    var statistics: Statistics {
        lock.withLock {
            Statistics(submittedFrames: submittedFrames, scheduledTasks: scheduledTasks,
                       deliveredUpdates: deliveredUpdates, pendingUpdates: pending ? 1 : 0)
        }
    }

    /// Multiple arrivals before the actor drains them produce one update with
    /// their full elapsed time. Large gaps stay large for the court pause policy.
    func submit(delta: Double) {
        guard delta.isFinite, delta >= 0 else { return }
        lock.withLock {
            guard active else { return }
            submittedFrames += 1
            accumulatedDelta += delta
            guard !pending else { return }
            pending = true
            scheduledTasks += 1
            let ticket = generation
            pendingTask = Task { @MainActor [weak self] in
                guard !Task.isCancelled else { return }
                self?.deliver(generation: ticket)
            }
        }
    }

    /// Scene teardown and handler execution share MainActor, so cancellation
    /// cannot race a copied handler into mutating the replacement scene.
    @MainActor
    func cancel() {
        lock.withLock {
            active = false
            generation &+= 1
            pendingTask?.cancel()
            pendingTask = nil
            pending = false
            accumulatedDelta = 0
            onFrame = nil
            onReady = nil
        }
    }

    @MainActor
    private func deliver(generation ticket: UInt) {
        let delivery = lock.withLock { () -> (Double, @MainActor @Sendable (Double) -> Void)? in
            guard active, generation == ticket, pending, let onFrame else { return nil }
            let delta = accumulatedDelta
            accumulatedDelta = 0
            pending = false
            pendingTask = nil
            deliveredUpdates += 1
            return (delta, onFrame)
        }
        guard let (delta, handler) = delivery else { return }
        handler(delta)
        // A frame handler may itself tear down the scene. Do not report the
        // obsolete scene ready afterward, or consume a replacement's callback.
        let ready = lock.withLock { () -> (@MainActor @Sendable () -> Void)? in
            guard active, generation == ticket else { return nil }
            let ready = onReady
            onReady = nil
            return ready
        }
        ready?()
    }
}
