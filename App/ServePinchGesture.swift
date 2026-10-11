import Foundation

/// A deliberate free-hand serve gesture. The fingers must first be observed
/// apart, so a pinch held through lost tracking cannot accidentally serve.
struct ServePinchGesture: Sendable {
    static let closeDistance: Float = 0.025
    static let releaseDistance: Float = 0.04
    static let holdDuration: Double = 0.12
    static let maximumSampleGap: Double = 0.10
    static let maximumSampleAge: Double = 0.12

    private var armed = false
    private var closeStartedAt: Double?
    private var lastTimestamp: Double?

    mutating func reset() {
        armed = false
        closeStartedAt = nil
        lastTimestamp = nil
    }

    /// Feed tracked thumb-to-index fingertip distance in metres. Pass `nil`
    /// when either fingertip or its hand is untracked. Both times use the same
    /// monotonic clock; `now` allows an old anchor update to be rejected.
    mutating func update(distance: Float?, timestamp: Double, now: Double) -> Bool {
        guard let distance, distance.isFinite, distance >= 0,
              timestamp.isFinite, now.isFinite,
              now >= timestamp,
              now - timestamp <= Self.maximumSampleAge else {
            reset()
            return false
        }

        if let previous = lastTimestamp {
            if timestamp < previous {
                reset()
                return false
            }
            // Repeated rendering of one anchor sample must not advance a hold.
            if timestamp == previous { return false }
            if timestamp - previous > Self.maximumSampleGap {
                reset()
            }
        }
        lastTimestamp = timestamp

        if distance > Self.releaseDistance {
            armed = true
            closeStartedAt = nil
            return false
        }
        guard armed else { return false }

        // Hysteresis retains the open-hand arm, but a partial release interrupts
        // the sustained pinch needed to serve.
        guard distance < Self.closeDistance else {
            closeStartedAt = nil
            return false
        }
        guard let started = closeStartedAt else {
            closeStartedAt = timestamp
            return false
        }
        guard timestamp - started >= Self.holdDuration else { return false }

        armed = false
        closeStartedAt = nil
        return true
    }
}
