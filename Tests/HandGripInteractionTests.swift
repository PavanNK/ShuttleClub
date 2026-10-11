import Foundation
import Testing
import QuartzCore
import RealityKit
import simd
import ShuttleCore
@testable import ShuttleClub

@MainActor @Suite(.serialized)
struct HandGripInteractionTests {
    private func defaults() throws -> (UserDefaults, String) {
        let name = "ShuttleClub.HandGripInteractionTests.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: name)), name)
    }

    private func fixture(_ saved: UserDefaults, withRobot: Bool = false) -> GameModel {
        let game = GameModel(gripDefaults: saved)
        game.automaticServing = false
        game.musicEnabled = false; game.soundEnabled = false
        game.racketKind = .coral
        if withRobot { ClubScene.robot(game.assets) }
        game.assets.root.addChild(game.assets.milo)
        game.assets.milo.scale = [1.35, 1.35, 1.35]
        game.assets.root.addChild(game.assets.racket)
        game.assets.root.addChild(game.assets.shuttle)
        game.restart()
        return game
    }

    private func wrist(at position: V3 = [2, 1.2, -0.25], angle: Float = 0.4) -> simd_float4x4 {
        var pose = simd_float4x4(simd_quatf(angle: angle, axis: simd_normalize(V3(1, 2, 3))))
        pose.columns.3 = SIMD4(position, 1)
        return pose
    }

    /// Finger pairs share the wrist's world frame. Scaling a local tip along
    /// its knuckle ray produces a known, hand-size-independent measured curl.
    private func sample(_ game: GameModel, wrist pose: simd_float4x4,
                        curl: Float? = 1.1, jointsTracked: Bool = true,littleTracked:Bool = true,
                        wristTracked: Bool = true, timestamp: Double, now: Double? = nil) {
        let local: [V3] = [[0.035, 0.08, 0], [0, 0.09, 0], [-0.035, 0.065, 0]]
        func world(_ point: V3) -> V3 { (pose * SIMD4<Float>(point, 1)).xyz }
        let fingers: [(knuckle: V3, tip: V3)] = curl.map { value in
            local.map { (knuckle: world($0), tip: world($0 * value)) }
        } ?? []
        game.receiveHandInput(worldFromWrist: pose, wristTracked: wristTracked,
            indexKnuckle: .init(position: world(local[0]), isTracked: jointsTracked),
            middleKnuckle: .init(position: world(local[1]), isTracked: jointsTracked),
            littleKnuckle: .init(position: world(local[2]), isTracked: jointsTracked && littleTracked),
            trackedFingers: littleTracked ? fingers:Array(fingers.prefix(2)), timestamp: timestamp, now: now ?? timestamp)
    }

    /// Simulate acquisition history, then render its final, fresh measured
    /// sample. No wall-clock sleeps or future readiness samples are needed.
    private func grab(_ game: GameModel, wrist pose: simd_float4x4) throws {
        let start = CACurrentMediaTime() - 0.24
        for index in 0...5 { sample(game, wrist: pose, curl: 1.9, timestamp: start + Double(index) * 0.02) }
        for index in 0...5 { sample(game, wrist: pose, timestamp: start + 0.12 + Double(index) * 0.02) }
        try #require(game.handRacketHeld)
        game.update(1 / 90)
        try #require(game.racketReady)
    }

    private func beginIncoming(_ game: GameModel, wrist pose: simd_float4x4) throws {
        sample(game, wrist: pose, timestamp: CACurrentMediaTime())
        game.serve()
        try #require(game.isPreparingServe)
        for _ in 0..<100 {
            guard game.isPreparingServe else { break }
            sample(game, wrist: pose, timestamp: CACurrentMediaTime())
            game.update(1 / 120)
        }
        try #require(game.shuttleState != nil)
    }

    private func displayed(_ game: GameModel) -> simd_float4x4 {
        game.assets.racket.transformMatrix(relativeTo: game.assets.root)
    }

