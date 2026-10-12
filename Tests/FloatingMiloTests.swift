import Testing
import RealityKit
import simd
import ShuttleCore
@testable import ShuttleClub

@MainActor @Suite struct FloatingMiloTests {
    private func rig()->SceneAssets {
        let assets=SceneAssets()
        assets.root.addChild(assets.milo)
        ClubScene.robot(assets)
        assets.milo.position=[0.4,0,-8]
        assets.milo.scale=[1.35,1.35,1.35]
        return assets
    }
    private func expectPose(_ actual:simd_float4x4,_ expected:simd_float4x4) {
        for column in 0..<4 { #expect(simd_distance(actual[column],expected[column])<0.00001) }
    }

    @Test func floatingCharacterHasNoGroundContactRigAndHasAnElevatedEngine() {
        let assets=rig()
        #expect(assets.robotLegs.isEmpty && assets.robotFeet.isEmpty && assets.robotLegRestPositions.isEmpty)
        #expect(assets.robotBody.children.count == 4)
        #expect(assets.robotHoverBase.parent === assets.robotBody)
        #expect(assets.robotHoverGlow.parent === assets.robotHoverBase && assets.robotHoverGlow.children.count == 2)
        let bounds=assets.robotHoverBase.visualBounds(relativeTo:assets.robotBody)
        #expect(bounds.min.y > 0.45 && bounds.max.y < 0.91)
        #expect(bounds.extents.x > 0.3 && bounds.extents.z > 0.2)
    }

    @Test func restHeightsAndTheActualShoulderRacketChainStayUnchanged() {
        let assets=rig()
        #expect(assets.robotBody.parent === assets.milo)
        #expect(assets.robotTorso.parent === assets.robotBody && assets.robotTorso.position == V3(0,0.9,0))
        #expect(assets.robotHead.parent === assets.robotTorso)
        #expect(simd_distance(assets.robotHead.position,V3(0,0.53,0))<0.00001)
        #expect(assets.robotArm.parent === assets.robotBody && assets.robotArm.position == V3(-0.25,1.07,0))
        #expect(assets.robotFreeArm.parent === assets.robotBody && assets.robotFreeArm.position == V3(0.25,1.07,0))
        #expect(assets.robotRacket.parent === assets.robotArm && assets.robotRacket.position == V3(-0.15,-0.27,0.18))
        #expect(assets.robotRacket.children.count == 1)
        #expect(assets.milo.scale == V3(1.35,1.35,1.35))
    }

    @Test func bobBankAndThrustNeverMoveThePhysicalShoulderOrMeasuredStrings() {
        let assets=rig()
        assets.robotBody.orientation=simd_quatf(angle:0.12,axis:[0,1,0])
        assets.robotArm.orientation=simd_quatf(angle:0.6,axis:[1,0,0])
        assets.robotRacket.orientation=simd_quatf(angle:-0.2,axis:[0,0,1])
        let root=assets.milo.transformMatrix(relativeTo:assets.root)
        let body=assets.robotBody.transformMatrix(relativeTo:assets.root)
        let shoulder=assets.robotArm.transformMatrix(relativeTo:assets.root)
        let strings=assets.robotRacket.transformMatrix(relativeTo:assets.root)
        assets.movement=4;assets.robotReaction=1
        var largestBob:Float=0,largestBank:Float=0,largestThrust:Float=0
        let phases:[MiloAnimationPhase]=[.ready,.preparingServe,.anticipating,.striking,.recovering,.celebrating]
        for (index,phase) in phases.enumerated() {
            for frame in 0..<30 {
                assets.animateMilo(time:Float(index*30+frame)/90,active:true,dt:1/90,
                                   phase:phase,lookTarget:[2,1.8,-0.2])
                largestBob=max(largestBob,abs(assets.robotHoverBase.position.y-assets.robotHoverRestPosition.y))
                largestBank=max(largestBank,simd_length(assets.robotTorso.orientation.vector.xyz))
                largestThrust=max(largestThrust,assets.robotHoverGlow.scale.y)
                #expect(simd_distance(assets.robotHoverBase.position,assets.robotHoverRestPosition)<0.04)
                #expect(simd_distance(assets.robotTorso.position,assets.robotTorsoRestPosition)<0.06)
                expectPose(assets.milo.transformMatrix(relativeTo:assets.root),root)
                expectPose(assets.robotBody.transformMatrix(relativeTo:assets.root),body)
                expectPose(assets.robotArm.transformMatrix(relativeTo:assets.root),shoulder)
                expectPose(assets.robotRacket.transformMatrix(relativeTo:assets.root),strings)
            }
        }
        #expect(largestBob > 0.005 && largestBank > 0.02 && largestThrust > 1.2)
    }

    @Test func movingBetweenRalliesStillBanksTheFloatingBody() {
        let assets=rig()
        assets.movement=3.5
        for frame in 0..<60 {
            assets.animateMilo(time:Float(frame)/60,active:false,dt:1/60,phase:.recovering)
        }
        #expect(abs(assets.robotTorso.orientation.vector.x)>0.03)
        #expect(assets.robotHoverGlow.scale.y>1.3)
        #expect(assets.robotArm.position == V3(-0.25,1.07,0))
    }

    @Test func reducedMotionRestoresHoverVisualsWithoutChangingTheRacketPose() {
        let assets=rig()
        assets.movement=4
        let strings=assets.robotRacket.transformMatrix(relativeTo:assets.root)
        for frame in 0..<30 { assets.animateMilo(time:Float(frame)/60,active:true,dt:1/60,phase:.anticipating) }
        assets.animateMilo(time:1,active:true,dt:1/60,reducedMotion:true,phase:.striking)
        #expect(assets.robotTorso.position == assets.robotTorsoRestPosition)
        #expect(assets.robotHoverBase.position == assets.robotHoverRestPosition)
        #expect(assets.robotHoverGlow.scale == V3(1,1,1))
        #expect(assets.robotTorso.orientation.vector == SIMD4<Float>(0,0,0,1))
        #expect(assets.robotHoverBase.orientation.vector == SIMD4<Float>(0,0,0,1))
        expectPose(assets.robotRacket.transformMatrix(relativeTo:assets.root),strings)
    }
}
