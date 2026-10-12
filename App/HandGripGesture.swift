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
    var isArmed:Bool { armed }
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
    mutating func update(curl: Float?, timestamp: Double, now: Double, releaseAllowed: Bool = true) -> Event? {
        // Policy changes must break an unfinished release even when the
        // caller only has the same anchor sample as the preceding frame.
        if isHeld, !releaseAllowed { openStartedAt = nil }
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
            guard releaseAllowed, curl >= Self.openCurl else {
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
            guard let ratio = fingerRatio(wrist: wrist, finger: finger) else { return nil }
            ratios.append(ratio)
        }
        return median(&ratios)
    }

    /// Acquisition-only fallback when too few fingertips are observed. The
    /// first finger bone's bend relative to its palm ray does not authorize
    /// release; confidentOpenRelease still requires actual fingertip pairs.
    static func proximalCurl(wrist: V3, trackedFingers: [(knuckle: V3, intermediate: V3)]) -> Float? {
        guard finite(wrist), trackedFingers.count >= 2 else { return nil }
        var curls: [Float] = []
        for finger in trackedFingers {
            guard finite(finger.knuckle), finite(finger.intermediate) else { return nil }
            let palmRay = finger.knuckle - wrist
            let firstBone = finger.intermediate - finger.knuckle
            let palmLength = simd_length(palmRay), boneLength = simd_length(firstBone)
            guard palmLength.isFinite, palmLength >= 0.02,
                  boneLength.isFinite, boneLength >= 0.005 else { return nil }
            let alignment = simd_dot(firstBone / boneLength, palmRay / palmLength)
            guard alignment.isFinite else { return nil }
            if alignment <= 0.4 { curls.append(1.1) }
            else if alignment >= 0.9 { curls.append(1.9) }
            else { curls.append(1.1 + (alignment - 0.4) / 0.5 * 0.8) }
        }
        return median(&curls)
    }

    /// A subset of extended fingers must not turn occluded curled fingers
    /// into a release. Every available pair must support a full opening.
    static func confidentOpenRelease(wrist: V3, trackedFingers: [(knuckle: V3, tip: V3)]) -> Bool {
        guard finite(wrist), trackedFingers.count >= 3 else { return false }
        return trackedFingers.allSatisfy { finger in
            guard let ratio = fingerRatio(wrist: wrist, finger: finger) else { return false }
            return ratio >= openCurl
        }
    }

    private static func fingerRatio(wrist: V3, finger: (knuckle: V3, tip: V3)) -> Float? {
        guard finite(finger.knuckle), finite(finger.tip) else { return nil }
        let knuckleDistance = simd_distance(wrist, finger.knuckle)
        let tipDistance = simd_distance(wrist, finger.tip)
        guard knuckleDistance.isFinite, knuckleDistance >= 0.0001, tipDistance.isFinite else { return nil }
        let ratio = tipDistance / knuckleDistance
        return ratio.isFinite ? ratio : nil
    }

    private static func median(_ values: inout [Float]) -> Float {
        values.sort()
        let middle = values.count / 2
        return values.count.isMultiple(of: 2)
            ? values[middle - 1] / 2 + values[middle] / 2
            : values[middle]
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
