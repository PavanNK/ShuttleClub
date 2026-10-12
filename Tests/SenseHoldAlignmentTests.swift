import Foundation
import Testing
import simd
@testable import ShuttleClub

@Suite
struct SenseHoldAlignmentTests {
    private func pose(_ orientation: simd_quatf, at position: SIMD3<Float> = [0.2, 1.1, -0.45]) -> simd_float4x4 {
        var matrix = simd_float4x4(orientation)
        matrix.columns.3 = SIMD4<Float>(position, 1)
        return matrix
    }

    private func identity() -> simd_float4x4 {
        pose(simd_quatf(angle: 0, axis: [1, 0, 0]))
    }

    private func tick(_ alignment: inout SenseHoldAlignment, pose: simd_float4x4?, time: Double,
                      dt: Float = 1 / 60) -> SenseHoldAlignment.Outcome {
        alignment.update(pose: pose, timestamp: time, now: time, dt: dt)
    }

    private func isCompleted(_ outcome: SenseHoldAlignment.Outcome) -> Bool {
        if case .completed = outcome { return true }
        return false
    }

    private func progress(_ outcome: SenseHoldAlignment.Outcome) -> Float {
        if case .holding(let fraction) = outcome { return fraction }
        return 0
    }

    @Test(arguments: [30, 60, 90])
    func naturalTremorAndSmallDriftCompleteQuicklyAcrossRenderRates(rate: Int) throws {
        var alignment = SenseHoldAlignment()
        let dt = Float(1) / Float(rate)
        let base = simd_quatf(angle: 1.1, axis: simd_normalize(SIMD3<Float>(1, -2, 3)))
        var result = alignment.outcome
        var latest = identity()
        var finishTime: Double?
        for frame in 0..<(rate * 2) {
            let time = Double(frame) / Double(rate)
            let t = Float(time)
            let jitter = simd_quatf(angle: 0.045 * sin(2 * .pi * 5 * t), axis: [1, 0, 0]) *
                simd_quatf(angle: 0.028 * cos(2 * .pi * 7 * t) + 0.02 * t, axis: [0, 1, 0])
            let position = SIMD3<Float>(0.2 + 0.006 * sin(2 * .pi * 6 * t),
                                       1.1 + 0.005 * cos(2 * .pi * 4 * t), -0.45 + 0.005 * t)
            latest = pose(base * jitter, at: position)
            result = tick(&alignment, pose: latest, time: time, dt: dt)
            if isCompleted(result) { finishTime = time; break }
        }
        let finished = try #require(finishTime)
        #expect(finished >= 1.4 && finished <= 1.7)
        guard case .completed(let average) = result else {
            Issue.record("Natural tremor failed to produce an averaged hold")
            return
        }
        #expect(alignment.secondsRemaining == 0 && alignment.isFinished)
        #expect(simd_distance(average.columns.3, latest.columns.3) < 0.000001)
        // The recent average stays close to the intended hold, rather than
        // calibrating against one extremum of a small finger/arm oscillation.
        #expect(abs(simd_dot(simd_quatf(average).vector, base.vector)) > 0.999)
        #expect(abs(simd_determinant(average) - 1) < 0.00001)
    }

    @Test func aSlowIntentionalTurnNeverCalibratesAndOffersABoundedRetry() {
        var alignment = SenseHoldAlignment()
        var result = alignment.outcome
        for frame in 0...370 {
            let time = Double(frame) / 60
            // Only .002 rad per frame: individual-step tests miss this turn.
            let turning = pose(simd_quatf(angle: Float(time) * 0.12, axis: [0, 1, 0]))
            result = tick(&alignment, pose: turning, time: time)
            #expect(!isCompleted(result))
        }
        guard case .failed(let reason) = result else {
            Issue.record("Continuous turning must end with a bounded retry")
            return
        }
        #expect(reason == .movingHold && !reason.message.isEmpty && alignment.isFinished)
        let unchanged = tick(&alignment, pose: identity(), time: 7)
        guard case .failed(let retained) = unchanged else {
            Issue.record("A timed-out capture must wait for explicit retry")
            return
        }
        #expect(retained == reason)
        alignment.reset()
        for frame in 0...100 { result = tick(&alignment, pose: identity(), time: 8 + Double(frame) / 60) }
        #expect(isCompleted(result))
    }

    @Test func fastMenuPointingMovementIsDiscardedBeforeTheNewNaturalHold() throws {
        var alignment = SenseHoldAlignment()
        var result = alignment.outcome
        let natural = pose(simd_quatf(angle: -0.8, axis: simd_normalize(SIMD3<Float>(2, 1, -3))))
        for frame in 0..<42 {
            let t = Float(frame) / 60
            let moving = pose(simd_quatf(angle: t * 4, axis: [1, 0, 0]),
                              at: [0.2 + t * 0.4, 1.1, -0.45])
            result = tick(&alignment, pose: moving, time: Double(frame) / 60)
            #expect(!isCompleted(result))
        }
        for frame in 42..<125 {
            result = tick(&alignment, pose: natural, time: Double(frame) / 60)
            #expect(!isCompleted(result))
        }
        for frame in 125..<150 {
            result = tick(&alignment, pose: natural, time: Double(frame) / 60)
            if isCompleted(result) { break }
        }
        guard case .completed(let average) = result else {
            Issue.record("A new settled natural pose must finish promptly")
            return
        }
        #expect(abs(simd_dot(simd_quatf(average).vector, simd_quatf(natural).vector)) > 0.99999)
        #expect(simd_distance(average.columns.3, natural.columns.3) < 0.000001)
    }

