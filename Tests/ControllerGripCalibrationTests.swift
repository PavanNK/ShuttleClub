import Foundation
import Testing
import QuartzCore
import RealityKit
import simd
import ShuttleCore
@testable import ShuttleClub

@MainActor @Suite(.serialized)
struct ControllerGripCalibrationTests {
    func fixture(defaults:UserDefaults) -> GameModel {
        let game=GameModel(gripDefaults:defaults)
        game.automaticServing=false;game.input = .sense;game.leftHand=false
        game.musicEnabled=false;game.soundEnabled=false
        game.assets.root.addChild(game.assets.racket)
        game.restart()
        return game
    }
    func grip(at position:V3=[0.25,1.2,-0.4],angle:Float=0.4) -> simd_float4x4 {
        var pose=simd_float4x4(simd_quatf(angle:angle,axis:simd_normalize(V3(1,2,3))))
        pose.columns.3=SIMD4(position,1)
        return pose
    }
    func sample(_ game:GameModel,grip pose:simd_float4x4?=nil,
                timestamp:Double=CACurrentMediaTime(),left:Bool?=nil,velocity:V3 = .zero) -> SenseControllers.Pose {
        let measuredGrip=pose ?? grip()
        let mounted=game.controllerGripFit.mountedPose(fromGrip:measuredGrip)
        var prediction=mounted;prediction.columns.3.x += 0.25
        return .init(originFromGrip:measuredGrip,leftHand:left ?? game.leftHand,measured:mounted,
                     rendered:prediction,headVelocity:velocity,timestamp:timestamp)
    }
    func expectPose(_ actual:simd_float4x4,_ expected:simd_float4x4) {
        for column in 0..<4 { #expect(simd_distance(actual[column],expected[column])<0.0001) }
    }
    func defaults() throws -> (UserDefaults,String) {
        let name="ShuttleClub.ControllerGripTests.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName:name)),name)
    }
    @Test func liveFitMovesMeasuredDisplayHandleAndHeadAndReloads() throws {
        let (saved,name)=try defaults();defer { saved.removePersistentDomain(forName:name) }
        let game=fixture(defaults:saved)
        game.assets.root.transform=Transform(scale:[1,1,1],rotation:simd_quatf(angle:0.55,axis:[0,1,0]),translation:[0.8,0,-1.1])
        let source=grip();let polled=sample(game,grip:source)
        game.receiveControllerPose(polled)
        #expect(game.canAdjustControllerGrip);#expect(game.assets.racket.isEnabled)
        let old=game.assets.racket.transformMatrix(relativeTo:game.assets.root)
        expectPose(old,simd_inverse(game.assets.root.transformMatrix(relativeTo:nil))*polled.measured)
        let fit=SenseGripFit(translation:[0.025,-0.03,0.015],pitchDegrees:18,yawDegrees:-12,rollDegrees:9)
        game.setControllerGripFit(fit)
        let expected=simd_inverse(game.assets.root.transformMatrix(relativeTo:nil))*fit.mountedPose(fromGrip:source)
        let displayed=game.assets.racket.transformMatrix(relativeTo:game.assets.root)
        expectPose(displayed,expected)
        #expect(simd_distance(old.columns.3.xyz,displayed.columns.3.xyz)>0.02)
        #expect(simd_distance((old*SIMD4<Float>(0,0.37,0,1)).xyz,(displayed*SIMD4<Float>(0,0.37,0,1)).xyz)>0.05)
        let reloaded=fixture(defaults:saved)
        #expect(reloaded.controllerGripFit == fit.normalized())
        game.receiveControllerPose(sample(game,grip:source))
        expectPose(game.assets.racket.transformMatrix(relativeTo:game.assets.root),expected)
        #expect(game.lastContact == nil);#expect(game.rallyHits == 0)
    }
    @Test func fitsAreSavedAndResetSeparatelyForEachControllerHand() throws {
        let (saved,name)=try defaults();defer { saved.removePersistentDomain(forName:name) }
        let game=fixture(defaults:saved)
        let right=SenseGripFit(translation:[0.02,0.01,-0.03],pitchDegrees:24,rollDegrees:-8)
        let left=SenseGripFit(translation:[-0.03,0.015,0.01],yawDegrees:-31,rollDegrees:15)
        game.receiveControllerPose(sample(game));game.setControllerGripFit(right)
        game.leftHand=true;game.reconfigureTracking()
        #expect(!game.controllerReady);#expect(!game.canAdjustControllerGrip)
        #expect(game.controllerGripFit == SenseGripFit())
        game.receiveControllerPose(sample(game));game.setControllerGripFit(left)
        let reloaded=fixture(defaults:saved)
        #expect(reloaded.controllerGripFit == right.normalized())
        reloaded.leftHand=true;#expect(reloaded.controllerGripFit == left.normalized())
        reloaded.receiveControllerPose(sample(reloaded));reloaded.resetControllerGrip()
        #expect(reloaded.controllerGripFit == SenseGripFit())
        reloaded.leftHand=false;#expect(reloaded.controllerGripFit == right.normalized())
        let afterReset=fixture(defaults:saved)
        #expect(afterReset.controllerGripFit == right.normalized())
        afterReset.leftHand=true;#expect(afterReset.controllerGripFit == SenseGripFit())
    }
    enum InvalidSample:CaseIterable { case untracked,stale,wrongHand,invalidVelocity,invalidMatrix,singularMatrix }
    @Test(arguments:InvalidSample.allCases)
    func rejectedSamplesCannotAdjustOrResetFit(reason:InvalidSample) throws {
        let (saved,name)=try defaults();defer { saved.removePersistentDomain(forName:name) }
        let game=fixture(defaults:saved)
        let chosen=SenseGripFit(translation:[0.02,0.01,0],pitchDegrees:16)
        game.receiveControllerPose(sample(game));game.setControllerGripFit(chosen)
        switch reason {
        case .untracked:game.receiveControllerPose(nil)
        case .stale:game.receiveControllerPose(sample(game,timestamp:CACurrentMediaTime()-1))
        case .wrongHand:game.receiveControllerPose(sample(game,left:true))
        case .invalidVelocity:game.receiveControllerPose(sample(game,velocity:[.nan,0,0]))
        case .invalidMatrix:
            var invalid=grip();invalid.columns.3.x = .nan
            game.receiveControllerPose(sample(game,grip:invalid))
        case .singularMatrix:
            var invalid=grip();invalid.columns.0 = .zero
            game.receiveControllerPose(sample(game,grip:invalid))
        }
        #expect(!game.controllerReady);#expect(!game.canAdjustControllerGrip)
        #expect(!game.assets.racket.isEnabled)
        game.setControllerGripFit(.init(translation:[-0.04,0,0]));game.resetControllerGrip();game.setGrip()
        #expect(game.controllerGripFit == chosen.normalized())
        #expect(fixture(defaults:saved).controllerGripFit == chosen.normalized())
    }
    @Test func inputHandAndBackgroundChangesRequireASelectedFreshGrip() throws {
        let (saved,name)=try defaults();defer { saved.removePersistentDomain(forName:name) }
        let game=fixture(defaults:saved)
        game.receiveControllerPose(sample(game));#expect(game.canAdjustControllerGrip)
        game.sceneActivityChanged(active:false)
        game.setControllerGripFit(.init(pitchDegrees:30));#expect(game.controllerGripFit == SenseGripFit())
        #expect(!game.canAdjustControllerGrip)
        game.sceneActivityChanged(active:true);game.receiveControllerPose(sample(game))
        game.input = .hands;game.reconfigureTracking()
        #expect(!game.controllerReady);#expect(!game.canAdjustControllerGrip)
        game.setControllerGripFit(.init(yawDegrees:30));#expect(game.controllerGripFit == SenseGripFit())
        game.input = .sense;game.reconfigureTracking()
        #expect(!game.canAdjustControllerGrip)
        game.receiveControllerPose(sample(game));#expect(game.canAdjustControllerGrip)
        game.leftHand=true
        #expect(!game.canAdjustControllerGrip)
        game.setControllerGripFit(.init(rollDegrees:30));#expect(game.controllerGripFit == SenseGripFit())
        game.reconfigureTracking();#expect(!game.controllerReady)
        game.receiveControllerPose(sample(game));#expect(game.canAdjustControllerGrip)
    }
    @Test func alignAngleUsesCourtOrientationAndPreservesTheFittedHandlePosition() throws {
        let (saved,name)=try defaults();defer { saved.removePersistentDomain(forName:name) }
        let game=fixture(defaults:saved)
        game.assets.root.transform=Transform(scale:[1,1,1],rotation:simd_quatf(angle:0.7,axis:[0,1,0]),translation:[0.8,0,-1.2])
        let source=grip(at:[0.4,1.35,-0.4],angle:1.1)
        game.receiveControllerPose(sample(game,grip:source))
        game.setControllerGripFit(.init(translation:[0.03,-0.02,0.015],pitchDegrees:15,yawDegrees:-20,rollDegrees:12))
        let before=game.assets.racket.transformMatrix(relativeTo:game.assets.root).columns.3.xyz
        game.setGrip()
        let fitted=game.assets.racket.transformMatrix(relativeTo:game.assets.root)
        let desired=simd_quatf(angle:0,axis:[0,0,1])
        #expect(simd_distance(fitted.columns.3.xyz,before)<0.0001)
        #expect(simd_distance(fitted.columns.1.xyz,desired.act(V3(0,1,0)))<0.0001)
        #expect(simd_distance(fitted.columns.2.xyz,desired.act(V3(0,0,1)))<0.0001)
        #expect(game.controllerGripFit.pitchDegrees == 0)
        #expect(game.controllerGripFit.yawDegrees == 0)
        #expect(game.controllerGripFit.rollDegrees == 0)
        game.receiveControllerPose(sample(game,grip:source))
        expectPose(game.assets.racket.transformMatrix(relativeTo:game.assets.root),fitted)
        #expect(game.lastContact == nil);#expect(game.rallyHits == 0)
    }
    @Test func activeRallyRejectsFitAndPausedFitKeepsFlightFrozenAndDisarmsContact() throws {
        let (saved,name)=try defaults();defer { saved.removePersistentDomain(forName:name) }
        let game=fixture(defaults:saved)
        ClubScene.robot(game.assets);game.assets.root.addChild(game.assets.milo)
        game.assets.milo.scale=[1.35,1.35,1.35];game.assets.root.addChild(game.assets.shuttle)
        // Begin a real native serve through the existing measured hand-input
        // fixture, then change to the controller's real poll commit path.
        game.input = .hands;game.reconfigureTracking()
        var hand=matrix_identity_float4x4;hand.columns.3=SIMD4<Float>(2,1.23,-0.25,1)
        game.receiveHandPose(hand);game.serve()
        for _ in 0..<100 {
            guard game.isPreparingServe else { break }
            game.receiveHandPose(hand);game.update(1/120)
        }
        let initialFlight=try #require(game.shuttleState)
        game.input = .sense;game.reconfigureTracking()
        #expect(game.paused)
        game.receiveControllerPose(sample(game));game.paused=false
        #expect(!game.canAdjustControllerGrip)
        let before=game.assets.racket.transformMatrix(relativeTo:game.assets.root)
        game.setControllerGripFit(.init(translation:[0.05,0,0],pitchDegrees:50))
        #expect(game.controllerGripFit == SenseGripFit())
        expectPose(game.assets.racket.transformMatrix(relativeTo:game.assets.root),before)
        game.paused=true;#expect(game.canAdjustControllerGrip)
        let fit=SenseGripFit(translation:[0.05,0.03,0],pitchDegrees:55,yawDegrees:-35)
        game.setControllerGripFit(fit)
        #expect(game.controllerGripFit == fit.normalized())
        #expect(!game.controllerContactReady);#expect(game.controllerHeadVelocity == .zero)
        game.receiveControllerPose(sample(game,velocity:[0,8,-10]))
        // A new poll following refit establishes a baseline even if the SDK
        // reports motion; this sample cannot reach the collision branch.
        #expect(game.controllerReady);#expect(!game.controllerContactReady)
        #expect(game.shuttleState?.position == initialFlight.position)
        #expect(game.shuttleState?.velocity == initialFlight.velocity)
        #expect(game.lastContact == nil);#expect(game.rallyHits == 0)
        game.update(0.03)
        #expect(game.paused);#expect(game.shuttleState?.position == initialFlight.position)
        #expect(game.lastContact == nil)
    }
    @Test func idleRefitClearsSwingHistoryAndNextControllerSampleIsOnlyABaseline() throws {
        let (saved,name)=try defaults();defer { saved.removePersistentDomain(forName:name) }
        let game=fixture(defaults:saved)
        let now=CACurrentMediaTime()
        game.receiveControllerPose(sample(game,timestamp:now-0.02,velocity:[0,4,-6]))
        game.receiveControllerPose(sample(game,timestamp:now-0.01,velocity:[0,4,-6]))
        #expect(game.controllerContactReady);#expect(simd_length(game.controllerHeadVelocity)>7)
        game.setControllerGripFit(.init(translation:[0.04,0.03,0],pitchDegrees:65))
        #expect(!game.controllerContactReady);#expect(game.controllerHeadVelocity == .zero)
        game.receiveControllerPose(sample(game,timestamp:now,velocity:[0,4,-6]))
        #expect(game.controllerReady);#expect(!game.controllerContactReady)
        #expect(game.lastContact == nil);#expect(game.rallyHits == 0)
        game.receiveControllerPose(sample(game,timestamp:now+0.005))
        #expect(game.controllerContactReady);#expect(game.controllerHeadVelocity == .zero)
        #expect(game.canServe);#expect(!game.rallyInProgress)
    }
}
