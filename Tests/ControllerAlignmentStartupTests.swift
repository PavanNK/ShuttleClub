import Foundation
import Testing
import QuartzCore
import RealityKit
import simd
import ShuttleCore
@testable import ShuttleClub

@MainActor @Suite(.serialized)
struct ControllerAlignmentStartupTests {
    private struct SampleClock {
        private var previous: Double = 0
        mutating func next() -> Double {
            previous = max(CACurrentMediaTime(), previous + 0.00001)
            return previous
        }
    }

    private func defaults() throws -> (UserDefaults, String) {
        let name = "ShuttleClub.ControllerAlignmentStartupTests.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: name)), name)
    }

    /// prepare sets trackingActive, which is needed by the actual automatic
    /// startup path. Tests remain synchronous on MainActor; deferred stop
    /// cancels its pending tracking Task before that task can start a session.
    private func fixture(_ saved: UserDefaults, left: Bool = false) -> GameModel {
        let game = GameModel(gripDefaults: saved)
        game.input = .sense; game.leftHand = left
        game.automaticServing = false; game.soundEnabled = false; game.musicEnabled = false
        game.prepare(); game.setCourtMovement(.stationary)
        return game
    }

    private func grip(_ angle: Float = 0.8) -> simd_float4x4 {
        var matrix = simd_float4x4(simd_quatf(angle: angle, axis: simd_normalize(V3(1, -2, 3))))
        matrix.columns.3 = SIMD4<Float>(0.25, 1.15, -0.4, 1)
        return matrix
    }

    private func commit(_ game: GameModel, grip: simd_float4x4, clock: inout SampleClock,
                        velocity: V3 = .zero) {
        let mounted = game.controllerGripFit.mountedPose(fromGrip: grip)
        game.receiveControllerPose(.init(originFromGrip: grip, leftHand: game.leftHand,
            measured: mounted, rendered: mounted, headVelocity: velocity, timestamp: clock.next()))
    }

    private func tick(_ game: GameModel, grip: simd_float4x4, clock: inout SampleClock, count: Int) {
        for _ in 0..<count {
            commit(game, grip: grip, clock: &clock)
            game.updateControllerAlignment(0.1)
        }
    }

    private func matrixMatches(_ a: simd_float4x4, _ b: simd_float4x4) -> Bool {
        (0..<4).allSatisfy { simd_distance(a[$0], b[$0]) < 0.0001 }
    }

    @Test(arguments: [false, true])
    func oldNondefaultSavedFitRequiresAutomaticCaptureWithoutLosingItsBytes(left: Bool) throws {
        let (saved, name) = try defaults()
        let key = "ShuttleClub.SenseGripFit.\(left ? "left" : "right").v1"
        let old = SenseGripFit(translation: [0.025, -0.015, 0.02],
            calibratedOrientation: simd_quatf(angle: 0.5, axis: [0, 0, 1]).vector,
            pitchDegrees: 18, yawDegrees: -32, rollDegrees: 11)
        // Pre-build-11 saves did not contain a rotation-order marker or the
        // separate natural-hold confirmation. Preserve the exact old JSON.
        let encoded = try JSONEncoder().encode(old)
        let object = try JSONSerialization.jsonObject(with: encoded)
        var legacy = try #require(object as? [String: Any])
        legacy.removeValue(forKey: "rotationOrderVersion")
        let bytes = try JSONSerialization.data(withJSONObject: legacy, options: [.sortedKeys])
        saved.set(bytes, forKey: key)
        let loaded = SenseGripFitStore.load(left: left, defaults: saved)
        let other = SenseGripFit(translation: [-0.02, 0.01, 0], yawDegrees: 40)
        #expect(SenseGripFitStore.save(other, left: !left, defaults: saved))
        let game = fixture(saved, left: left)
        defer { game.stop(); saved.removePersistentDomain(forName: name) }
        game.assets.root.orientation = simd_quatf(angle: left ? -0.65 : 0.75, axis: [0, 1, 0])
        let natural = game.assets.root.transformMatrix(relativeTo: nil) * grip(left ? -0.9 : 1.1)
        var clock = SampleClock()
        commit(game, grip: natural, clock: &clock)
        #expect(game.controllerAlignmentRequired && game.controllerGripFit != SenseGripFit())
        #expect(matrixMatches(game.controllerGripFit.offset, loaded.offset))
        game.beginInitialControllerAlignmentIfNeeded()
        #expect(game.isControllerAlignmentPending)
        tick(game, grip: natural, clock: &clock, count: 15)
        #expect(game.isControllerAlignmentPending && game.controllerAlignmentRequired)
        #expect(saved.data(forKey: key) == bytes)
        let handle = game.assets.racket.transformMatrix(relativeTo: game.assets.root).columns.3
        tick(game, grip: natural, clock: &clock, count: 1)
        let displayed = game.assets.racket.transformMatrix(relativeTo: game.assets.root)
        #expect(!game.isControllerAlignmentPending && !game.controllerAlignmentRequired)
        #expect(game.controllerAlignmentFailure == nil && saved.data(forKey: key) != bytes)
        #expect(simd_distance(displayed.columns.1, SIMD4<Float>(0, 1, 0, 0)) < 0.0001)
        #expect(simd_distance(displayed.columns.2, SIMD4<Float>(0, 0, 1, 0)) < 0.0001)
        #expect(simd_distance(displayed.columns.3, handle) < 0.0001)
        #expect(game.controllerGripFit.translation == loaded.translation)
        #expect(matrixMatches(SenseGripFitStore.load(left: !left, defaults: saved).offset, other.offset))
        #expect(!game.controllerContactReady && game.controllerHeadVelocity == .zero && game.lastContact == nil)
        commit(game, grip: natural, clock: &clock, velocity: [0, 8, -12])
        #expect(!game.controllerContactReady && game.controllerHeadVelocity == .zero)
    }