    private func expectPose(_ actual: simd_float4x4, _ expected: simd_float4x4) {
        for column in 0..<4 { #expect(simd_distance(actual[column], expected[column]) < 0.0001) }
    }

    private func sameFit(_ a: HandGripFit, _ b: HandGripFit) -> Bool {
        abs(simd_dot(a.normalized().calibratedOrientation, b.normalized().calibratedOrientation)) > 0.99999
    }

    @Test func anInitiallyClosedHandCannotAcquireServeOrCalibrate() throws {
        let (saved, name) = try defaults(); defer { saved.removePersistentDomain(forName: name) }
        let game = fixture(saved), pose = wrist()
        let start = CACurrentMediaTime() - 0.16
        for index in 0...7 { sample(game, wrist: pose, timestamp: start + Double(index) * 0.02) }
        game.update(1 / 90)
        #expect(game.handVisible)
        #expect(!game.handRacketHeld && !game.racketReady)
        #expect(!game.canAdjustHandGrip && game.handHeadVelocity == .zero)
        game.setGrip(); game.serve()
        #expect(game.handGripFit == HandGripFit())
        #expect(game.canServe && !game.isPreparingServe && game.shuttleState == nil)
        #expect(game.lastContact == nil)
    }

    @Test func anOpenThenClosedDwellAcquiresTheMeasuredRacketAndAllowsServe() throws {
        let (saved, name) = try defaults(); defer { saved.removePersistentDomain(forName: name) }
        let game = fixture(saved, withRobot: true), pose = wrist()
        let start = CACurrentMediaTime() - 0.24
        for index in 0...5 {
            sample(game, wrist: pose, curl: 1.9, timestamp: start + Double(index) * 0.02)
            #expect(!game.handRacketHeld)
        }
        for index in 0..<5 {
            sample(game, wrist: pose, timestamp: start + 0.12 + Double(index) * 0.02)
            #expect(!game.handRacketHeld)
        }
        sample(game, wrist: pose, timestamp: start + 0.22)
        game.update(1 / 90)
        #expect(game.handRacketHeld && game.racketReady && game.canAdjustHandGrip)
        #expect(game.assets.racket.isEnabled && game.handHeadVelocity == .zero)
        sample(game, wrist: pose, timestamp: CACurrentMediaTime())
        game.serve()
        #expect(game.isPreparingServe && !game.canServe)
        #expect(game.serveCountdown == 0.65 && game.shuttleState == nil)
        #expect(game.lastContact == nil && game.rallyHits == 0)
    }

    @Test func relaxedAndMissingFingersRetainTheLockedMountWhileTheWristMoves() throws {
        let (saved, name) = try defaults(); defer { saved.removePersistentDomain(forName: name) }
        let game = fixture(saved), initial = wrist()
        try grab(game, wrist: initial)
        let mount = simd_inverse(initial) * displayed(game)
        let time = CACurrentMediaTime()
        let relaxed = wrist(at: [2.03, 1.21, -0.25], angle: 0.7)
        sample(game, wrist: relaxed, curl: 1.45, timestamp: time)
        game.update(1 / 90)
        #expect(game.handRacketHeld && game.racketReady)
        expectPose(displayed(game), relaxed * mount)
        let missing = wrist(at: [2.04, 1.22, -0.25], angle: 0.8)
        sample(game, wrist: missing, curl: nil, jointsTracked: false, timestamp: time + 1 / 60)
        game.update(1 / 90)
        #expect(game.handRacketHeld && game.racketReady)
        expectPose(displayed(game), missing * mount)
        #expect(simd_distance(displayed(game).columns.3.xyz, (relaxed * mount).columns.3.xyz) > 0.005)
    }

    @Test func wristLossBetweenRenderFramesPausesAndRecoveryIsOnlyABaseline() throws {
        let (saved,name)=try defaults();defer { saved.removePersistentDomain(forName:name) }
        let game=fixture(saved,withRobot:true),pose=wrist()
        try grab(game,wrist:pose);try beginIncoming(game,wrist:pose)
        let frozen=try #require(game.shuttleState),time=CACurrentMediaTime()
        sample(game,wrist:pose,wristTracked:false,timestamp:time)
        #expect(game.paused && !game.racketReady && !game.assets.racket.isEnabled)
        var recovered=pose;recovered.columns.3.x += 0.04
        sample(game,wrist:recovered,curl:nil,jointsTracked:false,timestamp:time+1/60)
        game.update(1/90)
        #expect(game.handRacketHeld && game.racketReady && game.paused)
        #expect(game.handHeadVelocity == .zero)
        #expect(game.shuttleState?.position == frozen.position && game.shuttleState?.velocity == frozen.velocity)
        #expect(game.lastContact == nil && game.rallyHits == 0)
    }

    @Test func sustainedOpenReleasePausesAFlightAndCannotCreateAContact() throws {
        let (saved, name) = try defaults(); defer { saved.removePersistentDomain(forName: name) }
        let game = fixture(saved, withRobot: true), pose = wrist()
        try grab(game, wrist: pose); try beginIncoming(game, wrist: pose)
        let before = try #require(game.shuttleState)
        #expect(!game.paused)
        let start = CACurrentMediaTime()
        for index in 0..<15 {
            sample(game, wrist: pose, curl: 1.9, timestamp: start + Double(index) * 0.02)
            #expect(game.handRacketHeld && !game.paused)
        }
        sample(game, wrist: pose, curl: 1.9, timestamp: start + 0.30)
        // No render update occurred during the dwell: the release itself
        // pauses the live rally, rather than an unrelated render freshness gate.
        #expect(!game.handRacketHeld && !game.racketReady && game.paused)
        #expect(game.handHeadVelocity == .zero)
        game.update(1 / 90); game.serve()
        #expect(game.shuttleState?.position == before.position)
        #expect(game.shuttleState?.velocity == before.velocity)
        #expect(game.lastContact == nil && game.rallyHits == 0)
        #expect(game.paused)
    }

    @Test func anchorVelocityUsesSixtyHertzSampleTimeAndRepeatedRenderFramesAreStill() throws {
        let (saved, name) = try defaults(); defer { saved.removePersistentDomain(forName: name) }
        let game = fixture(saved), initial = wrist()
        try grab(game, wrist: initial)
        let time = CACurrentMediaTime()
        sample(game, wrist: initial, timestamp: time); game.update(1 / 90)
        #expect(game.handHeadVelocity == .zero)
        var moved = initial; moved.columns.3.x += 0.03
        sample(game, wrist: moved, timestamp: time + 1 / 60); game.update(1 / 90)
        let expected = V3(0.03 / Float(1 / 60.0), 0, 0)
        #expect(simd_distance(game.handHeadVelocity, expected) < 0.001)
        #expect(abs(game.handHeadVelocity.x - 0.03 / Float(1 / 90.0)) > 0.8)
        let heldPose = displayed(game)
        game.update(1 / 90)
        #expect(game.handHeadVelocity == .zero)
        expectPose(displayed(game), heldPose)
        sample(game, wrist: moved, timestamp: time + 1 / 60); game.update(1 / 90)
        #expect(game.handHeadVelocity == .zero && game.handRacketHeld)
        #expect(game.lastContact == nil)
    }

    @Test func staleOrUnheldSamplesCannotReplaceASavedHandFit() throws {
        let (saved, name) = try defaults(); defer { saved.removePersistentDomain(forName: name) }
        let original = HandGripFit(calibratedOrientation: simd_quatf(angle: 0.6, axis: [1, 0, 0]).vector)
        #expect(HandGripFitStore.save(original, left: false, defaults: saved))
        let game = fixture(saved), pose = wrist()
        sample(game, wrist: pose, curl: 1.9, timestamp: CACurrentMediaTime()); game.update(1 / 90)
        #expect(!game.handRacketHeld && !game.canAdjustHandGrip)
        game.setGrip(); #expect(sameFit(game.handGripFit, original))
        game.reconfigureTracking()
        // Acquired input can be genuine yet too old to calibrate. Replay that
        // history in acquisition time, then evaluate readiness in current time.
        let start = CACurrentMediaTime() - 1.24
        for index in 0...5 { sample(game, wrist: pose, curl: 1.9, timestamp: start + Double(index) * 0.02) }
        for index in 0...5 { sample(game, wrist: pose, timestamp: start + 0.12 + Double(index) * 0.02) }
        #expect(game.handRacketHeld && !game.racketReady && !game.canAdjustHandGrip)
        game.setGrip(); game.serve(); game.update(1 / 90)
        #expect(sameFit(game.handGripFit, original))
        #expect(sameFit(HandGripFitStore.load(left: false, defaults: saved), original))
        #expect(!game.isPreparingServe && game.shuttleState == nil && game.handHeadVelocity == .zero)
    }

    @Test func duplicatedOrReorderedInputCannotTeleportTheHeldRacketOrInventSpeed() throws {
        let (saved, name) = try defaults(); defer { saved.removePersistentDomain(forName: name) }
        let game = fixture(saved), initial = wrist()
        try grab(game, wrist: initial)
        let time = CACurrentMediaTime()
        sample(game, wrist: initial, timestamp: time); game.update(1 / 90)
        let before = displayed(game)
        let other = wrist(at: [-1, 2, -3], angle: 1.4)
        sample(game, wrist: other, curl: 1.9, timestamp: time)
        game.update(1 / 90)
        expectPose(displayed(game), before)
        #expect(game.handRacketHeld && game.handHeadVelocity == .zero)
        sample(game, wrist: other, curl: 1.9, timestamp: time - 0.01)
        game.update(1 / 90)
        expectPose(displayed(game), before)
        #expect(game.handRacketHeld && game.handHeadVelocity == .zero)
        sample(game, wrist: initial, timestamp: time + 1 / 60); game.update(1 / 90)
        expectPose(displayed(game), before)
        #expect(game.handRacketHeld && game.racketReady && game.handHeadVelocity == .zero)
        #expect(game.lastContact == nil && game.rallyHits == 0)
    }

    @Test func pausedAlignmentPreservesTheHandleFreezesFlightAndClearsSwingHistory() throws {
        let (saved, name) = try defaults(); defer { saved.removePersistentDomain(forName: name) }
        let game = fixture(saved, withRobot: true), pose = wrist(angle: 0.9)
        game.assets.root.transform = Transform(scale: [1, 1, 1],
            rotation: simd_quatf(angle: 0.6, axis: [0, 1, 0]), translation: [0.8, 0, -1.1])
        try grab(game, wrist: pose); try beginIncoming(game, wrist: pose)
        #expect(!game.canAdjustHandGrip)
        let beforeActiveAdjustment = displayed(game)
        game.setGrip()
        #expect(game.handGripFit == HandGripFit())
        expectPose(displayed(game), beforeActiveAdjustment)
        game.paused = true
        let time = CACurrentMediaTime()
        sample(game, wrist: pose, timestamp: time); game.update(1 / 90)
        var moved = pose; moved.columns.3.x += 0.02
        sample(game, wrist: moved, timestamp: time + 1 / 60); game.update(1 / 90)
        #expect(game.canAdjustHandGrip && simd_length(game.handHeadVelocity) > 1)
        let handle = displayed(game).columns.3.xyz
        let frozen = try #require(game.shuttleState)
        game.setGrip()
        let aligned = displayed(game), fitted = game.handGripFit
        #expect(simd_distance(aligned.columns.3.xyz, handle) < 0.0001)
        #expect(simd_distance(aligned.columns.1.xyz, V3(0, 1, 0)) < 0.0001)
        #expect(simd_distance(aligned.columns.2.xyz, V3(0, 0, 1)) < 0.0001)
        #expect(game.handHeadVelocity == .zero && !sameFit(fitted, HandGripFit()))
        sample(game, wrist: moved, timestamp: time + 1 / 60 + 0.002); game.update(1 / 90)
        #expect(game.handHeadVelocity == .zero)
        expectPose(displayed(game), aligned)
        #expect(game.paused && game.shuttleState?.position == frozen.position)
        #expect(game.shuttleState?.velocity == frozen.velocity)
        #expect(game.lastContact == nil && game.rallyHits == 0)
        let reloaded = GameModel(gripDefaults: saved)
        #expect(sameFit(reloaded.handGripFit, fitted))
        #expect(!reloaded.handRacketHeld && !reloaded.racketReady)
    }

    @Test func inputAndHandPreferencesReloadSeparateFitsWithoutRevivingOldSamples() throws {
        let (saved, name) = try defaults(); defer { saved.removePersistentDomain(forName: name) }
        let game = fixture(saved)
        try grab(game, wrist: wrist(angle: 0.5)); game.setGrip()
        let right = game.handGripFit
        game.leftHand = true
        #expect(!game.racketReady && !game.canAdjustHandGrip)
        game.setGrip(); #expect(game.handGripFit == HandGripFit())
        game.reconfigureTracking()
        #expect(!game.handRacketHeld && !game.racketReady && !game.assets.racket.isEnabled)
        #expect(game.handHeadVelocity == .zero && game.handGripFit == HandGripFit())
        try grab(game, wrist: wrist(angle: -0.8)); game.setGrip()
        let left = game.handGripFit
        #expect(!sameFit(left, right))
        game.input = .sense; game.reconfigureTracking()
        #expect(!game.handRacketHeld && !game.racketReady && !game.canAdjustHandGrip)
        let reloaded = fixture(saved)
        #expect(reloaded.input == .sense && reloaded.leftHand)
        #expect(sameFit(reloaded.handGripFit, left))
        #expect(!reloaded.handVisible && !reloaded.handRacketHeld && !reloaded.racketReady)
        reloaded.input = .hands; reloaded.reconfigureTracking()
        let start = CACurrentMediaTime() - 0.12
        for index in 0...5 {
            sample(reloaded, wrist: wrist(angle: -0.8), timestamp: start + Double(index) * 0.02)
        }
        reloaded.update(1 / 90); reloaded.serve()
        #expect(!reloaded.handRacketHeld && !reloaded.racketReady && !reloaded.isPreparingServe)
        reloaded.leftHand = false; reloaded.reconfigureTracking()
        #expect(sameFit(reloaded.handGripFit, right))
        #expect(!reloaded.handRacketHeld && reloaded.handHeadVelocity == .zero)
        let afterHandChange = GameModel(gripDefaults: saved)
        #expect(afterHandChange.input == .hands && !afterHandChange.leftHand)
        #expect(sameFit(afterHandChange.handGripFit, right))
        #expect(afterHandChange.lastContact == nil && !afterHandChange.racketReady)
    }

    @Test func missingInitialLittleKnuckleCannotArmGrabAndExplainsPalmRecovery() throws {
        let (saved,name)=try defaults();defer { saved.removePersistentDomain(forName:name) }
        let game=fixture(saved),pose=wrist(),start=CACurrentMediaTime()-0.24
        for i in 0...5 { sample(game,wrist:pose,curl:1.9,littleTracked:false,timestamp:start+Double(i)*0.02) }
        for i in 0...5 { sample(game,wrist:pose,littleTracked:false,timestamp:start+0.12+Double(i)*0.02) }
        #expect(!game.handRacketHeld && !game.handAcquisitionReady && !game.racketReady)
        #expect(game.trackingMessage.contains("palm"))
        game.reconfigureTracking();try grab(game,wrist:pose)
        #expect(game.handRacketHeld && game.racketReady)
    }

    @Test func backgroundOpenCloseCannotAcquireAndForegroundRequiresNewOpen() throws {
        let (saved,name)=try defaults();defer { saved.removePersistentDomain(forName:name) }
        let game=fixture(saved),pose=wrist(),start=CACurrentMediaTime()-0.6
        for i in 0...5 { sample(game,wrist:pose,curl:1.9,timestamp:start+Double(i)*0.02) }
        game.sceneActivityChanged(active:false)
        for i in 0...10 { sample(game,wrist:pose,timestamp:start+0.12+Double(i)*0.02) }
        #expect(!game.handVisible && !game.handRacketHeld && !game.racketReady)
        game.sceneActivityChanged(active:true)
        for i in 0...5 { sample(game,wrist:pose,timestamp:start+0.36+Double(i)*0.02) }
        #expect(!game.handRacketHeld && !game.racketReady)
        game.reconfigureTracking();try grab(game,wrist:pose)
        #expect(game.racketReady)
    }

    @Test func backgroundPreservesLockedMountButCannotReleaseOrResumeWithoutFreshHand() throws {
        let (saved,name)=try defaults();defer { saved.removePersistentDomain(forName:name) }
        let game=fixture(saved,withRobot:true),pose=wrist()
        try grab(game,wrist:pose);try beginIncoming(game,wrist:pose)
        let mount=displayed(game),flight=try #require(game.shuttleState)
        let start=CACurrentMediaTime()
        game.sceneActivityChanged(active:false)
        for i in 0...20 { sample(game,wrist:pose,curl:1.9,timestamp:start+Double(i)*0.02) }
        game.sceneActivityChanged(active:true);game.handleControllerMenu()
        #expect(game.paused && !game.racketReady)
        sample(game,wrist:pose,timestamp:CACurrentMediaTime());game.update(1/90)
        #expect(game.handRacketHeld && game.racketReady && game.handHeadVelocity == .zero)
        expectPose(displayed(game),mount)
        #expect(game.shuttleState?.position == flight.position && game.lastContact == nil)
        game.handleControllerMenu();#expect(!game.paused)
    }

    @Test func expiredHandShowsRecoveryMessageAndResetFitPreservesPalmAndOtherHand() throws {
        let (saved,name)=try defaults();defer { saved.removePersistentDomain(forName:name) }
        let other=HandGripFit(calibratedOrientation:simd_quatf(angle:0.4,axis:[0,1,0]).vector)
        #expect(HandGripFitStore.save(other,left:true,defaults:saved))
        let game=fixture(saved),pose=wrist(angle:0.9)
        try grab(game,wrist:pose);game.setGrip()
        #expect(!sameFit(game.handGripFit,HandGripFit()))
        let handle=displayed(game).columns.3.xyz
        game.resetHandGrip()
        #expect(sameFit(game.handGripFit,HandGripFit()))
        #expect(simd_distance(displayed(game).columns.3.xyz,handle)<0.0001 && game.handHeadVelocity == .zero)
        #expect(sameFit(HandGripFitStore.load(left:true,defaults:saved),other))
        game.reconfigureTracking()
        let stale=CACurrentMediaTime()-1.24
        for i in 0...5 { sample(game,wrist:pose,curl:1.9,timestamp:stale+Double(i)*0.02) }
        for i in 0...5 { sample(game,wrist:pose,timestamp:stale+0.12+Double(i)*0.02) }
        game.update(1/90)
        #expect(!game.racketReady && game.trackingMessage.contains("tracking lost"))
        #expect(!game.trackingMessage.contains("Racket held."))
    }
    @Test func noHandSamplesCannotOverwritePermissionOrProviderFailureFeedback() throws {
        let (saved,name)=try defaults();defer { saved.removePersistentDomain(forName:name) }
        let game=fixture(saved)
        game.trackingMessage="Allow hand tracking in Settings, then choose Retry tracking."
        game.update(1/90)
        #expect(game.trackingMessage == "Allow hand tracking in Settings, then choose Retry tracking.")
        #expect(!game.racketReady && !game.handGripLocked)
    }
}
