import Foundation
import Testing
import QuartzCore
import RealityKit
import simd
import ShuttleCore
@testable import ShuttleClub

@MainActor @Suite(.serialized)
struct ControllerAlignmentCountdownTests {
    /// Simulation dt drives the countdown. Anchor time remains a fresh,
    /// ordered acquisition clock rather than pretending three wall seconds
    /// passed while this synchronous regression runs.
    private struct SampleClock {
        private var previous: Double = 0
        mutating func next() -> Double {
            previous = max(CACurrentMediaTime(), previous + 0.00001)
            return previous
        }
    }

    private func defaults() throws -> (UserDefaults, String) {
        let name = "ShuttleClub.ControllerAlignmentTests.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: name)), name)
    }
    private func fixture(_ saved: UserDefaults, left: Bool = false) -> GameModel {
        let game = GameModel(gripDefaults: saved)
        game.input = .sense; game.leftHand = left; game.automaticServing = false
        game.soundEnabled = false; game.musicEnabled = false
        ClubScene.robot(game.assets)
        game.assets.root.addChild(game.assets.milo)
        game.assets.root.addChild(game.assets.racket)
        game.assets.root.addChild(game.assets.shuttle)
        game.restart(); game.setCourtMovement(.stationary)
        return game
    }
    private func pose(_ rotation: simd_quatf, position: V3) -> simd_float4x4 {
        var result = simd_float4x4(rotation)
        result.columns.3 = SIMD4<Float>(position, 1)
        return result
    }
    private func commit(_ game: GameModel, grip: simd_float4x4,
                        timestamp: Double, velocity: V3 = .zero) {
        let mounted = game.controllerGripFit.mountedPose(fromGrip: grip)
        game.receiveControllerPose(.init(originFromGrip: grip, leftHand: game.leftHand,
            measured: mounted, rendered: mounted, headVelocity: velocity, timestamp: timestamp))
    }
    private func tick(_ game: GameModel, grip: simd_float4x4, clock: inout SampleClock,
                      count: Int, dt: Float = 0.1) {
        for _ in 0..<count {
            commit(game, grip: grip, timestamp: clock.next())
            game.updateControllerAlignment(dt)
        }
    }
    private func matches(_ a: simd_float4x4, _ b: simd_float4x4) -> Bool {
        (0..<4).allSatisfy { simd_distance(a[$0], b[$0]) < 0.0001 }
    }
    private func displayed(_ game: GameModel) -> simd_float4x4 {
        game.assets.racket.transformMatrix(relativeTo: game.assets.root)
    }
    private func expectUpright(_ game: GameModel) {
        let matrix = displayed(game)
        #expect(simd_distance(matrix.columns.1, SIMD4<Float>(0, 1, 0, 0)) < 0.0001)
        #expect(simd_distance(matrix.columns.2, SIMD4<Float>(0, 0, 1, 0)) < 0.0001)
    }