    @Test func resetRequiresAFreshCaptureAndBlocksServeEvenBeforeTheCaptureBegins() throws {
        let (saved, name) = try defaults()
        let game = fixture(saved)
        defer { game.stop(); saved.removePersistentDomain(forName: name) }
        let natural = grip()
        var clock = SampleClock()
        commit(game, grip: natural, clock: &clock)
        game.setControllerGripFit(SenseGripFit(translation: [0.02, -0.01, 0], yawDegrees: 35))
        #expect(!game.controllerAlignmentRequired)
        game.beginInitialControllerAlignmentIfNeeded()
        #expect(!game.isControllerAlignmentPending)
        game.resetControllerGrip()
        #expect(game.controllerAlignmentRequired && game.controllerGripFit == SenseGripFit())
        #expect(!saved.bool(forKey: "ShuttleClub.SenseNaturalHold.right.v2"))
        game.serve()
        #expect(game.canServe && !game.isPreparingServe && game.shuttleState == nil)
        game.beginInitialControllerAlignmentIfNeeded()
        #expect(game.isControllerAlignmentPending)
        tick(game, grip: natural, clock: &clock, count: 16)
        #expect(!game.controllerAlignmentRequired && !game.isControllerAlignmentPending)
        commit(game, grip: natural, clock: &clock)
        game.serve()
        #expect(game.isPreparingServe && !game.canServe && game.shuttleState == nil)
        #expect(game.lastContact == nil && game.rallyHits == 0)
    }

    @Test func firstFrameTriggerIsBlockedBeforeAutomaticAlignmentDispatch() throws {
        let (saved, name) = try defaults()
        let game = fixture(saved)
        defer { game.stop(); saved.removePersistentDomain(forName: name) }
        let natural = grip(-0.7)
        var clock = SampleClock()
        game.showPlaySetup = true
        commit(game, grip: natural, clock: &clock)
        game.beginInitialControllerAlignmentIfNeeded()
        #expect(!game.isControllerAlignmentPending)
        game.finishTrackingSetup()
        commit(game, grip: natural, clock: &clock)
        // The real adapter dispatches a Trigger edge inside updateRacket,
        // before update calls beginInitialControllerAlignmentIfNeeded.
        game.serve()
        #expect(game.racketReady && game.controllerAlignmentRequired)
        #expect(game.canServe && !game.isPreparingServe && game.shuttleState == nil)
        game.beginInitialControllerAlignmentIfNeeded()
        tick(game, grip: natural, clock: &clock, count: 15)
        game.serve()
        #expect(game.canServe && !game.isPreparingServe)
        tick(game, grip: natural, clock: &clock, count: 1)
        commit(game, grip: natural, clock: &clock)
        game.serve()
        #expect(game.isPreparingServe && game.serveCountdown == 0.65)
        #expect(game.lastContact == nil)
    }

    @Test func movingHoldTimeoutRetainsTheOldFitAndRequiresExplicitRetry() throws {
        let (saved, name) = try defaults()
        let old = SenseGripFit(translation: [0.025, -0.015, 0], pitchDegrees: 25, yawDegrees: -30)
        #expect(SenseGripFitStore.save(old, left: false, defaults: saved))
        let bytes = try #require(saved.data(forKey: "ShuttleClub.SenseGripFit.right.v1"))
        let game = fixture(saved)
        defer { game.stop(); saved.removePersistentDomain(forName: name) }
        var clock = SampleClock()
        let natural = grip()
        commit(game, grip: natural, clock: &clock)
        game.beginInitialControllerAlignmentIfNeeded()
        for frame in 1...61 {
            let moving = natural * simd_float4x4(simd_quatf(angle: Float(frame) * 0.02, axis: [0, 1, 0]))
            commit(game, grip: moving, clock: &clock)
            game.updateControllerAlignment(0.1)
        }
        #expect(!game.isControllerAlignmentPending && game.controllerAlignmentRequired)
        #expect(game.controllerAlignmentFailure?.isEmpty == false)
        #expect(saved.data(forKey: "ShuttleClub.SenseGripFit.right.v1") == bytes)
        #expect(matrixMatches(game.controllerGripFit.offset, old.offset))
        game.beginInitialControllerAlignmentIfNeeded()
        #expect(!game.isControllerAlignmentPending)
        game.serve()
        #expect(game.canServe && !game.isPreparingServe && game.shuttleState == nil)
        commit(game, grip: natural, clock: &clock)
        game.beginControllerAlignment()
        #expect(game.isControllerAlignmentPending && game.controllerAlignmentFailure == nil)
        tick(game, grip: natural, clock: &clock, count: 16)
        #expect(!game.isControllerAlignmentPending && !game.controllerAlignmentRequired)
        #expect(game.controllerAlignmentFailure == nil && !game.controllerContactReady)
        #expect(saved.data(forKey: "ShuttleClub.SenseGripFit.right.v1") != bytes)
        #expect(game.lastContact == nil && game.shuttleState == nil)
    }

