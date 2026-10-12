import Foundation
import Testing
import QuartzCore
import RealityKit
import simd
import ShuttleCore
@testable import ShuttleClub

@MainActor @Suite(.serialized)
struct CourtNavigationTests {
    private func defaults() throws -> (UserDefaults,String) {
        let name="ShuttleClub.CourtNavigationTests.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName:name)),name)
    }
    private func game(_ saved:UserDefaults,input:InputMode = .sense)->GameModel {
        let game=GameModel(gripDefaults:saved)
        game.musicEnabled=false;game.soundEnabled=false;game.automaticServing=false
        game.input=input;game.leftHand=false
        ClubScene.robot(game.assets)
        game.assets.root.addChild(game.assets.milo);game.assets.milo.scale=[1.35,1.35,1.35]
        game.assets.root.addChild(game.assets.racket);game.assets.root.addChild(game.assets.shuttle)
        game.assets.root.addChild(game.assets.interfaceRoot)
        game.restart()
        return game
    }
    private func pose(at position:V3=[0.2,1.2,-0.4])->simd_float4x4 {
        var result=matrix_identity_float4x4;result.columns.3=SIMD4(position,1);return result
    }
    private func packet(_ game:GameModel,timestamp:Double=CACurrentMediaTime(),velocity:V3 = .zero,left:Bool?=nil)->SenseControllers.Pose {
        let grip=pose(),measured=game.controllerGripFit.mountedPose(fromGrip:grip)
        var rendered=measured;rendered.columns.3.x += 0.25
        return .init(originFromGrip:grip,leftHand:left ?? game.leftHand,measured:measured,
                     rendered:rendered,headVelocity:velocity,timestamp:timestamp)
    }
    private func expectPose(_ actual:simd_float4x4,_ expected:simd_float4x4) {
        for column in 0..<4 { #expect(simd_distance(actual[column],expected[column])<0.0001) }
    }

    @Test func stickDeadzoneRejectsJitterAndInvalidAxes() {
        for value:SIMD2<Float> in [.zero,[0.1,-0.1],[0.18,0],[.nan,0.5],[0.5,.infinity]] {
            #expect(CourtNavigation.direction(value) == .zero)
        }
        #expect(abs(CourtNavigation.direction([0.59,0]).x-0.5)<0.0001)
    }

    @Test func forwardStickMapsTowardTheNetAndDiagonalMagnitudeIsBounded() {
        #expect(CourtNavigation.direction([0,1]) == SIMD2<Float>(0,-1))
        #expect(CourtNavigation.direction([1,0]) == SIMD2<Float>(1,0))
        let diagonal=CourtNavigation.direction([1,1])
        #expect(diagonal.x > 0 && diagonal.y < 0 && abs(simd_length(diagonal)-1)<0.0001)
        #expect(simd_distance(CourtNavigation.direction([3,3]),diagonal)<0.0001)
        #expect(CourtNavigation.speed == 1.25)
    }

    @Test(arguments:[Float(1)/30,Float(1)/60,Float(1)/90])
    func accelerationAndDiagonalTravelStayWithinComfortSpeed(dt:Float) {
        var straight=CourtNavigation(),diagonal=CourtNavigation()
        let diagonalDirection=CourtNavigation.direction([1,1])
        for _ in 0..<Int((0.5/dt).rounded()) {
            let beforeStraight=straight.velocity,beforeDiagonal=diagonal.velocity
            straight.step(dt:dt,direction:[1,0],allowed:true)
            diagonal.step(dt:dt,direction:diagonalDirection,allowed:true)
            #expect(simd_length(straight.velocity-beforeStraight)<=CourtNavigation.acceleration*dt+0.0001)
            #expect(simd_length(diagonal.velocity-beforeDiagonal)<=CourtNavigation.acceleration*dt+0.0001)
            #expect(simd_length(straight.velocity)<=1.2501 && simd_length(diagonal.velocity)<=1.2501)
        }
        #expect(abs(simd_length(straight.velocity)-1.25)<0.0001)
        #expect(abs(simd_length(straight.velocity)-simd_length(diagonal.velocity))<0.0001)
    }

    @Test(arguments:[SIMD2<Float>(1,0),[-1,0],[0,1],[0,-1]])
    func courtBoundsPreventNetAndWallOvershoot(direction:SIMD2<Float>) {
        var navigation=CourtNavigation()
        for _ in 0..<1_000 {
            navigation.step(dt:0.02,direction:direction,allowed:true)
            #expect(navigation.position.x>=CourtNavigation.minPosition.x && navigation.position.x<=CourtNavigation.maxPosition.x)
            #expect(navigation.position.y>=CourtNavigation.minPosition.y && navigation.position.y<=CourtNavigation.maxPosition.y)
        }
        #expect(navigation.velocity == .zero)
        #expect(CourtNavigation.minPosition.y > Court.netZ+0.65 && CourtNavigation.maxPosition.y < 1.7)
    }

    @Test func approachingAReceivingSpotSettlesWithoutOngoingDrift() {
        var navigation=CourtNavigation()
        let target=SIMD2<Float>(1.1,-1.6)
        for _ in 0..<800 {
            let direction=navigation.direction(toward:target)
            navigation.step(dt:0.01,direction:direction,allowed:true)
        }
        let settled=navigation.position
        #expect(simd_distance(settled,target)<0.04 && simd_length(navigation.velocity)<0.001)
        for _ in 0..<120 {
            let direction=navigation.direction(toward:target)
            navigation.step(dt:0.01,direction:direction,allowed:true)
            #expect(simd_distance(navigation.position,settled)<0.001)
        }
    }

    @Test func blockedOrInvalidElapsedFramesStopWithoutChangingPosition() {
        var navigation=CourtNavigation()
        for _ in 0..<10 { navigation.step(dt:0.02,direction:[1,0],allowed:true) }
        let position=navigation.position
        navigation.step(dt:0.01,direction:[1,0],allowed:false)
        #expect(navigation.position == position && navigation.velocity == .zero)
        for delta:Float in [0,-0.01,.nan,.infinity,0.11] {
            navigation.step(dt:delta,direction:[1,0],allowed:true)
            #expect(navigation.position == position && navigation.velocity == .zero)
        }
        navigation.step(dt:0.01,direction:[.nan,0],allowed:true)
        #expect(navigation.position == position && navigation.velocity == .zero)
        navigation.reset();#expect(navigation.position == .zero && navigation.velocity == .zero)
    }

    @Test func receivingPredictionUsesTheDescendingPlayerHalfReach() throws {
        let descending=Flight(position:[0.7,2.2,-3.5],velocity:[0,-1,2])
        let point=try #require(CourtNavigation.receivingPoint(for:descending,height:1.6))
        #expect(abs(point.y-1.6)<0.0001 && point.z > Court.netZ+0.65)
        let rising=Flight(position:[0.2,1.6,-3.9],velocity:[0,4,3])
        let afterApex=try #require(CourtNavigation.receivingPoint(for:rising,height:1.6))
        #expect(abs(afterApex.y-1.6)<0.0001 && afterApex.z > rising.position.z+0.2)
        let high=try #require(CourtNavigation.receivingPoint(for:descending,height:10))
        let low=try #require(CourtNavigation.receivingPoint(for:descending,height:-1))
        #expect(abs(high.y-1.85)<0.0001 && abs(low.y-1.15)<0.0001)
        #expect(CourtNavigation.receivingPoint(for:.init(position:[0,2,-3],velocity:[0,-1,-2]),height:1.6) == nil)
        #expect(CourtNavigation.receivingPoint(for:.init(position:[0,0.5,-3],velocity:[0,-1,2]),height:1.6) == nil)
        #expect(CourtNavigation.receivingPoint(for:descending,height:.nan) == nil)
    }

    @Test func freshThumbstickMovesTheCourtWhileTheInterfaceStaysInPlace() throws {
        let (saved,name)=try defaults();defer { saved.removePersistentDomain(forName:name) }
        let game=game(saved)
        game.assets.root.transform=Transform(scale:[1,1,1],rotation:simd_quatf(angle:0.53,axis:[0,1,0]),translation:[0.4,0,-0.6])
        let origin=game.assets.root.transformMatrix(relativeTo:nil)
        for _ in 0..<60 {
            game.receiveControllerPose(packet(game))
            game.advanceCourtMovement(1/60,stick:[1,0.5])
            #expect(game.virtualCourtSpeed<=1.2501)
            expectPose(game.assets.interfaceRoot.transformMatrix(relativeTo:nil),origin)
        }
        let position=game.virtualCourtPosition
        #expect(position.x>0.3 && position.y < -0.1)
        var offset=matrix_identity_float4x4;offset.columns.3=SIMD4(-position.x,0,-position.y,1)
        expectPose(game.assets.root.transformMatrix(relativeTo:nil),origin*offset)
    }

    enum Gate:CaseIterable { case pause,courtMenu,settings,rackets,setup,background,alignment,stale,wrongHand }
    @Test(arguments:Gate.allCases)
    func disabledAndStaleReadinessCannotContinueVirtualMotion(reason:Gate) throws {
        let (saved,name)=try defaults();defer { saved.removePersistentDomain(forName:name) }
        let game=game(saved)
        game.receiveControllerPose(packet(game))
        for _ in 0..<3 { game.advanceCourtMovement(0.02,stick:[1,0]) }
        let before=game.virtualCourtPosition
        #expect(game.virtualCourtSpeed>0)
        switch reason {
        case .pause:game.paused=true
        case .courtMenu:game.showCourtMenu=true
        case .settings:game.showSettings=true
        case .rackets:game.showRackets=true
        case .setup:game.showPlaySetup=true
        case .background:game.sceneActivityChanged(active:false)
        case .alignment:game.beginControllerAlignment();#expect(game.isControllerAlignmentPending)
        case .stale:game.receiveControllerPose(packet(game,timestamp:CACurrentMediaTime()-1))
        case .wrongHand:game.receiveControllerPose(packet(game,left:true))
        }
        game.advanceCourtMovement(0.02,stick:[1,0])
        #expect(game.virtualCourtPosition == before && game.virtualCourtSpeed == 0)
    }

    @Test(arguments:[Float(0),Float(0.71)])
    func controllerSDKVelocityOnlyRotatesWithYawDuringVirtualSliding(yaw:Float) throws {
        let (saved,name)=try defaults();defer { saved.removePersistentDomain(forName:name) }
        let game=game(saved),rotation=simd_quatf(angle:yaw,axis:[0,1,0]),physicalVelocity=V3(1.2,0.3,-0.7)
        game.assets.root.transform=Transform(scale:[1,1,1],rotation:rotation,translation:[0.4,0,-0.6])
        game.receiveControllerPose(packet(game,timestamp:CACurrentMediaTime()-0.02,velocity:physicalVelocity))
        game.receiveControllerPose(packet(game,velocity:physicalVelocity))
        let expected=rotation.inverse.act(physicalVelocity)
        for _ in 0..<40 {
            game.advanceCourtMovement(1/60,stick:[0.75,1])
            let source=packet(game,velocity:physicalVelocity)
            game.receiveControllerPose(source)
            #expect(simd_distance(game.controllerHeadVelocity,expected)<0.0001)
            #expect(abs(simd_length(game.controllerHeadVelocity)-simd_length(physicalVelocity))<0.0001)
            expectPose(game.assets.racket.transformMatrix(relativeTo:nil),source.measured)
        }
        #expect(simd_length(game.virtualCourtPosition)>0.1 && game.lastContact == nil)
    }

    @Test func repeatedFreshControllerPacketRemapsTheDisplayWithoutAddingMotionOrRevivingLoss() throws {
        let (saved,name)=try defaults();defer { saved.removePersistentDomain(forName:name) }
        let game=game(saved),velocity=V3(1.2,0,0)
        game.receiveControllerPose(packet(game,timestamp:CACurrentMediaTime()-0.02,velocity:velocity))
        let fresh=packet(game,velocity:velocity)
        game.receiveControllerPose(fresh)
        #expect(simd_length(game.controllerHeadVelocity)>1)
        for _ in 0..<3 {
            game.advanceCourtMovement(0.02,stick:[1,0])
            game.receiveControllerPose(fresh)
            #expect(game.controllerHeadVelocity == .zero && game.controllerReady)
            expectPose(game.assets.racket.transformMatrix(relativeTo:nil),fresh.measured)
        }
        #expect(game.virtualCourtPosition.x>0.001)
        game.receiveControllerPose(nil);game.receiveControllerPose(fresh)
        #expect(!game.controllerReady && !game.assets.racket.isEnabled && game.controllerHeadVelocity == .zero)
    }

    @Test func autoGlideMovesAroundAFixedPhysicalHandWithoutInventingASwing() throws {
        let (saved,name)=try defaults();defer { saved.removePersistentDomain(forName:name) }
        let game=game(saved,input:.hands),physical=pose(at:[0.8,1.23,-0.25])
        for _ in 0..<2 { game.receiveHandPose(physical,timestamp:CACurrentMediaTime());game.update(1/120) }
        #expect(game.effectiveCourtMovement == .autoGlide && game.racketReady)
        game.serve();try #require(game.isPreparingServe)
        for _ in 0..<120 {
            guard game.isPreparingServe else { break }
            game.receiveHandPose(physical,timestamp:CACurrentMediaTime());game.update(1/120)
        }
        try #require(!game.isPreparingServe && game.shuttleState != nil)
        for _ in 0..<36 {
            game.receiveHandPose(physical,timestamp:CACurrentMediaTime());game.update(1/120)
            #expect(game.handHeadVelocity == .zero && game.virtualCourtSpeed<=1.2501)
            expectPose(game.assets.racket.transformMatrix(relativeTo:nil),physical*game.handGripFit.offset)
        }
        #expect(simd_length(game.virtualCourtPosition)>0.005 && game.lastContact == nil)
    }

    @Test func realWorldHandMotionIsConvertedOnlyByYawWhileTheRootAlsoSlides() throws {
        let (saved,name)=try defaults();defer { saved.removePersistentDomain(forName:name) }
        let game=game(saved,input:.hands),rotation=simd_quatf(angle:0.63,axis:[0,1,0])
        game.assets.root.transform=Transform(scale:[1,1,1],rotation:rotation,translation:[0.2,0,-0.3])
        let initial=pose(at:[0.5,1.23,-0.4]),start=CACurrentMediaTime()-0.06
        game.receiveHandPose(initial,timestamp:start);game.update(1/90)
        game.receiveHandPose(initial,timestamp:start+0.02);game.update(1/90)
        #expect(game.handHeadVelocity == .zero)
        game.assets.root.position += [0.04,0,-0.03]
        var moved=initial;moved.columns.3.x += 0.03
        game.receiveHandPose(moved,timestamp:start+0.04);game.update(1/90)
        let expected=rotation.inverse.act(V3(1.5,0,0))
        #expect(simd_distance(game.handHeadVelocity,expected)<0.001)
        expectPose(game.assets.racket.transformMatrix(relativeTo:nil),moved*game.handGripFit.offset)
        #expect(game.lastContact == nil)
    }

    @Test func recenterClearsTheVirtualOffsetAndStartsANewPhysicalMotionBaseline() throws {
        let (saved,name)=try defaults();defer { saved.removePersistentDomain(forName:name) }
        let game=game(saved)
        game.assets.root.transform=Transform(scale:[1,1,1],rotation:simd_quatf(angle:0.4,axis:[0,1,0]),translation:[0.3,0,-0.5])
        let origin=game.assets.root.transformMatrix(relativeTo:nil)
        for _ in 0..<30 { game.receiveControllerPose(packet(game));game.advanceCourtMovement(1/60,stick:[1,0]) }
        #expect(game.virtualCourtPosition.x>0.1)
        game.recenter()
        #expect(game.virtualCourtPosition == .zero && game.virtualCourtSpeed == 0)
        #expect(game.controllerHeadVelocity == .zero && !game.controllerContactReady)
        expectPose(game.assets.root.transformMatrix(relativeTo:nil),origin)
        expectPose(game.assets.interfaceRoot.transformMatrix(relativeTo:nil),origin)
        game.receiveControllerPose(packet(game,velocity:[1,0,0]))
        #expect(game.controllerHeadVelocity == .zero && !game.controllerContactReady)
        game.receiveControllerPose(packet(game,velocity:[1,0,0]))
        #expect(simd_length(game.controllerHeadVelocity)>0.9)
    }

    @Test func handsFallbackAndChosenMovementPreferenceReloadWithoutOldTracking() throws {
        let (saved,name)=try defaults();defer { saved.removePersistentDomain(forName:name) }
        let game=game(saved)
        game.setCourtMovement(.thumbstick);game.input = .hands
        #expect(game.courtMovement == .thumbstick && game.effectiveCourtMovement == .autoGlide)
        let handsReloaded=GameModel(gripDefaults:saved)
        #expect(handsReloaded.input == .hands && handsReloaded.courtMovement == .thumbstick)
        #expect(handsReloaded.effectiveCourtMovement == .autoGlide && !handsReloaded.racketReady)
        game.input = .sense;game.setCourtMovement(.stationary)
        game.receiveControllerPose(packet(game))
        for _ in 0..<20 { game.advanceCourtMovement(0.02,stick:[1,1]) }
        #expect(game.virtualCourtPosition == .zero && game.virtualCourtSpeed == 0)
        for selected in CourtMovement.allCases {
            game.setCourtMovement(selected)
            let reloaded=GameModel(gripDefaults:saved)
            #expect(reloaded.courtMovement == selected && reloaded.effectiveCourtMovement == selected)
            #expect(reloaded.virtualCourtPosition == .zero && !reloaded.racketReady)
        }
    }
}
