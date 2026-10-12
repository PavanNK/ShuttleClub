import Foundation
import Testing
import simd
@testable import ShuttleCore

struct ComfortableFeedTests {
    // Actual default authored string-centre release: Milo's 1.35 scale,
    // shoulder/wrist offsets and final 0.10-radian pitch/0.05-radian roll.
    private let origin = V3(-0.146494, 1.544328, -7.745764)
    private let target = V3(0.347083, 1.6, -0.25)

    private struct Profile {
        var arrival: Flight
        var apex: Float
        var netHeight: Float?
    }
    private func profile(_ shot: Flight, duration: Float, frameStep: Float = 1 / 120) -> Profile {
        var flight = shot
        var remaining = duration
        var apex = shot.position.y
        var netHeight: Float?
        while remaining > 0 {
            let dt = min(frameStep, remaining)
            let before = flight.position
            flight.step(dt)
            remaining -= dt
            apex = max(apex, flight.position.y)
            if let crossing = Court.crossingHeight(from: before, to: flight.position) { netHeight = crossing }
        }
        return Profile(arrival: flight, apex: apex, netHeight: netHeight)
    }
    private func verify(_ feed: ComfortableFeed, target: V3,
                        limits: ComfortableFeedConstraints = .init()) throws {
        let measured = profile(feed.flight, duration: feed.duration)
        let net = try #require(measured.netHeight)
        let horizontal = simd_length(SIMD2(measured.arrival.velocity.x, measured.arrival.velocity.z))
        let angle = atan2(-measured.arrival.velocity.y, horizontal) * 180 / .pi
        #expect(feed.duration >= 0.5 && feed.duration <= 1.4)
        #expect(simd_distance(measured.arrival.position, target) < 0.015)
        #expect(measured.apex <= limits.maximumApexHeight + 0.001)
        #expect(net >= Court.netHeight + limits.minimumNetClearance - 0.001)
        #expect(measured.arrival.velocity.y <= -0.05)
        #expect(-measured.arrival.velocity.y <= limits.maximumArrivalDescentSpeed + 0.001)
        #expect(angle <= limits.maximumArrivalDescentAngleDegrees + 0.01)
        #expect(simd_length(measured.arrival.velocity) <= limits.maximumArrivalSpeed + 0.001)
        #expect(simd_length(feed.flight.velocity) <= limits.maximumLaunchSpeed)
        #expect(abs(feed.apexHeight - measured.apex) < 0.002)
        #expect(abs(feed.netCrossingHeight - net) < 0.002)
        #expect(simd_distance(feed.arrivalVelocity, measured.arrival.velocity) < 0.002)
        #expect(abs(feed.arrivalDescentAngleDegrees - angle) < 0.02)
    }

    @Test func starterFeedAvoidsTheExistingOverheadArc() throws {
        let feed = try #require(Flight.comfortableFeed(from: origin, to: target))
        try verify(feed, target: target)
        #expect(abs(feed.duration - 1.1) < 0.0001)
        #expect(abs(feed.apexHeight - 3.093) < 0.02)
        #expect(abs(feed.netCrossingHeight - 2.835) < 0.02)
        #expect(abs(feed.arrivalVelocity.y + 4.712) < 0.03)
        #expect(abs(feed.arrivalDescentAngleDegrees - 47.79) < 0.2)
        let existing = Flight.clearanceShot(from: origin, to: target, duration: 1.65)
        let oldProfile = profile(existing, duration: 1.65)
        #expect(oldProfile.apex > 4.9)
        #expect(feed.apexHeight + 1.8 < oldProfile.apex)
        // The competitive API retains its authored time/trajectory.
        let oldAim = Flight.aimed(from: origin, to: target, duration: 1.65)
        #expect(simd_distance(existing.velocity, oldAim.velocity) < 0.0001)
        print("COMFORTABLE FEED default: duration=\(feed.duration)s apex=\(feed.apexHeight)m net=\(feed.netCrossingHeight)m arrival=\(feed.arrivalVelocity)m/s descent=\(feed.arrivalDescentAngleDegrees)deg; existing apex=\(oldProfile.apex)m")
    }