    @Test(arguments: [false, true])
    func capturesTheNaturalHoldAfterMenuPointingAndPreservesBothHands(left: Bool) throws {
        let (saved, name) = try defaults(); defer { saved.removePersistentDomain(forName: name) }
        let other = SenseGripFit(translation: [-0.01, 0.025, 0], pitchDegrees: -17, yawDegrees: 30)
        #expect(SenseGripFitStore.save(other, left: !left, defaults: saved))
        let game = fixture(saved, left: left)
        let court = pose(simd_quatf(angle: left ? -0.85 : 0.65, axis: [0, 1, 0]),
                         position: [0.8, -0.15, -1.2])
        game.assets.root.transform = Transform(matrix: court)
        let pointing = court * pose(simd_quatf(angle: -0.3, axis: [1, 0, 0]), position: [0.2, 1.25, -0.55])
        let natural = court * pose(simd_quatf(angle: left ? -1.1 : 0.9,
            axis: simd_normalize(V3(1, -2, 3))), position: [0.3, 1.15, -0.4])
        var clock = SampleClock()
        commit(game, grip: pointing, timestamp: clock.next())
        let chosen = SenseGripFit(translation: [0.03, -0.02, 0.015], pitchDegrees: 16,
                                  yawDegrees: -22, rollDegrees: 11)
        game.setControllerGripFit(chosen)
        game.showPlaySetup = true; game.beginControllerAlignment()
        #expect(game.isControllerAlignmentPending && game.controllerAlignmentCountdown == 3)
        tick(game, grip: natural, clock: &clock, count: 29)
        #expect(game.isControllerAlignmentPending && game.controllerAlignmentCountdown > 0)
        #expect(matches(game.controllerGripFit.offset, chosen.offset))
        let handleBefore = displayed(game).columns.3
        tick(game, grip: natural, clock: &clock, count: 1)
        #expect(!game.isControllerAlignmentPending)
        expectUpright(game)
        #expect(simd_distance(displayed(game).columns.3, handleBefore) < 0.0001)
        #expect(game.controllerGripFit.translation == chosen.translation)
        #expect(game.controllerGripFit.pitchDegrees == 0 && game.controllerGripFit.yawDegrees == 0
                && game.controllerGripFit.rollDegrees == 0)
        #expect(matches(SenseGripFitStore.load(left: left, defaults: saved).mountedPose(fromGrip: natural),
                        court * displayed(game)))
        #expect(matches(SenseGripFitStore.load(left: !left, defaults: saved).offset, other.offset))
        #expect(saved.bool(forKey: "ShuttleClub.SenseNaturalHold.\(left ? "left" : "right").v2"))
        #expect(!game.controllerContactReady && game.controllerHeadVelocity == .zero)
        commit(game, grip: natural, timestamp: clock.next(), velocity: [0, 8, -10])
        #expect(game.racketReady && !game.controllerContactReady && game.controllerHeadVelocity == .zero)
        expectUpright(game)
        #expect(game.lastContact == nil && game.rallyHits == 0 && game.shuttleState == nil)
    }

    enum Interruption: CaseIterable { case background, input, hand, stale, trackingLoss, cancel }
    @Test(arguments: Interruption.allCases)
    func interruptedCaptureCannotOverwriteThePreviousFit(reason: Interruption) throws {
        let (saved, name) = try defaults(); defer { saved.removePersistentDomain(forName: name) }
        let game = fixture(saved)
        let grip = pose(simd_quatf(angle: 0.7, axis: simd_normalize(V3(1, 2, 3))), position: [0.3, 1.2, -0.4])
        var clock = SampleClock()
        commit(game, grip: grip, timestamp: clock.next())
        let chosen = SenseGripFit(translation: [0.025, 0.01, -0.02], pitchDegrees: 25, rollDegrees: -12)
        game.setControllerGripFit(chosen); game.beginControllerAlignment()
        tick(game, grip: grip, clock: &clock, count: 10)
        #expect(game.isControllerAlignmentPending)
        switch reason {
        case .background: game.sceneActivityChanged(active: false)
        case .input: game.input = .hands
        case .hand: game.leftHand = true
        case .stale: commit(game, grip: grip, timestamp: CACurrentMediaTime() - 1)
        case .trackingLoss: game.receiveControllerPose(nil)
        case .cancel: game.cancelControllerAlignment()
        }
        game.updateControllerAlignment(0.1)
        #expect(!game.isControllerAlignmentPending)
        game.sceneActivityChanged(active: true); game.input = .sense; game.leftHand = false
        tick(game, grip: grip, clock: &clock, count: 40)
        #expect(matches(game.controllerGripFit.offset, chosen.offset))
        #expect(matches(SenseGripFitStore.load(left: false, defaults: saved).offset, chosen.offset))
        #expect(!saved.bool(forKey: "ShuttleClub.SenseNaturalHold.right.v2"))
        #expect(game.lastContact == nil && game.shuttleState == nil)
    }

    @Test(arguments: [false, true])
    func movingTheControllerRestartsTheFullStableHold(rotation: Bool) throws {
        let (saved, name) = try defaults(); defer { saved.removePersistentDomain(forName: name) }
        let game = fixture(saved)
        let initial = pose(simd_quatf(angle: 0.4, axis: [1, 0, 0]), position: [0.2, 1.1, -0.4])
        var clock = SampleClock()
        commit(game, grip: initial, timestamp: clock.next()); game.beginControllerAlignment()
        tick(game, grip: initial, clock: &clock, count: 15)
        #expect(game.controllerAlignmentCountdown < 1.6)
        var moved = initial
        if rotation { moved = initial * simd_float4x4(simd_quatf(angle: 0.2, axis: [0, 1, 0])) }
        else { moved.columns.3.x += 0.03 }
        tick(game, grip: moved, clock: &clock, count: 1)
        #expect(game.controllerAlignmentCountdown > 2.8 && game.isControllerAlignmentPending)
        tick(game, grip: moved, clock: &clock, count: 28)
        #expect(game.isControllerAlignmentPending)
        tick(game, grip: moved, clock: &clock, count: 1)
        #expect(!game.isControllerAlignmentPending)
        expectUpright(game)
    }

    @Test func triggerCannotStartARealServeUntilNaturalHoldCaptureCompletes() throws {
        let (saved, name) = try defaults(); defer { saved.removePersistentDomain(forName: name) }
        let game = fixture(saved)
        let grip = pose(simd_quatf(angle: 1.1, axis: simd_normalize(V3(1, -1, 2))), position: [0.2, 1.2, -0.4])
        var clock = SampleClock()
        commit(game, grip: grip, timestamp: clock.next()); game.beginControllerAlignment()
        game.serve()
        #expect(game.canServe && !game.isPreparingServe && game.shuttleState == nil)
        tick(game, grip: grip, clock: &clock, count: 29)
        game.serve()
        #expect(game.canServe && !game.isPreparingServe && game.shuttleState == nil)
        tick(game, grip: grip, clock: &clock, count: 1)
        #expect(!game.isControllerAlignmentPending)
        commit(game, grip: grip, timestamp: clock.next())
        game.serve()
        #expect(!game.canServe && game.isPreparingServe && game.serveCountdown == 0.65)
        #expect(game.shuttleState == nil && game.lastContact == nil)
    }

    @Test(arguments: [false, true])
    func tinyCumulativeDriftCannotBecomeAStableThreeSecondHold(rotation: Bool) throws {
        let (saved, name) = try defaults(); defer { saved.removePersistentDomain(forName: name) }
        let game = fixture(saved)
        let initial = pose(simd_quatf(angle: 0.4, axis: [1, 0, 0]), position: [0.2, 1.1, -0.4])
        var clock = SampleClock()
        commit(game, grip: initial, timestamp: clock.next())
        let chosen = SenseGripFit(translation: [0.02, -0.015, 0.01], pitchDegrees: 18,
                                  yawDegrees: -25, rollDegrees: 9)
        game.setControllerGripFit(chosen)
        let savedBefore = try #require(saved.data(forKey: "ShuttleClub.SenseGripFit.right.v1"))
        game.beginControllerAlignment()
        for frame in 1...30 {
            var drifting = initial
            if rotation {
                drifting = initial * simd_float4x4(simd_quatf(angle: Float(frame) * 0.02, axis: [0, 1, 0]))
            } else {
                drifting.columns.3.x += Float(frame) * 0.001
            }
            commit(game, grip: drifting, timestamp: clock.next())
            game.updateControllerAlignment(0.1)
            #expect(game.isControllerAlignmentPending)
        }
        // Every individual step is below the reset threshold, but a stable
        // window must reject the accumulated .03m or .6rad displacement.
        #expect(game.controllerAlignmentCountdown > 0.1)
        #expect(matches(game.controllerGripFit.offset, chosen.offset))
        #expect(saved.data(forKey: "ShuttleClub.SenseGripFit.right.v1") == savedBefore)
        #expect(!saved.bool(forKey: "ShuttleClub.SenseNaturalHold.right.v2"))
        #expect(game.lastContact == nil && game.shuttleState == nil)
    }

    @Test func zeroElapsedTimeNeitherCancelsNorAdvancesPendingAlignment() throws {
        let (saved, name) = try defaults(); defer { saved.removePersistentDomain(forName: name) }
        let game = fixture(saved)
        let grip = pose(simd_quatf(angle: 0.8, axis: [0, 1, 0]), position: [0.3, 1.2, -0.4])
        var clock = SampleClock()
        commit(game, grip: grip, timestamp: clock.next()); game.beginControllerAlignment()
        for _ in 0..<10 { game.updateControllerAlignment(0) }
        #expect(game.isControllerAlignmentPending && game.controllerAlignmentCountdown == 3)
        tick(game, grip: grip, clock: &clock, count: 5)
        let remaining = game.controllerAlignmentCountdown
        game.updateControllerAlignment(0)
        #expect(game.isControllerAlignmentPending && game.controllerAlignmentCountdown == remaining)
        #expect(game.controllerGripFit == SenseGripFit())
        #expect(saved.data(forKey: "ShuttleClub.SenseGripFit.right.v1") == nil)
        #expect(game.lastContact == nil && game.shuttleState == nil)
    }
}