    @Test func aTrackingGapDropsOldEvidenceAndNeedsANewFullHold() {
        var alignment = SenseHoldAlignment()
        var result = alignment.outcome
        for frame in 0..<60 { result = tick(&alignment, pose: identity(), time: Double(frame) / 60) }
        #expect(progress(result) > 0.5 && !isCompleted(result))
        for frame in 60..<78 { result = tick(&alignment, pose: nil, time: Double(frame) / 60) }
        if case .waitingForTracking = result {} else { Issue.record("Tracking loss must clear hold progress") }
        for frame in 78..<160 {
            result = tick(&alignment, pose: identity(), time: Double(frame) / 60)
            #expect(!isCompleted(result))
        }
        for frame in 160..<180 { result = tick(&alignment, pose: identity(), time: Double(frame) / 60) }
        #expect(isCompleted(result))
    }

    @Test func repeatedOrReorderedObservationsCannotFinishAnUnmeasuredHold() {
        var alignment = SenseHoldAlignment()
        var result = alignment.outcome
        for frame in 0..<54 { result = tick(&alignment, pose: identity(), time: Double(frame) / 60) }
        let previous = progress(result)
        for frame in 54..<59 {
            result = alignment.update(pose: identity(), timestamp: 53.0 / 60,
                                      now: Double(frame) / 60, dt: 1 / 60)
            #expect(progress(result) == previous && !isCompleted(result))
        }
        result = alignment.update(pose: identity(), timestamp: 52.0 / 60, now: 59.0 / 60, dt: 1 / 60)
        if case .waitingForTracking = result {} else { Issue.record("Reordered observation must break dwell") }
        for frame in 60..<141 {
            result = tick(&alignment, pose: identity(), time: Double(frame) / 60)
            #expect(!isCompleted(result))
        }
        for frame in 141..<162 { result = tick(&alignment, pose: identity(), time: Double(frame) / 60) }
        #expect(isCompleted(result))
    }

    @Test func missingOrFrozenTrackingTimesOutWithoutProducingAPose() {
        var alignment = SenseHoldAlignment()
        var result = tick(&alignment, pose: identity(), time: 0)
        for frame in 1...370 {
            result = alignment.update(pose: identity(), timestamp: 0, now: Double(frame) / 60, dt: 1 / 60)
            #expect(!isCompleted(result))
        }
        guard case .failed(let reason) = result else {
            Issue.record("Frozen tracking must offer retry instead of keeping a countdown forever")
            return
        }
        #expect(reason == .trackingUnavailable && !reason.message.isEmpty)
    }

    @Test(arguments: [false, true])
    func recentQuaternionMeanHandlesBothGripExamplesAndThePiSignBoundary(left: Bool) {
        var alignment = SenseHoldAlignment()
        let root = simd_quatf(angle: left ? -0.7 : 0.9, axis: [0, 1, 0])
        let hold = simd_quatf(angle: .pi, axis: left ? [1, 0, 0] : [0, 0, 1])
        let expected = root * hold
        var result = alignment.outcome
        var latest = identity()
        for frame in 0..<120 {
            let t = Float(frame) / 60
            let crossing = simd_quatf(angle: .pi + 0.025 * sin(t * 2 * .pi * 5),
                                     axis: left ? [1, 0, 0] : [0, 0, 1])
            latest = pose(root * crossing, at: [left ? -0.35 : 0.35, 1.25, -0.55])
            result = tick(&alignment, pose: latest, time: Double(frame) / 60)
            if isCompleted(result) { break }
        }
        guard case .completed(let average) = result else {
            Issue.record("Quaternion sign changes around pi must not lose the steady hold")
            return
        }
        #expect(abs(simd_dot(simd_quatf(average).vector, expected.vector)) > 0.9999)
        #expect(simd_distance(average.columns.3, latest.columns.3) < 0.000001)
        #expect(abs(simd_determinant(average) - 1) < 0.00001)
    }

    @Test func malformedPosesAndStaleSamplesCannotContributeAndZeroTimeDoesNothing() {
        var alignment = SenseHoldAlignment()
        var result = alignment.update(pose: identity(), timestamp: 0, now: 0, dt: 0)
        #expect(alignment.secondsRemaining == Float(1.45))
        if case .waitingForTracking = result {} else { Issue.record("Zero elapsed time must leave the state alone") }
        var scaled = identity(); scaled.columns.0 *= 2
        var reflected = identity(); reflected.columns.0 *= -1
        var invalid = identity(); invalid.columns.3.x = .nan
        for (index, badPose) in [scaled, reflected, invalid].enumerated() {
            result = tick(&alignment, pose: badPose, time: Double(index) / 60)
            if case .waitingForTracking = result {} else { Issue.record("Only a finite rigid grip can be captured") }
        }
        result = alignment.update(pose: identity(), timestamp: 0, now: 0.5, dt: 1 / 60)
        #expect(!isCompleted(result))
        let remaining = alignment.secondsRemaining
        _ = alignment.update(pose: identity(), timestamp: 1, now: 1, dt: 0)
        #expect(alignment.secondsRemaining == remaining && !alignment.isFinished)
        result = alignment.update(pose: identity(), timestamp: 1, now: 1, dt: 0.2)
        guard case .failed(let reason) = result else {
            Issue.record("A long render interruption must not be silently clamped into a successful capture")
            return
        }
        #expect(reason == .interrupted)
    }
}