    @Test func onlyAValidManualFitEditConfirmsTheSelectedSide() throws {
        let (saved, name) = try defaults()
        let game = fixture(saved)
        defer { game.stop(); saved.removePersistentDomain(forName: name) }
        var clock = SampleClock()
        commit(game, grip: grip(), clock: &clock)
        game.setControllerGripFit(SenseGripFit(calibratedOrientation: [.nan, 0, 0, 1]))
        #expect(game.controllerAlignmentRequired)
        #expect(saved.data(forKey: "ShuttleClub.SenseGripFit.right.v1") == nil)
        game.setControllerGripFit(SenseGripFit(yawDegrees: -45))
        #expect(!game.controllerAlignmentRequired)
        #expect(saved.bool(forKey: "ShuttleClub.SenseNaturalHold.right.v2"))
        #expect(!saved.bool(forKey: "ShuttleClub.SenseNaturalHold.left.v2"))
        let relaunched = GameModel(gripDefaults: saved)
        #expect(!relaunched.controllerAlignmentRequired)
        #expect(matrixMatches(relaunched.controllerGripFit.offset, game.controllerGripFit.offset))
    }

    @Test func pausedRealFlightCannotResumeAfterResetUntilTheNewHoldIsCaptured() throws {
        let (saved, name) = try defaults()
        let game = fixture(saved)
        defer { game.stop(); saved.removePersistentDomain(forName: name) }
        let natural = grip(-0.6)
        var clock = SampleClock()
        commit(game, grip: natural, clock: &clock)
        game.setControllerGripFit(SenseGripFit(translation: [0.015, -0.01, 0], yawDegrees: -25))
        commit(game, grip: natural, clock: &clock)
        game.serve()
        #expect(game.isPreparingServe && !game.controllerAlignmentRequired)
        for _ in 0..<7 { game.updateServePreparation(0.1) }
        let incoming = try #require(game.shuttleState)
        #expect(!game.isPreparingServe && game.rallyInProgress && !game.canServe)

        game.paused = true
        game.resetControllerGrip()
        #expect(game.controllerAlignmentRequired && !game.canResumeRally)
        #expect(game.controllerAlignmentFailure?.isEmpty == false)
        // This is the actual UI assignment, not just its disabled-state test.
        game.paused = false
        #expect(game.paused)
        game.handleControllerMenu()
        #expect(game.paused)
        game.update(0.05)
        #expect(game.shuttleState?.position == incoming.position)
        #expect(game.shuttleState?.velocity == incoming.velocity)

        // The paused real flight keeps canServe false. Startup must still be
        // able to begin capture, without restarting or replacing that flight.
        commit(game, grip: natural, clock: &clock)
        game.beginInitialControllerAlignmentIfNeeded()
        #expect(game.isControllerAlignmentPending && game.paused && !game.canServe)
        tick(game, grip: natural, clock: &clock, count: 15)
        game.paused = false
        game.handleControllerMenu()
        #expect(game.paused && !game.canResumeRally)
        #expect(game.shuttleState?.position == incoming.position)
        #expect(game.shuttleState?.velocity == incoming.velocity)
        tick(game, grip: natural, clock: &clock, count: 1)
        #expect(game.paused && game.canResumeRally && !game.controllerAlignmentRequired)
        #expect(!game.isControllerAlignmentPending && game.controllerAlignmentFailure == nil)
        #expect(!game.controllerContactReady && game.controllerHeadVelocity == .zero)
        commit(game, grip: natural, clock: &clock, velocity: [0, 8, -12])
        #expect(!game.controllerContactReady && game.controllerHeadVelocity == .zero)

        game.paused = false
        #expect(!game.paused && game.canResumeRally)
        game.paused = true
        game.handleControllerMenu()
        #expect(!game.paused && game.rallyInProgress)
        #expect(game.shuttleState?.position == incoming.position)
        #expect(game.shuttleState?.velocity == incoming.velocity)
        #expect(game.lastContact == nil && game.rallyHits == 0)
    }
}
