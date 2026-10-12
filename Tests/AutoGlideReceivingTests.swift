import Foundation
import Testing
import QuartzCore
import RealityKit
import simd
import ShuttleCore
@testable import ShuttleClub

@MainActor @Suite(.serialized)
struct AutoGlideReceivingTests {
    private func game(_ saved:UserDefaults)->GameModel {
        let game=GameModel(gripDefaults:saved)
        game.input = .hands;game.leftHand=false;game.mode = .practice
        game.musicEnabled=false;game.soundEnabled=false;game.automaticServing=false
        game.racketKind = .coral;game.setCourtMovement(.autoGlide)
        ClubScene.robot(game.assets)
        game.assets.root.addChild(game.assets.milo);game.assets.milo.scale=[1.35,1.35,1.35]
        game.assets.root.addChild(game.assets.racket);game.assets.root.addChild(game.assets.shuttle)
        game.assets.root.addChild(game.assets.interfaceRoot)
        game.selectRacket(.coral);game.restart()
        return game
    }
    private func physicalPose(head:V3)->simd_float4x4 {
        // Hold the bed edge-on to the incoming shuttle, with a comfortable
        // fixed head position. A real incidental glancing contact is allowed.
        let rotation=simd_quatf(angle:.pi/2,axis:[0,1,0])
        var result=simd_float4x4(rotation)
        result.columns.3=SIMD4(head-rotation.act(V3(0,0.37,0)),1)
        return result
    }
    private func tick(_ game:GameModel,physical:simd_float4x4,dt:Float=1/90) {
        game.receiveHandPose(physical,timestamp:CACurrentMediaTime());game.update(dt)
    }
    private func launch(_ game:GameModel,physical:simd_float4x4) throws->Flight {
        game.receiveHandPose(physical,timestamp:CACurrentMediaTime());game.serve()
        try #require(game.isPreparingServe)
        for _ in 0..<120 {
            guard game.isPreparingServe else { break }
            tick(game,physical:physical)
        }
        return try #require(game.shuttleState)
    }

    @Test(arguments:[Float(-0.3),Float(0.3)])
    func receivingTargetIncludesTheStablePhysicalRacketOffset(side:Float) throws {
        let name="ShuttleClub.AutoGlideReceiving.Target.\(UUID().uuidString)"
        let saved=try #require(UserDefaults(suiteName:name));defer { saved.removePersistentDomain(forName:name) }
        let game=game(saved),head=V3(side,1.6,-0.25),physical=physicalPose(head:head)
        tick(game,physical:physical);tick(game,physical:physical)
        #expect(game.racketReady && game.effectiveCourtMovement == .autoGlide)
        #expect(simd_distance(game.playerReturnTarget,head)<0.001)
        let flight=try launch(game,physical:physical)
        let point=try #require(CourtNavigation.receivingPoint(for:flight,height:head.y))
        let expected=SIMD2(point.x-head.x,point.z-head.z)
        // Native serving keeps intentional lateral variation around the
        // original hold, rather than adding the hand offset to every feed.
        #expect(abs(expected.x-sin(Float(1)*1.7)*0.12)<0.025)
        #expect(abs(expected.y)<0.025)
    }

    @Test(arguments:[Float(-0.3),Float(0.3)])
    func threeRealFeedsDoNotAccumulateTheSameHeldHandOffset(side:Float) throws {
        let name="ShuttleClub.AutoGlideReceiving.Repeated.\(UUID().uuidString)"
        let saved=try #require(UserDefaults(suiteName:name));defer { saved.removePersistentDomain(forName:name) }
        let game=game(saved),head=V3(side,1.6,-0.25),physical=physicalPose(head:head)
        tick(game,physical:physical);tick(game,physical:physical)
        var launched=0
        for cycle in 1...3 {
            let flight=try launch(game,physical:physical);launched += 1
            let point=try #require(CourtNavigation.receivingPoint(for:flight,height:head.y))
            let expected=SIMD2(point.x-head.x,point.z-head.z)
            #expect(abs(expected.x-sin(Float(cycle)*1.7)*0.12)<0.025)
            for _ in 0..<800 {
                guard game.shuttleState != nil else { break }
                tick(game,physical:physical)
                #expect(game.handHeadVelocity == .zero)
                let displayed=game.assets.racket.transformMatrix(relativeTo:nil)
                for column in 0..<4 { #expect(simd_distance(displayed[column],physical[column])<0.0001) }
            }
            #expect(game.canServe && game.shuttleState == nil)
            #expect(game.score.milo == cycle)
            #expect(simd_distance(game.virtualCourtPosition,expected)<0.05)
            #expect(abs(game.virtualCourtPosition.x)<0.4 && abs(game.virtualCourtPosition.y)<0.04)
            let expectedFeed=V3(game.virtualCourtPosition.x+head.x,head.y,game.virtualCourtPosition.y+head.z)
            #expect(simd_distance(game.playerReturnTarget,expectedFeed)<0.001)
        }
        #expect(launched == 3)
    }
}
