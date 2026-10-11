import Foundation
import Testing
import simd
import ShuttleCore

@Suite
struct RacketMotionContactTests {
    private func pose(angle: Float = 0, axis: V3 = [0, 1, 0],
                      position: V3 = .zero, scale: Float = 1) -> simd_float4x4 {
        var result = simd_float4x4(simd_quatf(angle: angle, axis: axis))
        result.columns.0 *= scale; result.columns.1 *= scale; result.columns.2 *= scale
        result.columns.3 = SIMD4<Float>(position, 1)
        return result
    }

    private func assertActualContact(_ hit: RacketSweep.Contact, radius: Float = 0.04,
                                     radiusX: Float = 0.137, radiusY: Float = 0.185) {
        #expect(simd_distance(hit.cork, hit.stringPoint) <= radius + 0.000006)
        #expect(hit.point.z == 0)
        #expect(pow(hit.point.x / radiusX, 2) + pow(hit.point.y / radiusY, 2) <= 1.00001)
        let actual = (hit.pose * SIMD4<Float>(hit.point + V3(0, 0.37, 0), 1)).xyz
        #expect(simd_distance(actual, hit.stringPoint) < 0.00001)
    }

    @Test func fixedFaceAndTranslatedFaceKeepTheirMeasuredContactFractions() throws {
        let fixed = try #require(RacketSweep.intersection(from: [0, 0.37, 1], to: [0, 0.37, -1],
            oldPose: pose(), newPose: pose()))
        #expect(abs(fixed.fraction - 0.48) < 0.00001)
        assertActualContact(fixed)
        let translated = try #require(RacketSweep.intersection(from: [0, 0.37, 0], to: [0, 0.37, 0],
            oldPose: pose(position: [0, 0, -0.2]), newPose: pose(position: [0, 0, 0.2])))
        #expect(abs(translated.fraction - 0.4) < 0.00001)
        assertActualContact(translated)
    }

    @Test func aRotatingLocalChordCannotInventAContactOutsideTheWorldStrings() {
        let old = pose(angle: -.pi / 6), new = pose(angle: .pi / 6)
        let from = V3(0.19, 0.37, -0.01), to = V3(0.19, 0.37, 0.01)
        // A local endpoint chord falsely reaches the strings although the cork
        // stays at least .19-.13=.06m from the actual rotating bed throughout.
        let a = (simd_inverse(old) * SIMD4<Float>(from, 1)).xyz - V3(0, 0.37, 0)
        let b = (simd_inverse(new) * SIMD4<Float>(to, 1)).xyz - V3(0, 0.37, 0)
        #expect(RacketContact.intersection(from: a, to: b, radiusX: 0.13, radiusY: 0.178) != nil)
        #expect(RacketSweep.intersection(from: from, to: to, oldPose: old, newPose: new,
                                        radiusX: 0.13, radiusY: 0.178) == nil)
    }

    @Test func aMovingEdgeCanStrikeWhileItsStringCentreHasNoVelocity() throws {
        let old = pose(), new = pose(angle: 0.08)
        let hit = try #require(RacketSweep.intersection(from: [0.10, 0.37, -0.045],
            to: [0.10, 0.37, -0.0445], oldPose: old, newPose: new))
        assertActualContact(hit)
        #expect(hit.fraction > 0 && hit.fraction < 1)
        let angular = RacketMotion.angularVelocity(from: old, to: new, duration: 0.01)
        #expect(simd_distance(angular, V3(0, 8, 0)) < 0.0001)
        let centre = V3.zero
        let contactVelocity = RacketMotion.pointVelocity(headVelocity: centre, angularVelocity: angular,
                                                        pose: hit.pose, contact: hit.point)
        #expect(contactVelocity.z < -0.75)
        let normal = hit.pose.columns.2.xyz
        #expect(RacketImpact.rebound(incoming: [0, 0, 0.05], headVelocity: centre,
                                    normal: normal, contact: hit.point, racket: .coral) == nil)
        let returned = try #require(RacketImpact.rebound(incoming: [0, 0, 0.05],
            headVelocity: contactVelocity, normal: normal, contact: hit.point, racket: .coral))
        #expect(returned.z < -0.5)
    }

    @Test func measuredSampleDurationControlsAngularVelocityAndOppositeSignsAreEquivalent() {
        let old = pose(), new = pose(angle: 4 / 60)
        let sampleVelocity = RacketMotion.angularVelocity(from: old, to: new, duration: 1 / 60)
        #expect(simd_distance(sampleVelocity, V3(0, 4, 0)) < 0.0001)
        let renderVelocity = RacketMotion.angularVelocity(from: old, to: new, duration: 1 / 90)
        #expect(simd_distance(renderVelocity, V3(0, 6, 0)) < 0.0001)
        let rotation = simd_quatf(angle: 1.2, axis: simd_normalize(V3(1, 2, -1)))
        #expect(RacketMotion.angularVelocity(from: simd_float4x4(rotation),
            to: simd_float4x4(simd_quatf(vector: -rotation.vector)), duration: 1 / 60) == .zero)
    }

    @Test(arguments: [Float(1) / 30, Float(1) / 60, Float(1) / 90])
    func rotatingContactTimeStaysConsistentAcrossFrameBoundaries(dt: Float) throws {
        func cork(_ time: Float) -> V3 { [0.1, 0.37, -0.06 + 0.1 * time] }
        var time: Float = 0
        var detected: (RacketSweep.Contact, Float)?
        for _ in 0..<12 {
            if let hit = RacketSweep.intersection(from: cork(time), to: cork(time + dt),
                oldPose: pose(angle: 8 * time), newPose: pose(angle: 8 * (time + dt))) {
                detected = (hit, time + hit.fraction * dt)
                break
            }
            time += dt
        }
        let (hit, contactTime) = try #require(detected)
        assertActualContact(hit)
        // At this interior contact the exact rotating plane reaches the cork
        // when its local signed z rises from -.06 to the -.04m cork surface.
        var low: Float = 0, high: Float = 0.1
        for _ in 0..<32 {
            let middle = (low + high) / 2
            let signedZ = sin(8 * middle) * 0.1 + cos(8 * middle) * (-0.06 + 0.1 * middle)
            if signedZ < -0.04 { low = middle } else { high = middle }
        }
        #expect(abs(contactTime - (low + high) / 2) < 0.00003)
    }

    @Test func contactVelocityRotatesAndScalesTheActualOffCentreLever() {
        let matrix = pose(angle: .pi / 2, axis: [0, 0, 1], position: [5, 2, -3], scale: 1.35)
        let result = RacketMotion.pointVelocity(headVelocity: [1, 2, 3], angularVelocity: [0, 0, 4],
                                               pose: matrix, contact: [0.1, 0, 0])
        // World lever is (0,.135,0), so omega cross lever is (-.54,0,0).
        #expect(simd_distance(result, V3(0.46, 2, 3)) < 0.00001)
        let centre = RacketMotion.pointVelocity(headVelocity: [1, 2, 3], angularVelocity: [0, 0, 4],
                                               pose: matrix, contact: .zero)
        #expect(centre == V3(1, 2, 3))
    }

    @Test func scaledStringsKeepTheCorkRadiusInWorldMetres() throws {
        let matrix = pose(scale: 1.35)
        let hit = try #require(RacketSweep.intersection(from: [0.2, 0.37 * 1.35, 0.5],
            to: [0.2, 0.37 * 1.35, -0.5], oldPose: matrix, newPose: matrix,
            radiusX: 0.13, radiusY: 0.178))
        assertActualContact(hit, radiusX: 0.13, radiusY: 0.178)
        #expect(abs(hit.stringPoint.x - 0.13 * 1.35) < 0.00001)
        #expect(RacketSweep.intersection(from: [0.23, 0.37 * 1.35, 0.5],
            to: [0.23, 0.37 * 1.35, -0.5], oldPose: matrix, newPose: matrix,
            radiusX: 0.13, radiusY: 0.178) == nil)
    }

    @Test func departingTangentialAndStationaryCorksCannotCreateReturns() {
        let matrix = pose()
        #expect(RacketSweep.intersection(from: [0, 0.37, 0.02], to: [0, 0.37, 0.2],
                                        oldPose: matrix, newPose: matrix) == nil)
        #expect(RacketSweep.intersection(from: [-0.05, 0.37, 0.04], to: [0.05, 0.37, 0.04],
                                        oldPose: matrix, newPose: matrix) == nil)
        #expect(RacketSweep.intersection(from: [0, 0.37, 0], to: [0.05, 0.37, 0],
                                        oldPose: matrix, newPose: matrix) == nil)
        #expect(RacketSweep.intersection(from: [0, 0.37, 0.02], to: [0, 0.37, 0.02],
                                        oldPose: matrix, newPose: matrix) == nil)
    }

    @Test func invalidPosesAndNonfiniteMotionCannotCreateContacts() {
        let valid = pose()
        var invalid = valid; invalid.columns.3.x = .nan
        var sheared = valid; sheared.columns.0.y = 0.4
        var collapsed = valid; collapsed.columns.0 = .zero
        for matrix in [invalid, sheared, collapsed] {
            #expect(RacketSweep.intersection(from: [0, 0.37, 1], to: [0, 0.37, -1],
                                            oldPose: valid, newPose: matrix) == nil)
            #expect(RacketMotion.angularVelocity(from: valid, to: matrix, duration: 1 / 60) == .zero)
        }
        #expect(RacketSweep.intersection(from: [.nan, 0.37, 1], to: [0, 0.37, -1],
                                        oldPose: valid, newPose: valid) == nil)
        #expect(RacketMotion.angularVelocity(from: valid, to: pose(angle: 0.2), duration: 0) == .zero)
        let invalidVelocity = RacketMotion.pointVelocity(headVelocity: [.nan, 0, 0],
            angularVelocity: .zero, pose: valid, contact: .zero)
        #expect(RacketImpact.rebound(incoming: [0, 0, 8], headVelocity: invalidVelocity,
                                    normal: [0, 0, 1], contact: .zero, racket: .coral) == nil)
    }
}

private extension SIMD4 where Scalar == Float {
    var xyz: V3 { [x, y, z] }
}
