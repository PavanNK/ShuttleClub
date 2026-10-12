import Foundation
import Testing
import QuartzCore
import RealityKit
import simd
import ShuttleCore
@testable import ShuttleClub

/// Synthetic, fresh measured poses exercise the native game/scene path.
/// These fixtures do not establish physical tracking quality or comfort.
@MainActor @Suite(.serialized)
struct ComfortableServeTests {
    enum FixtureMode: String, CaseIterable {
        case senseStationary, senseThumbstick, handsThumbstick
        var input: InputMode { self == .handsThumbstick ? .hands : .sense }
        var movement: CourtMovement { self == .senseStationary ? .stationary : .thumbstick }
    }
    private struct SampleClock {
        private var previous: Double = 0
        mutating func next() -> Double {
            previous = max(CACurrentMediaTime(), previous + 0.000001)
            return previous
        }
    }
    private func defaults() throws -> (UserDefaults, String) {
        let name = "ShuttleClub.ComfortableServeTests.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: name)), name)
    }
    private func game(_ saved: UserDefaults, mode: FixtureMode,
                      left: Bool = false, confirmedFit: Bool = true) -> GameModel {
        if confirmedFit {
            saved.set(true, forKey: "ShuttleClub.SenseNaturalHold.\(left ? "left" : "right").v2")
        }
        let game = GameModel(gripDefaults: saved)
        game.input = mode.input; game.leftHand = left; game.mode = .practice
        game.soundEnabled = false; game.musicEnabled = false; game.automaticServing = false
        game.difficulty = .friendly; game.racketKind = .coral
        game.setCourtMovement(mode.movement)
        ClubScene.robot(game.assets)
        game.assets.root.addChild(game.assets.milo); game.assets.milo.scale = [1.35, 1.35, 1.35]
        game.assets.root.addChild(game.assets.racket); game.assets.root.addChild(game.assets.shuttle)
        game.assets.root.addChild(game.assets.interfaceRoot)
        game.selectRacket(.coral); game.restart()
        return game
    }
    private func racketPose(head: V3, rotation: simd_quatf = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])) -> simd_float4x4 {
        var result = simd_float4x4(rotation)
        result.columns.3 = SIMD4(head - rotation.act(V3(0, 0.37, 0)), 1)
        return result
    }
    private func commit(_ game: GameModel, racket: simd_float4x4, clock: inout SampleClock) {
        if game.input == .sense {
            // Construct the actual grip whose selected fit produces the supplied
            // measured racket. Render prediction is deliberately irrelevant.
            let grip = racket * simd_inverse(SenseGripFit.baseMount * game.controllerGripFit.offset)
            let mounted = game.controllerGripFit.mountedPose(fromGrip: grip)
            game.receiveControllerPose(.init(originFromGrip: grip, leftHand: game.leftHand,
                measured: mounted, rendered: mounted, headVelocity: .zero, timestamp: clock.next()))
        } else {
            // Timestamp-less samples use simulation dt for measured motion,
            // as the existing native scripted-contact fixtures do.
            game.receiveHandPose(racket)
        }
    }
    private func prime(_ game: GameModel, racket: simd_float4x4, clock: inout SampleClock) {
        commit(game, racket: racket, clock: &clock)
        if game.input == .hands { game.update(0) }
        commit(game, racket: racket, clock: &clock)
        if game.input == .hands { game.update(1 / 120) }
    }
    private func finishPreparation(_ game: GameModel, racket: simd_float4x4,
                                   clock: inout SampleClock) {
        for _ in 0..<100 {
            guard game.isPreparingServe, !game.paused else { break }
            commit(game, racket: racket, clock: &clock)
            if game.input == .sense {
                // This is the same production preparation method update()
                // invokes. update() itself would poll a nonexistent ARKit
                // accessory provider and discard this explicit fixture pose.
                game.updateServePreparation(1 / 120)
            } else { game.update(1 / 120) }
            let strings = game.assets.robotRacket.convert(position: [0, 0.37, 0], to: game.assets.root)
            #expect(simd_distance(game.assets.shuttle.position, strings) < 0.0001)
            #expect(game.lastContact == nil && game.rallyHits == 0)
        }
    }
    private struct ReceivingProfile {
        var point: V3
        var velocity: V3
        var time: Float
        var apex: Float
        var netHeight: Float
    }
    private func receivingProfile(_ flight: Flight, height: Float) throws -> ReceivingProfile {
        var probe = flight
        var elapsed: Float = 0
        var apex = probe.position.y
        var net: Float?
        let dt: Float = 1 / 240
        for _ in 0..<480 {
            let before = probe
            probe.step(dt); elapsed += dt
            apex = max(apex, probe.position.y)
            if let crossing = Court.crossingHeight(from: before.position, to: probe.position) { net = crossing }
            if probe.velocity.y < 0, before.position.y >= height, probe.position.y <= height,
               probe.position.z > Court.netZ {
                let fraction = (before.position.y - height) / (before.position.y - probe.position.y)
                return ReceivingProfile(point: before.position + (probe.position - before.position) * fraction,
                    velocity: before.velocity + (probe.velocity - before.velocity) * fraction,
                    time: elapsed - dt + dt * fraction, apex: apex, netHeight: try #require(net))
            }
        }
        Issue.record("No descending receiving-height crossing in the actual native launch")
        throw ProfileError.noReceivingCrossing
    }
    private enum ProfileError: Error { case noReceivingCrossing }
    private func verifyProfile(_ profile: ReceivingProfile, expected: V3) {
        let horizontal = simd_length(SIMD2(profile.velocity.x, profile.velocity.z))
        let angle = atan2(-profile.velocity.y, horizontal) * 180 / .pi
        #expect(simd_distance(profile.point, expected) < 0.015)
        #expect(profile.time >= 0.49 && profile.time <= 1.41)
        #expect(profile.apex <= 3.2)
        #expect(profile.netHeight >= Court.netHeight + 0.25)
        #expect(profile.velocity.y < 0 && -profile.velocity.y <= 5.001)
        #expect(angle <= 55.01)
        #expect(simd_length(profile.velocity) <= 9.001)
    }

    @Test(arguments: FixtureMode.allCases, [false, true])
    func actualNativeReleaseFeedsTheSelectedHeldSideAtReceivingHeights(mode: FixtureMode, left: Bool) throws {
        for height: Float in [1.15, 1.6, 1.85] {
            let (saved, name) = try defaults(); defer { saved.removePersistentDomain(forName: name) }
            let game = game(saved, mode: mode, left: left)
            let head = V3(left ? -0.65 : 0.65, height, -0.4)
            let racket = racketPose(head: head)
            var clock = SampleClock()
            prime(game, racket: racket, clock: &clock)
            #expect(game.racketReady && !game.controllerAlignmentRequired)
            game.serve(); try #require(game.isPreparingServe)
            #expect(simd_distance(game.playerReturnTarget, head) < 0.001)
            finishPreparation(game, racket: racket, clock: &clock)
            let flight = try #require(game.shuttleState)
            let actualRelease = game.assets.robotRacket.convert(position: [0, 0.37, 0], to: game.assets.root)
            #expect(simd_distance(flight.position, actualRelease) < 0.0001)
            #expect(flight.velocity.z > 0 && !game.isPreparingServe && !game.paused)
            #expect(game.score.player == 0 && game.score.milo == 0 && game.lastContact == nil)
            let expected = head + V3(sin(Float(1) * 1.7) * 0.12, 0, 0)
            let measured = try receivingProfile(flight, height: height)
            verifyProfile(measured, expected: expected)
            if mode == .handsThumbstick { #expect(game.effectiveCourtMovement == .autoGlide) }
            else { #expect(game.effectiveCourtMovement == mode.movement) }
            print("NATIVE COMFORTABLE SERVE \(mode.rawValue) \(left ? "left" : "right") height=\(height)m: arrival=\(measured.time)s apex=\(measured.apex)m net=\(measured.netHeight)m point=\(measured.point)")
        }
    }

    @Test(arguments: [false, true])
    func unconfirmedDefaultSenseFitCannotLaunchUntilExplicitlyAligned(left: Bool) throws {
        let (saved, name) = try defaults(); defer { saved.removePersistentDomain(forName: name) }
        let game = game(saved, mode: .senseStationary, left: left, confirmedFit: false)
        let racket = racketPose(head: [left ? -0.5 : 0.5, 1.6, -0.4])
        var clock = SampleClock()
        prime(game, racket: racket, clock: &clock)
        #expect(game.racketReady && game.controllerAlignmentRequired)
        game.serve()
        #expect(game.canServe && !game.isPreparingServe && game.shuttleState == nil)
        #expect(game.playerReturnTarget == V3(0, 1.6, -0.25))
        #expect(game.score.player == 0 && game.score.milo == 0 && game.lastContact == nil)
        game.setGrip()
        #expect(!game.controllerAlignmentRequired)
        #expect(saved.bool(forKey: "ShuttleClub.SenseNaturalHold.\(left ? "left" : "right").v2"))
        let grip = racket * simd_inverse(SenseGripFit.baseMount)
        let fitted = game.controllerGripFit.mountedPose(fromGrip: grip)
        prime(game, racket: fitted, clock: &clock)
        game.serve(); try #require(game.isPreparingServe)
        finishPreparation(game, racket: fitted, clock: &clock)
        #expect(game.shuttleState != nil && game.lastContact == nil)
    }

    enum CaptureGate: CaseIterable { case setup, courtMenu, settings, rackets, paused }
    @Test(arguments: CaptureGate.allCases)
    func menuPointingAndPausedPosesCannotBecomeTheReadyFeedTarget(gate: CaptureGate) throws {
        let (saved, name) = try defaults(); defer { saved.removePersistentDomain(forName: name) }
        let game = game(saved, mode: .handsThumbstick)
        game.setCourtMovement(.stationary)
        switch gate {
        case .setup: game.showPlaySetup = true
        case .courtMenu: game.showCourtMenu = true
        case .settings: game.showSettings = true
        case .rackets: game.showRackets = true
        case .paused: game.paused = true
        }
        var clock = SampleClock()
        let pointing = racketPose(head: [-0.7, 1.85, -0.15])
        prime(game, racket: pointing, clock: &clock)
        game.serve()
        #expect(!game.isPreparingServe && game.shuttleState == nil)
        #expect(game.playerReturnTarget == V3(0, 1.6, -0.25))
        game.showPlaySetup = false; game.showCourtMenu = false
        game.showSettings = false; game.showRackets = false; game.paused = false
        let ready = V3(0.5, 1.2, -0.65)
        prime(game, racket: racketPose(head: ready), clock: &clock)
        game.serve(); try #require(game.isPreparingServe)
        #expect(simd_distance(game.playerReturnTarget, ready) < 0.001)
        #expect(game.lastContact == nil && game.score.player == 0 && game.score.milo == 0)
    }

    @Test(arguments: [Difficulty.friendly, .club, .challenge])
    func openingFeedsKeepTheirHeightBoundWhilePreservingDifficultyVariation(difficulty: Difficulty) throws {
        let (saved, name) = try defaults(); defer { saved.removePersistentDomain(forName: name) }
        let game = game(saved, mode: .senseStationary)
        game.difficulty = difficulty
        let head = V3(-0.5, 1.5, -0.6), racket = racketPose(head: head)
        var clock = SampleClock()
        prime(game, racket: racket, clock: &clock)
        game.serve(); try #require(game.isPreparingServe)
        finishPreparation(game, racket: racket, clock: &clock)
        let profile = try receivingProfile(try #require(game.shuttleState), height: head.y)
        let variation: Float = difficulty == .friendly ? 0.12 : 0.35
        verifyProfile(profile, expected: head + V3(sin(Float(1) * 1.7) * variation, 0, 0))
    }

    @Test(arguments: [false, true])
    func comfortableFeedOnlyReturnsAfterARealSweptStringContact(miss: Bool) throws {
        let (saved, name) = try defaults(); defer { saved.removePersistentDomain(forName: name) }
        let game = game(saved, mode: .handsThumbstick)
        game.setCourtMovement(.stationary)
        let ready = racketPose(head: [0.65, 1.4, -0.4])
        var clock = SampleClock()
        prime(game, racket: ready, clock: &clock)
        game.serve(); finishPreparation(game, racket: ready, clock: &clock)
        let launched = try #require(game.shuttleState)
        let receiver = try receivingProfile(launched, height: 1.4)
        let offset: Float = miss ? 0.8 : 0
        let angle = simd_quatf(angle: 0.6, axis: [1, 0, 0])
        let start = receiver.point + V3(offset, -0.36, 0.48)
        game.receiveHandPose(racketPose(head: start, rotation: angle)); game.update(0)
        let dt: Float = 1 / 120
        var elapsed: Float = 0
        for _ in 0..<400 {
            let u = min(0.12, max(-0.12, elapsed + dt - receiver.time))
            let head = receiver.point + V3(offset, 3 * u, -4 * u)
            game.receiveHandPose(racketPose(head: head, rotation: angle)); game.update(dt)
            elapsed += dt
            if game.lastContact?.side == .player || game.shuttleState == nil { break }
            #expect(game.lastContact == nil && game.rallyHits == 0)
            if game.shuttleState != nil { #expect(game.score.player == 0 && game.score.milo == 0) }
        }
        if miss {
            #expect(game.lastContact == nil && game.rallyHits == 0)
            #expect(game.shuttleState == nil && game.score.milo == 1 && game.score.player == 0)
        } else {
            let hit = try #require(game.lastContact)
            #expect(hit.side == .player && game.rallyHits == 1)
            #expect(simd_distance(hit.cork, hit.stringPoint) <= 0.040006)
            #expect(simd_distance(hit.headVelocity, V3(0, 3, -4)) < 0.001)
            #expect(game.score.player == 0 && game.score.milo == 0)
        }
    }

    @Test func infeasibleActualReleasePausesAtTheNavigationBoundaryWithoutAwardingAPoint() throws {
        let (saved, name) = try defaults(); defer { saved.removePersistentDomain(forName: name) }
        let game = game(saved, mode: .senseThumbstick)
        let physical = racketPose(head: [0.65, 1.15, -0.85])
        var clock = SampleClock()
        prime(game, racket: physical, clock: &clock)
        for _ in 0..<45 {
            commit(game, racket: physical, clock: &clock)
            game.advanceCourtMovement(0.1, stick: [0, 1])
        }
        #expect(abs(game.virtualCourtPosition.y - CourtNavigation.minPosition.y) < 0.001)
        // An intentionally extreme but finite native actor pose puts the
        // actual cork 5cm behind the net. A low receiver cannot simultaneously
        // clear by 25cm and satisfy the bounded descending-angle/speed limits.
        // This is a failure-path fixture, not a claimed normal AI stance.
        game.assets.milo.position = [0.4, 0, -5.305]
        commit(game, racket: physical, clock: &clock)
        game.serve(); try #require(game.isPreparingServe)
        #expect(abs(game.playerReturnTarget.z + 4.2) < 0.001)
        finishPreparation(game, racket: physical, clock: &clock)
        let actualRelease = game.assets.robotRacket.convert(position: [0, 0.37, 0], to: game.assets.root)
        #expect(actualRelease.z < Court.netZ && actualRelease.z > Court.netZ - 0.06)
        #expect(game.paused && game.canServe && !game.isPreparingServe)
        #expect(game.shuttleState == nil && game.lastContact == nil && game.rallyHits == 0)
        #expect(game.score.player == 0 && game.score.milo == 0)
        #expect(game.message.contains("comfortable serve"))
        #expect(game.virtualCourtSpeed == 0)
        commit(game, racket: physical, clock: &clock); game.serve()
        #expect(!game.isPreparingServe && game.shuttleState == nil)
    }
}
