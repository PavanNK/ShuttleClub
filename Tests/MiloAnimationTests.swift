import Testing
import RealityKit
import simd
@testable import ShuttleClub

@MainActor @Suite
struct MiloAnimationTests {
    func visualRig() -> SceneAssets {
        let assets = SceneAssets()
        assets.root.addChild(assets.milo)
        assets.milo.addChild(assets.robotBody)
        assets.robotBody.addChild(assets.robotTorso)
        assets.robotTorso.position = assets.robotTorsoRestPosition
        assets.robotTorso.addChild(assets.robotHead)
        assets.robotHead.position = [0, 0.53, 0]
        assets.robotHead.addChild(assets.robotFace)
        assets.robotBody.addChild(assets.robotFreeArm)
        assets.robotBody.addChild(assets.robotHoverBase)
        assets.robotHoverBase.position = assets.robotHoverRestPosition
        assets.robotHoverBase.addChild(assets.robotHoverGlow)
        return assets
    }

    @Test func visualAnimationCannotMoveThePhysicalRacketRig() {
        let assets = SceneAssets()
        assets.root.addChild(assets.milo)
        ClubScene.robot(assets)
        assets.milo.position = [0.4, 0, -8]
        assets.robotBody.orientation = simd_quatf(angle: 0.12, axis: [0, 1, 0])
        assets.robotArm.orientation = simd_quatf(angle: 0.6, axis: [1, 0, 0])
        assets.robotRacket.orientation = simd_quatf(angle: -0.2, axis: [0, 0, 1])
        let before = assets.robotRacket.transformMatrix(relativeTo: assets.root)
        assets.movement = 3
        assets.robotReaction = 1
        let phases: [MiloAnimationPhase] = [.ready, .preparingServe, .anticipating, .striking, .recovering, .celebrating]
        for (index, phase) in phases.enumerated() {
            for frame in 0..<20 {
                assets.animateMilo(time: Float(index * 20 + frame) / 60, active: true,
                                   dt: 1 / 60, phase: phase, lookTarget: [1, 1.6, -0.2])
                let after = assets.robotRacket.transformMatrix(relativeTo: assets.root)
                for column in 0..<4 { #expect(simd_distance(before[column], after[column]) < 0.00001) }
            }
        }
        #expect(assets.robotArm.parent === assets.robotBody)
        #expect(assets.robotHead.parent === assets.robotTorso)
    }

    @Test func movingHoverBaseBobsWithinItsVisualEnvelope() {
        let assets = visualRig()
        assets.movement = 3
        var bobbed = false
        for frame in 0..<120 {
            assets.animateMilo(time: Float(frame) / 60, active: true, dt: 1 / 60, phase: .anticipating)
            let distance = simd_distance(assets.robotHoverBase.position, assets.robotHoverRestPosition)
            #expect(distance < 0.04)
            #expect(assets.robotHoverGlow.scale.y > 0 && assets.robotHoverGlow.scale.y < 1.6)
            if distance > 0.005 { bobbed = true }
        }
        #expect(bobbed && assets.robotLegs.isEmpty && assets.robotFeet.isEmpty)
    }

    @Test func reactionsDecayInElapsedTimeAcrossDifferentFrameRates() {
        let slow = visualRig(), fast = visualRig()
        slow.robotReaction = 1
        fast.robotReaction = 1
        for frame in 0..<18 {
            slow.animateMilo(time: Float(frame) / 60, active: false, dt: 1 / 60)
        }
        for frame in 0..<36 {
            fast.animateMilo(time: Float(frame) / 120, active: false, dt: 1 / 120)
        }
        #expect(abs(slow.robotReaction - fast.robotReaction) < 0.00001)
        #expect(abs(slow.robotReaction - 0.49) < 0.00001)
    }

    @Test func recoveringBetweenRalliesStillBanksAndPowersTheHoverEngine() {
        let assets = visualRig()
        assets.movement = 1.96
        var banked = false
        for frame in 0..<60 {
            assets.animateMilo(time: Float(frame) / 60, active: false, dt: 1 / 60, phase: .recovering)
            #expect(simd_distance(assets.robotHoverBase.position, assets.robotHoverRestPosition) < 0.04)
            if abs(assets.robotTorso.orientation.imag.x) > 0.02 { banked = true }
        }
        #expect(banked && assets.robotHoverGlow.scale.y > 1.15)
    }

    @Test func reducedMotionResetsVisualJointsWithoutChangingPhysicalPose() {
        let assets = visualRig()
        assets.movement = 3
        assets.robotReaction = 1
        for frame in 0..<30 {
            assets.animateMilo(time: Float(frame) / 60, active: true, dt: 1 / 60, phase: .striking)
        }
        assets.animateMilo(time: 1, active: true, dt: 1 / 60, reducedMotion: true, phase: .celebrating)
        #expect(assets.robotTorso.position == assets.robotTorsoRestPosition)
        #expect(assets.robotFace.scale == SIMD3<Float>(1, 1, 1))
        #expect(assets.robotHoverBase.position == assets.robotHoverRestPosition)
        #expect(assets.robotHoverGlow.scale == SIMD3<Float>(1, 1, 1))
        for entity in [assets.robotTorso, assets.robotHead, assets.robotFreeArm, assets.robotHoverBase] {
            #expect(simd_length(entity.orientation.imag) < 0.00001)
            #expect(abs(abs(entity.orientation.real) - 1) < 0.00001)
        }
        #expect(assets.robotLegs.isEmpty && assets.robotFeet.isEmpty)
    }
}
