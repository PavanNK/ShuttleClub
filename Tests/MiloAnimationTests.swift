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
        for side: Float in [-1, 1] {
            let leg = Entity(), foot = Entity()
            leg.position = [side * 0.12, 0.73, 0]
            foot.position = [side * 0.15, -0.7145, 0.12]
            assets.robotBody.addChild(leg)
            leg.addChild(foot)
            assets.robotLegs.append(leg)
            assets.robotLegRestPositions.append(leg.position)
            assets.robotFeet.append(foot)
        }
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

    @Test func walkingFeetStayLevelAndAboveTheirRestingSole() {
        let assets = visualRig()
        assets.movement = 3
        var lifted = false
        for frame in 0..<120 {
            assets.animateMilo(time: Float(frame) / 60, active: true, dt: 1 / 60, phase: .anticipating)
            for foot in assets.robotFeet {
                let pose = foot.transformMatrix(relativeTo: assets.robotBody)
                #expect(pose.columns.3.y >= 0.0155 - 0.00001)
                #expect(pose.columns.3.y <= 0.061)
                #expect(simd_distance(pose.columns.1, SIMD4<Float>(0, 1, 0, 0)) < 0.00001)
                if pose.columns.3.y > 0.03 { lifted = true }
            }
        }
        #expect(lifted)
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

    @Test func recoveringBetweenRalliesStillMovesTheFeet() {
        let assets = visualRig()
        assets.movement = 1.96
        var lifted = false
        for frame in 0..<60 {
            assets.animateMilo(time: Float(frame) / 60, active: false, dt: 1 / 60, phase: .recovering)
            for foot in assets.robotFeet {
                let transform = foot.transformMatrix(relativeTo: assets.robotBody)
                #expect(transform.columns.3.y >= 0.0155 - 0.00001)
                #expect(simd_distance(transform.columns.1, SIMD4<Float>(0, 1, 0, 0)) < 0.00001)
                if transform.columns.3.y > 0.03 { lifted = true }
            }
        }
        #expect(lifted)
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
        for entity in [assets.robotTorso, assets.robotHead, assets.robotFreeArm] + assets.robotLegs + assets.robotFeet {
            #expect(simd_length(entity.orientation.imag) < 0.00001)
            #expect(abs(abs(entity.orientation.real) - 1) < 0.00001)
        }
        for (index, leg) in assets.robotLegs.enumerated() {
            #expect(leg.position == assets.robotLegRestPositions[index])
        }
    }
}
