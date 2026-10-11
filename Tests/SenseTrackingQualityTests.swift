import Testing
import simd
import ShuttleCore
@testable import ShuttleClub

@MainActor @Suite
struct SenseTrackingQualityTests {
    let anchor=matrix_identity_float4x4
    var mounted:simd_float4x4 { SenseGripFit().mountedPose(fromGrip:anchor) }

    @Test func angularMotionUsesTheVisibleHeadLeverArmAndWorldRotation() throws {
        var worldFromAnchor=simd_float4x4(simd_quatf(angle:.pi/2,axis:[0,0,1]))
        worldFromAnchor.columns.3=SIMD4<Float>(1,1.2,-2,1)
        let racket=SenseGripFit().mountedPose(fromGrip:worldFromAnchor)
        let velocity=try #require(SenseControllers.validatedHeadVelocity(
            worldFromAnchor:worldFromAnchor,mountedPose:racket,linear:[0.2,0.1,0],
            angular:[0,10,0],fullPosition:true,age:0.01))
        // Local head (0,0,-.37), omega (0,10,0) produces (-3.7,0,0).
        // Add local translation, then rotate (-3.5,.1,0) into world space.
        #expect(simd_distance(velocity,V3(-0.1,-3.5,0))<0.0001)
    }

    @Test func invalidAngularVelocityCannotBecomeAValidStationaryRacket() {
        for invalid in [Float.nan,Float.infinity,-Float.infinity] {
            let angular=V3(0,invalid,0)
            // The existing math helper deliberately supplies a safe fallback.
            let fallback=SenseGripFit.headVelocity(worldFromAnchor:anchor,mountedPose:mounted,
                                                    linear:.zero,angular:angular)
            #expect(fallback == .zero)
            let accepted=SenseControllers.validatedHeadVelocity(worldFromAnchor:anchor,mountedPose:mounted,
                linear:.zero,angular:angular,fullPosition:true,age:0.01)
            #expect(accepted == nil)
        }
        for invalid in [Float.nan,Float.infinity,-Float.infinity] {
            let accepted=SenseControllers.validatedHeadVelocity(worldFromAnchor:anchor,mountedPose:mounted,
                linear:[invalid,0,0],angular:.zero,fullPosition:true,age:0.01)
            #expect(accepted == nil)
        }
    }

    @Test func stationaryAnchorCannotHideAnImplausiblyFastRotatingRacketHead() {
        let accepted=SenseControllers.validatedHeadVelocity(worldFromAnchor:anchor,mountedPose:mounted,
            linear:.zero,angular:[0,150,0],fullPosition:true,age:0.01)
        // Raw anchor translation is zero; the string centre nevertheless moves
        // 55.5 m/s and must fail the same speed gate as the displayed racket.
        #expect(accepted == nil)
        let overflow=SenseControllers.validatedHeadVelocity(worldFromAnchor:anchor,mountedPose:mounted,
            linear:.zero,angular:[0,Float.greatestFiniteMagnitude,0],fullPosition:true,age:0.01)
        #expect(overflow == nil)
    }

    @Test func weakOrStaleTrackingCannotArmContactEvenWithPlausibleMotion() {
        let weak=SenseControllers.validatedHeadVelocity(worldFromAnchor:anchor,mountedPose:mounted,
            linear:[0,0.2,0],angular:[0,4,0],fullPosition:false,age:0.01)
        let stale=SenseControllers.validatedHeadVelocity(worldFromAnchor:anchor,mountedPose:mounted,
            linear:[0,0.2,0],angular:[0,4,0],fullPosition:true,age:0.13)
        #expect(weak == nil && stale == nil)
    }

    @Test func stoppedAccessoryGetsOneAutomaticRecoveryWithoutRepeatedSessionStarts() {
        var gate=SenseControllers.RefreshGate()
        var refresh=gate.shouldRefresh(connectionChanged:true,configured:false,providerStopped:false,worldStopped:false)
        #expect(refresh)
        for _ in 0..<10 {
            refresh=gate.shouldRefresh(connectionChanged:false,configured:true,providerStopped:false,worldStopped:false)
            #expect(!refresh)
        }
        refresh=gate.shouldRefresh(connectionChanged:false,configured:true,providerStopped:true,worldStopped:false)
        #expect(refresh)
        // A newly running replacement does not erase the recovery budget.
        refresh=gate.shouldRefresh(connectionChanged:false,configured:true,providerStopped:false,worldStopped:false)
        #expect(!refresh)
        for _ in 0..<10 {
            refresh=gate.shouldRefresh(connectionChanged:false,configured:true,providerStopped:true,worldStopped:false)
            #expect(!refresh && gate.requiresRetry)
        }
        refresh=gate.shouldRefresh(connectionChanged:true,configured:false,providerStopped:true,worldStopped:false)
        #expect(refresh && !gate.requiresRetry)
    }

    @Test func failedConfigurationWaitsForRetryOrChangedConnectionsAndNeverRerunsStoppedWorld() {
        var gate=SenseControllers.RefreshGate()
        var refresh=gate.shouldRefresh(connectionChanged:false,configured:false,providerStopped:false,worldStopped:false)
        #expect(refresh)
        gate.failed()
        for _ in 0..<10 {
            refresh=gate.shouldRefresh(connectionChanged:false,configured:false,providerStopped:true,worldStopped:false)
            #expect(!refresh && gate.requiresRetry)
        }
        refresh=gate.shouldRefresh(connectionChanged:true,configured:false,providerStopped:false,worldStopped:false)
        #expect(refresh && !gate.requiresRetry)
        for changed in [false,true] {
            refresh=gate.shouldRefresh(connectionChanged:changed,configured:false,providerStopped:true,worldStopped:true)
            #expect(!refresh && gate.requiresRetry)
        }
        // An explicit tracking Retry creates a new gate/session/world lifetime.
        gate=SenseControllers.RefreshGate()
        refresh=gate.shouldRefresh(connectionChanged:false,configured:false,providerStopped:false,worldStopped:false)
        #expect(refresh && !gate.requiresRetry)
    }
}
