import simd
import ShuttleCore

/// Open, then close to acquire a racket. Once acquired, relaxed fingers and
/// missing finger data keep the attachment until a deliberate open release.
struct HandGripGesture: Sendable {
    enum Event: Equatable, Sendable { case grabbed, released }

    static let closedCurl: Float = 1.25
    static let openCurl: Float = 1.65
    static let openArmDuration: Double = 0.10
    static let closeGrabDuration: Double = 0.10
    static let openReleaseDuration: Double = 0.30
    static let maximumSampleAge: Double = 0.12
    static let maximumSampleGap: Double = 0.12

    private(set) var isHeld = false
    private var armed = false
    private var openStartedAt: Double?
    private var closeStartedAt: Double?
    private var lastTimestamp: Double?

    mutating func reset() {
        isHeld = false
        interruptDwell()
        lastTimestamp = nil
    }

    /// Interrupt background/permission-sheet dwell without dropping an
    /// already held racket. Monotonic sample ordering remains enforced.
    mutating func suspend() { interruptDwell() }

    /// Times share a monotonic clock. Dwell advances only with fresh, distinct
    /// measured samples, so rendering an unchanged anchor cannot grab/release.
    mutating func update(curl: Float?, timestamp: Double, now: Double) -> Event? {
        guard let curl, curl.isFinite, curl >= 0,
              timestamp.isFinite, now.isFinite, now >= timestamp,
              now - timestamp <= Self.maximumSampleAge else {
            interruptDwell()
            return nil
        }
        if let previous = lastTimestamp {
            guard timestamp >= previous else {
                interruptDwell()
                return nil
            }
            if timestamp == previous { return nil }
            if timestamp - previous > Self.maximumSampleGap { interruptDwell() }
        }
        lastTimestamp = timestamp

        if isHeld {
            guard curl >= Self.openCurl else {
                openStartedAt = nil
                return nil
            }
            guard let started = openStartedAt else {
                openStartedAt = timestamp
                return nil
            }
            guard Self.elapsed(from: started, to: timestamp, reaches: Self.openReleaseDuration) else { return nil }
            isHeld = false
            // The sustained release already satisfies the open-before-grab
            // requirement, allowing a deliberate close to pick it up again.
            armed = true
            openStartedAt = nil
            closeStartedAt = nil
            return .released
        }

        if curl >= Self.openCurl {
            closeStartedAt = nil
            if !armed {
                if let started = openStartedAt {
                    if Self.elapsed(from: started, to: timestamp, reaches: Self.openArmDuration) {
                        armed = true
                        openStartedAt = nil
                    }
                } else { openStartedAt = timestamp }
            }
            return nil
        }
        openStartedAt = nil
        guard armed, curl <= Self.closedCurl else {
            closeStartedAt = nil
            return nil
        }
        guard let started = closeStartedAt else {
            closeStartedAt = timestamp
            return nil
        }
        guard Self.elapsed(from: started, to: timestamp, reaches: Self.closeGrabDuration) else { return nil }
        isHeld = true
        armed = false
        closeStartedAt = nil
        return .grabbed
    }

    /// Finger lengths are normalized to their own wrist-to-knuckle distance.
    /// A median avoids letting one noisy tracked fingertip dominate the grip.
    /// Only pass pairs whose knuckle and tip are both tracked.
    static func curl(wrist: V3, trackedFingers: [(knuckle: V3, tip: V3)]) -> Float? {
        guard finite(wrist), trackedFingers.count >= 2 else { return nil }
        var ratios: [Float] = []
        for finger in trackedFingers {
            guard finite(finger.knuckle), finite(finger.tip) else { return nil }
            let knuckleDistance = simd_distance(wrist, finger.knuckle)
            let tipDistance = simd_distance(wrist, finger.tip)
            guard knuckleDistance.isFinite, knuckleDistance >= 0.0001,
                  tipDistance.isFinite else { return nil }
            let ratio = tipDistance / knuckleDistance
            guard ratio.isFinite else { return nil }
            ratios.append(ratio)
        }
        ratios.sort()
        let middle = ratios.count / 2
        return ratios.count.isMultiple(of: 2)
            ? ratios[middle - 1] / 2 + ratios[middle] / 2
            : ratios[middle]
    }

    private mutating func interruptDwell() {
        armed = false
        openStartedAt = nil
        closeStartedAt = nil
    }

    private static func elapsed(from start: Double, to end: Double, reaches duration: Double) -> Bool {
        end - start + 0.000000001 >= duration
    }

    private static func finite(_ point: V3) -> Bool {
        point.x.isFinite && point.y.isFinite && point.z.isFinite
    }
}
