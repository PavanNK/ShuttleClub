import Testing
import simd
@testable import ShuttleCore

struct RacketTests {
    @Test func stationaryRacketReflectsWithoutAddingEnergy() throws {
        let incoming=V3(0,0,12)
        let rebound=try #require(RacketImpact.rebound(incoming:incoming,headVelocity:.zero,normal:[0,0,1],contact:.zero,racket:.coral))
        #expect(rebound.z < 0); #expect(simd_length(rebound) < simd_length(incoming))
    }
    @Test func speedFaceAngleAndSweetSpotAffectPhysicalReturn() throws {
        func bounce(_ speed:Float,_ normal:V3,_ point:V3) throws -> V3 {
            try #require(RacketImpact.rebound(incoming:[0,0,8],headVelocity:[0,0,-speed],normal:normal,contact:point,racket:.coral))
        }
        let slow=try bounce(2,[0,0,1],.zero),fast=try bounce(8,[0,0,1],.zero)
        #expect(fast.z < slow.z)
        #expect(try bounce(4,[0.4,0,1],.zero).x < -1)
        #expect(simd_length(try bounce(4,[0,0,1],[0.13,0,0])) < simd_length(try bounce(4,[0,0,1],.zero)))
    }
    @Test func racketChoiceChangesReboundAndInvalidInputsAreRejected() throws {
        func speed(_ racket:RacketKind) throws -> Float {
            simd_length(try #require(RacketImpact.rebound(incoming:[0,0,8],headVelocity:[0,0,-4],normal:[0,0,1],contact:.zero,racket:racket)))
        }
        #expect(try speed(.solar) > speed(.mint))
        #expect(RacketImpact.rebound(incoming:[.nan,0,0],headVelocity:.zero,normal:[0,0,1],contact:.zero,racket:.coral) == nil)
    }
    @Test func trackingGateRejectsStaleWeakAndImplausiblePoses() {
        #expect(TrackingGate.accepts(age:0.02,fullPosition:true,speed:15))
        #expect(!TrackingGate.accepts(age:0.13,fullPosition:true,speed:15))
        #expect(!TrackingGate.accepts(age:0.02,fullPosition:false,speed:15))
        #expect(!TrackingGate.accepts(age:0.02,fullPosition:true,speed:60))
    }
    @Test func controllerButtonsFireOncePerPress() {
        var edges=ButtonEdges()
        #expect(edges.update(trigger:true,menu:false).serve)
        #expect(!edges.update(trigger:true,menu:false).serve)
        _=edges.update(trigger:false,menu:false)
        #expect(edges.update(trigger:true,menu:true).pause)
        #expect(!edges.update(trigger:true,menu:true).pause)
    }
}

@Test func departingCorkAndOutsideStringsCannotCreateContact() {
    #expect(RacketContact.intersection(from:[0,0,0.02],to:[0,0,0.2]) == nil)
    #expect(RacketContact.intersection(from:[0.4,0,0.3],to:[0.4,0,-0.3]) == nil)
    let touch=RacketContact.intersection(from:[0,0,1],to:[0,0,-1])
    #expect(touch != nil); #expect(abs((touch?.fraction ?? 0)-0.48)<0.001)
}