    @Test func measuredLeftAndRightHoldsAtNavigationExtremesStayWithinEveryLimit() throws {
        var count = 0
        var durations = [Float](), apexes = [Float](), netHeights = [Float]()
        var descentSpeeds = [Float](), angles = [Float]()
        // Current app navigation bounds, +/-75cm measured ready offset,
        // low/high receiving heights and forward/back hold limits. The app
        // bounds these to x +/-2.4m and z [-4.2,1.2] before solving.
        for virtualX: Float in [-2.35, 0, 2.35] {
            for physicalX: Float in [-0.75, 0.75] {
                for height: Float in [1.15, 1.85] {
                    for virtualZ: Float in [-3.9, 0, 0.9] {
                        for physicalZ: Float in [-0.85, -0.1] {
                            let receiving = V3(min(2.4, max(-2.4, virtualX + physicalX)), height,
                                               min(1.2, max(-4.2, virtualZ + physicalZ)))
                            let feed = try #require(Flight.comfortableFeed(from: origin, to: receiving), "No feed for \(receiving)")
                            try verify(feed, target: receiving)
                            count += 1
                            durations.append(feed.duration); apexes.append(feed.apexHeight)
                            netHeights.append(feed.netCrossingHeight)
                            descentSpeeds.append(-feed.arrivalVelocity.y); angles.append(feed.arrivalDescentAngleDegrees)
                        }
                    }
                }
            }
        }
        #expect(count == 72)
        print("COMFORTABLE FEED ready/navigation: \(count) targets; duration=\(durations.min()!)...\(durations.max()!)s apex=\(apexes.min()!)...\(apexes.max()!)m minimum net=\(netHeights.min()!)m maximum descent=\(descentSpeeds.max()!)m/s / \(angles.max()!)deg")
    }

    @Test func tighterHeightLimitSearchesForAShorterValidTrajectory() throws {
        let limits = ComfortableFeedConstraints(maximumApexHeight: 2.8)
        let feed = try #require(Flight.comfortableFeed(from: origin, to: target, constraints: limits))
        #expect(feed.duration < 1.1)
        try verify(feed, target: target, limits: limits)
    }

    @Test func infeasibleTargetsAndPoliciesDoNotFallBackToHighLobs() {
        #expect(Flight.comfortableFeed(from: origin, to: [0, 1.15, Court.netZ + 0.01]) == nil)
        #expect(Flight.comfortableFeed(from: [0, 3.3, -8], to: target) == nil)
        #expect(Flight.comfortableFeed(from: origin, to: target,
                                      constraints: .init(maximumApexHeight: 1.7)) == nil)
        #expect(Flight.comfortableFeed(from: origin, to: target,
                                      constraints: .init(maximumLaunchSpeed: 3)) == nil)
        #expect(Flight.comfortableFeed(from: origin, to: target,
                                      constraints: .init(minimumNetClearance: 2)) == nil)
    }

    @Test func invalidInputsAndTargetsThatDoNotCrossTheNetAreRejected() {
        for bad: Float in [.nan, .infinity, -.infinity] {
            for axis in 0..<3 {
                var badOrigin = origin, badTarget = target
                badOrigin[axis] = bad; badTarget[axis] = bad
                #expect(Flight.comfortableFeed(from: badOrigin, to: target) == nil)
                #expect(Flight.comfortableFeed(from: origin, to: badTarget) == nil)
            }
            #expect(Flight.comfortableFeed(from: origin, to: target, constraints: .init(maximumApexHeight: bad)) == nil)
            #expect(Flight.comfortableFeed(from: origin, to: target, constraints: .init(maximumArrivalDescentSpeed: bad)) == nil)
        }
        #expect(Flight.comfortableFeed(from: origin, to: [0, 1.6, -9]) == nil)
        #expect(Flight.comfortableFeed(from: origin, to: [0, 1.6, Court.netZ]) == nil)
        #expect(Flight.comfortableFeed(from: origin, to: [0, -0.1, -0.25]) == nil)
        #expect(Flight.comfortableFeed(from: origin, to: target, constraints: .init(maximumArrivalDescentAngleDegrees: 90)) == nil)
        #expect(Flight.comfortableFeed(from: origin, to: target, constraints: .init(maximumArrivalSpeed: -1)) == nil)
    }

    @Test func crossingInTheOppositeDirectionUsesTheSamePhysicalConstraints() throws {
        let oppositeOrigin = V3(-origin.x, origin.y, 2 * Court.netZ - origin.z)
        let oppositeTarget = V3(-target.x, target.y, 2 * Court.netZ - target.z)
        let forward = try #require(Flight.comfortableFeed(from: origin, to: target))
        let reverse = try #require(Flight.comfortableFeed(from: oppositeOrigin, to: oppositeTarget))
        try verify(reverse, target: oppositeTarget)
        #expect(abs(forward.duration - reverse.duration) < 0.0001)
        #expect(abs(forward.apexHeight - reverse.apexHeight) < 0.002)
        #expect(abs(forward.arrivalVelocity.y - reverse.arrivalVelocity.y) < 0.002)
    }

    @Test func feedUsesTheNormalIntegratorAcrossRenderRates() throws {
        let feed = try #require(Flight.comfortableFeed(from: origin, to: target))
        for rate: Float in [30, 90, 120] {
            let measured = profile(feed.flight, duration: feed.duration, frameStep: 1 / rate)
            #expect(simd_distance(measured.arrival.position, target) < 0.015)
            #expect(simd_distance(measured.arrival.velocity, feed.arrivalVelocity) < 0.003)
            #expect(measured.apex < 3.2)
        }
    }
}
