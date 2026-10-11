import Testing
import simd
@testable import ShuttleCore

@Test func dragSolverReachesTarget() {
    for time: Float in [0.8, 1.3, 2] {
        let target = V3(1.4, 0.1, -10)
        let shot = Flight.aimed(from: V3(0, 1.7, 0), to: target, duration: time)
        #expect(simd_distance(shot.advanced(time).position, target) < 0.015)
    }
}
@Test func stableAcrossFrameRates() {
    var slow = Flight(position: V3(0, 2, 0), velocity: V3(1, 6, -12)), fast = slow
    for _ in 0..<30 { slow.step(1 / 30) }
    for _ in 0..<120 { fast.step(1 / 120) }
    #expect(simd_distance(slow.position, fast.position) < 0.01)
}
@Test func netCrossingDoesNotTunnel() {
    #expect(Court.crossingHeight(from: V3(0, 1, -4), to: V3(0, 1.2, -6))! < Court.netHeight)
    #expect(Court.crossingHeight(from: V3(0, 3, -4), to: V3(0, 2, -6))! > Court.netHeight)
}
@Test func legalAndIllegalLandings() {
    #expect(Court.winner(landing: V3(1, 0, -9), lastHitter: .player) == .player)
    #expect(Court.winner(landing: V3(4, 0, -9), lastHitter: .player) == .milo)
    #expect(Court.winner(landing: V3(0, 0, -2), lastHitter: .player) == .milo)
    #expect(Court.winner(landing: V3(0, 0, -1), lastHitter: .milo) == .milo)
}
@Test func winByTwo() {
    var score = MatchScore()
    for _ in 0..<6 { score.award(.player); score.award(.milo) }
    score.award(.player); #expect(score.winner == nil)
    score.award(.player); #expect(score.winner == .player)
}
@Test func sweptRacketAndEdgeMiss() {
    #expect(RacketContact.hit(from: V3(0, 0, -0.8), to: V3(0, 0, 0.8)) != nil)
    #expect(RacketContact.hit(from: V3(0.4, 0, -1), to: V3(0.4, 0, 1)) == nil)
    #expect(RacketContact.hit(from: V3(0, 0, 1), to: V3(0, 0, 2)) == nil)
}

@Test func clearDropAndSmashClearNetAndLandInCourt() {
    for (z,time): (Float,Float) in [(-7,1.25),(-9.3,0.95),(-11,1.9)] {
        var ball=Flight.clearanceShot(from:[0,1.6,-0.25],to:[1.8,0.06,z],duration:time)
        var crossed=false
        for _ in 0..<600 {
            let previous=ball.position; ball.step(1/120)
            if let height=Court.crossingHeight(from:previous,to:ball.position) { #expect(height > Court.netHeight); crossed=true }
            if ball.position.y <= 0.04 { break }
        }
        #expect(crossed); #expect(Court.winner(landing:ball.position,lastHitter:.player) == .player)
    }
}

@Test func opponentCanPlanShortAndDeepShots() {
    for z: Float in [-7,-9.3,-11] {
        let shot=Flight.clearanceShot(from:[0,1.6,-0.25],to:[1,0.06,z],duration:1.7)
        let contact=OpponentPlan.interception(shot)
        #expect(contact != nil)
        if let contact { #expect(contact.z < Court.netZ); #expect(contact.y > 0.35) }
    }
}

@Test func fastSmashSlowsAndStaysStableAcrossFrames() {
    var a=Flight(position:[0,8,0],velocity:[0,0,-80]),b=a
    for _ in 0..<15 { a.step(1/30) }
    for _ in 0..<60 { b.step(1/120) }
    #expect(simd_distance(a.position,b.position) < 0.02)
    #expect(simd_length(a.velocity) < 20)
    #expect(a.position.isFiniteVector)
}

@Test func finiteStringsEdgeContactHasARealSurfacePoint() throws {
    let edge=try #require(RacketContact.intersection(from:[0.155,0,0.5],to:[0.155,0,-0.5]))
    #expect(abs(edge.point.x-0.137)<0.0001)
    #expect(edge.point.z == 0)
    let cork=V3(0.155,0,0.5)+V3(0,0,-1)*edge.fraction
    #expect(simd_distance(cork,edge.point)<=0.04001)
    #expect(RacketContact.intersection(from:[0.18,0,0.5],to:[0.18,0,-0.5]) == nil)
}
