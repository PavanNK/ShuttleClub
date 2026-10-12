import Foundation
import simd

/// Collects a short, measured natural hold without restarting a long countdown
/// for ordinary tremor. Tolerances are provisional and need physical validation.
/// The owner starts/cancels this value with its tracking/input lifecycle.
struct SenseHoldAlignment: Sendable {
    enum Failure: Equatable, Sendable {
        case movingHold, trackingUnavailable, interrupted

        var message: String {
            switch self {
            case .movingHold:
                "Couldn't capture a steady hold. Rest your arm comfortably, then try Align again."
            case .trackingUnavailable:
                "Couldn't track the hold. Keep your selected controller in view, then try Align again."
            case .interrupted:
                "Alignment was interrupted. Try Align again when you're ready."
            }
        }
    }

    enum Outcome: Sendable {
        case waitingForTracking
        case settling
        case holding(progress: Float)
        case completed(pose: simd_float4x4)
        case failed(Failure)
    }

    static let settleDuration: Double = 0.25
    static let holdDuration: Double = 1.2
    static let timeoutDuration: Double = 6
    private static let maximumSampleAge: Double = 0.12
    private static let maximumSampleGap: Double = 0.12
    private static let meanDuration: Double = 0.45
    // Allow oscillation and modest drift, but reject a sustained intentional
    // change. A trend over the window distinguishes tremor from slow turning.
    private static let maximumPositionDeviation: Float = 0.025
    private static let maximumAngleDeviation: Float = 0.11
    private static let maximumPositionTrend: Float = 0.018
    private static let maximumAngleTrend: Float = 0.075
    private static let trendMinimumDuration: Double = 0.4

    private struct Sample: Sendable {
        let time: Double
        let position: SIMD3<Float>
        let orientation: simd_quatf
    }

    private var elapsed: Double = 0
    private var lastTimestamp: Double?
    private var lastSample: Sample?
    private var settleStarted: Double?
    private var samples: [Sample] = []
    private var lastFailure: Failure = .trackingUnavailable
    private(set) var outcome: Outcome = .waitingForTracking
    private(set) var secondsRemaining = Float(settleDuration + holdDuration)

    var isFinished: Bool {
        switch outcome {
        case .completed, .failed: true
        default: false
        }
    }

    mutating func reset() { self = Self() }

    /// dt is the full render elapsed time, not an artificially clamped physics
    /// interval. now and timestamp use the same monotonic acquisition clock.
    /// Repeated samples do not advance capture; their elapsed time is included
    /// when the next distinct fresh observation arrives. A gap loses evidence.
    /// Terminal outcomes remain available until the owner handles/reset them.
    mutating func update(pose: simd_float4x4?, timestamp: Double, now: Double,
                         dt: Float) -> Outcome {
        guard !isFinished else { return outcome }
        if dt == 0 { return outcome }
        guard dt.isFinite, dt > 0, dt <= 0.1 else {
            outcome = .failed(.interrupted)
            return outcome
        }
        elapsed += Double(dt)
        guard elapsed < Self.timeoutDuration else {
            outcome = .failed(lastFailure)
            return outcome
        }
        guard timestamp.isFinite, now.isFinite, now - timestamp >= -0.03,
              now - timestamp <= Self.maximumSampleAge,
              let pose, Self.isRigid(pose) else {
            loseEvidence()
            return outcome
        }
        if let previous = lastTimestamp {
            guard timestamp >= previous else {
                loseEvidence()
                return outcome
            }
            if timestamp == previous { return outcome }
            if timestamp - previous > Self.maximumSampleGap { loseEvidence() }
        }
        lastTimestamp = timestamp
        let current = Sample(time: elapsed, position: Self.xyz(pose.columns.3),
                             orientation: simd_quatf(pose).normalized)
        defer { lastSample = current }
        if let previous = lastSample,
           simd_distance(previous.position, current.position) > 0.09 ||
            Self.angle(previous.orientation, current.orientation) > 0.3 {
            restartHold(settle: true)
        }
        lastFailure = .movingHold
        guard let settledFrom = settleStarted else {
            settleStarted = elapsed
            outcome = .settling
            return outcome
        }
        let settling = elapsed - settledFrom
        guard settling + 0.0000001 >= Self.settleDuration else {
            secondsRemaining = Float(Self.settleDuration - settling + Self.holdDuration)
            outcome = .settling
            return outcome
        }
        // At most 180 retained observations per logical second. All incoming
        // samples still pass jump/order checks; this only bounds averaging work.
        if let previous = samples.last, elapsed - previous.time < 1 / 180 {
            return outcome
        }
        samples.append(current)
        if samples.count > 256 { samples.removeFirst(samples.count - 256) }
        guard Self.isStable(samples) else {
            // Preserve the deadline, keep only the latest evidence, and try a
            // short window again. Sustained motion cannot finish via resetting.
            samples = [current]
            secondsRemaining = Float(Self.holdDuration)
            outcome = .holding(progress: 0)
            return outcome
        }
        let duration = elapsed - (samples.first?.time ?? elapsed)
        secondsRemaining = Float(max(0, Self.holdDuration - duration))
        guard duration + 0.0000001 >= Self.holdDuration, samples.count >= 6 else {
            outcome = .holding(progress: Float(min(1, duration / Self.holdDuration)))
            return outcome
        }
        let recent = samples.filter { elapsed - $0.time <= Self.meanDuration }
        var averaged = simd_float4x4(Self.meanOrientation(recent))
        // Averaging orientation must not displace the physical handle.
        averaged.columns.3 = SIMD4<Float>(current.position, 1)
        secondsRemaining = 0
        outcome = .completed(pose: averaged)
        return outcome
    }

