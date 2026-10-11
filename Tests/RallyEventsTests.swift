import Testing
import simd
import ShuttleCore
@testable import ShuttleClub

struct RallyEventsTests {
    @Test func earliestFloorContactWinsOverLaterNetCrossing() throws {
        let event=try #require(RallyEvents.first(from:[0,0.2,-4.9],to:[0,-0.2,-5.1]))
        #expect(event.kind == .floor)
        #expect(abs(event.fraction-0.4)<0.0001)
        #expect(abs(event.position.y-0.04)<0.00001)
        #expect(event.position.z > Court.netZ)
    }
    @Test func earliestNetContactWinsOverLaterFloorContact() throws {
        let event=try #require(RallyEvents.first(from:[0,0.3,-4.8],to:[0,-0.1,-5.8]))
        #expect(event.kind == .net)
        #expect(abs(event.fraction-0.2)<0.0001)
        #expect(abs(event.position.z-Court.netZ)<0.00001)
        #expect(event.position.y > RallyEvents.floorHeight)
    }
    @Test func landingUsesFirstFloorPositionInsteadOfOvershootingEndpoint() throws {
        let end=V3(3.4,-0.1,0)
        let event=try #require(RallyEvents.first(from:[2.8,0.1,0],to:end))
        #expect(event.kind == .floor)
        #expect(Court.contains(event.position))
        #expect(!Court.contains(end))
        #expect(Court.winner(landing:event.position,lastHitter:.milo) == .milo)
    }
    @Test func airborneShuttleMayCrossSidelineAndClearNet() {
        #expect(RallyEvents.first(from:[2.8,2,-4],to:[3.4,2,-6]) == nil)
    }
    @Test func runawayDistanceHasSweptExitFraction() throws {
        let event=try #require(RallyEvents.first(from:[34,1,0],to:[36,1,0]))
        #expect(event.kind == .out)
        #expect(event.fraction > 0.49 && event.fraction < 0.5)
        #expect(abs(simd_length(event.position)-RallyEvents.maximumDistance)<0.0001)
    }
    @Test func alreadyGroundedShuttleFaultsAtFrameStart() throws {
        let start=V3(0,0.03,0)
        let event=try #require(RallyEvents.first(from:start,to:[0,0.02,0]))
        #expect(event.kind == .floor)
        #expect(event.fraction == 0)
        #expect(event.position == start)
    }
    @Test func nonfiniteEndpointsAreRejected() {
        #expect(RallyEvents.first(from:[0,Float.nan,0],to:[0,1,0]) == nil)
        #expect(RallyEvents.first(from:[0,1,0],to:[Float.infinity,1,0]) == nil)
    }
}