    private mutating func loseEvidence() {
        lastFailure = .trackingUnavailable
        lastSample = nil
        settleStarted = nil
        samples.removeAll(keepingCapacity: true)
        secondsRemaining = Float(Self.settleDuration + Self.holdDuration)
        outcome = .waitingForTracking
    }

    private mutating func restartHold(settle: Bool) {
        samples.removeAll(keepingCapacity: true)
        settleStarted = settle ? elapsed : settleStarted
        secondsRemaining = Float((settle ? Self.settleDuration : 0) + Self.holdDuration)
        outcome = .settling
    }

    private static func isStable(_ samples: [Sample]) -> Bool {
        guard let first = samples.first, let last = samples.last else { return true }
        let mean = meanOrientation(samples)
        let position = samples.reduce(SIMD3<Float>.zero) { $0 + $1.position } / Float(samples.count)
        guard samples.allSatisfy({ simd_distance($0.position, position) <= maximumPositionDeviation &&
            angle($0.orientation, mean) <= maximumAngleDeviation }) else { return false }
        guard last.time - first.time >= trendMinimumDuration else { return true }
        // Least-squares slope suppresses high-frequency, zero-mean tremor while
        // detecting a gradual translation or face turn across the whole hold.
        let meanTime = samples.reduce(0.0) { $0 + ($1.time - first.time) } / Double(samples.count)
        var variance: Float = 0
        var positionTrend = SIMD3<Float>.zero
        var angleTrend = SIMD3<Float>.zero
        for sample in samples {
            let time = Float(sample.time - first.time - meanTime)
            variance += time * time
            positionTrend += (sample.position - position) * time
            angleTrend += rotationVector(from: first.orientation, to: sample.orientation) * time
        }
        guard variance > 0 else { return false }
        return simd_length(positionTrend / variance) <= maximumPositionTrend &&
            simd_length(angleTrend / variance) <= maximumAngleTrend
    }

    private static func meanOrientation(_ samples: [Sample]) -> simd_quatf {
        guard let first = samples.first else { return simd_quatf(angle: 0, axis: [1, 0, 0]) }
        var sum = SIMD4<Float>.zero
        for sample in samples {
            let vector = sample.orientation.vector
            sum += simd_dot(vector, first.orientation.vector) < 0 ? -vector : vector
        }
        return simd_quatf(vector: simd_normalize(sum))
    }

    private static func rotationVector(from a: simd_quatf, to b: simd_quatf) -> SIMD3<Float> {
        var delta = (a.inverse * b).normalized
        if delta.real < 0 { delta = simd_quatf(vector: -delta.vector) }
        let length = simd_length(delta.imag)
        guard length > 0.000001 else { return .zero }
        return delta.imag * (2 * atan2(length, max(0, delta.real)) / length)
    }

    private static func angle(_ a: simd_quatf, _ b: simd_quatf) -> Float {
        simd_length(rotationVector(from: a, to: b))
    }

    private static func xyz(_ vector: SIMD4<Float>) -> SIMD3<Float> {
        [vector.x, vector.y, vector.z]
    }

    private static func isRigid(_ pose: simd_float4x4) -> Bool {
        guard (0..<4).allSatisfy({ column in (0..<4).allSatisfy { pose[column][$0].isFinite } }),
              abs(pose.columns.0.w) < 0.0001, abs(pose.columns.1.w) < 0.0001,
              abs(pose.columns.2.w) < 0.0001, abs(pose.columns.3.w - 1) < 0.0001 else { return false }
        let x = xyz(pose.columns.0), y = xyz(pose.columns.1), z = xyz(pose.columns.2)
        return abs(simd_determinant(simd_float3x3(columns: (x, y, z))) - 1) < 0.01 &&
            [x, y, z].allSatisfy { abs(simd_length_squared($0) - 1) < 0.01 } &&
            abs(simd_dot(x, y)) < 0.01 && abs(simd_dot(y, z)) < 0.01 && abs(simd_dot(z, x)) < 0.01
    }
}
