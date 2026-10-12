import Foundation
import Testing
import simd
@testable import ShuttleClub

@MainActor @Suite
struct SenseGripFitTests {
    @Test func leftAndRightFitsPersistIndependentlyThroughCodable() throws {
        let name = "SenseGripFitTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let left = SenseGripFit(translation: [0.02, -0.01, 0.03],
            calibratedOrientation: simd_quatf(angle: 0.4, axis: [0, 0, 1]).vector,
            pitchDegrees: 12, yawDegrees: -7, rollDegrees: 5)
        let right = SenseGripFit(translation: [-0.03, 0.04, -0.02],
            calibratedOrientation: simd_quatf(angle: -0.6, axis: [1, 0, 0]).vector,
            pitchDegrees: -16, yawDegrees: 9, rollDegrees: -4)
        #expect(SenseGripFitStore.save(left, left: true, defaults: defaults))
        #expect(SenseGripFitStore.save(right, left: false, defaults: defaults))
        let loadedLeft = SenseGripFitStore.load(left: true, defaults: defaults)
        let loadedRight = SenseGripFitStore.load(left: false, defaults: defaults)
        #expect(loadedLeft.translation == left.translation)
        #expect(loadedLeft.pitchDegrees == 12 && loadedLeft.yawDegrees == -7 && loadedLeft.rollDegrees == 5)
        #expect(loadedRight.translation == right.translation)
        #expect(loadedRight.pitchDegrees == -16 && loadedRight.yawDegrees == 9 && loadedRight.rollDegrees == -4)
        #expect(sameRotation(simd_quatf(vector: loadedLeft.calibratedOrientation),
                             simd_quatf(vector: left.calibratedOrientation)))
        #expect(sameRotation(simd_quatf(vector: loadedRight.calibratedOrientation),
                             simd_quatf(vector: right.calibratedOrientation)))
        #expect(SenseGripFitStore.save(SenseGripFit(), left: true, defaults: defaults))
        #expect(SenseGripFitStore.load(left: true, defaults: defaults) == SenseGripFit())
        #expect(matricesMatch(SenseGripFitStore.load(left: false, defaults: defaults).offset, right.offset))
    }

    @Test func defaultMountKeepsHandleAtGripAndHeadAlongGripMinusZ() {
        let grip = pose(rotation: simd_quatf(angle: 0.7, axis: simd_normalize([1, 2, -1])),
                        translation: [1.2, 0.9, -2.4])
        let racket = SenseGripFit().mountedPose(fromGrip: grip)
        #expect(simd_distance(racket.columns.3, grip.columns.3) < 0.00001)
        #expect(simd_distance(racket * SIMD4<Float>(0, 0.37, 0, 1),
                              grip * SIMD4<Float>(0, 0, -0.37, 1)) < 0.00001)
        #expect(simd_distance(racket * SIMD4<Float>(0, 0, 1, 0),
                              grip * SIMD4<Float>(1, 0, 0, 0)) < 0.00001)
        #expect(abs(simd_determinant(SenseGripFit.baseMount) - 1) < 0.00001)
    }

    @Test func fineAdjustmentIsLocalToCalibratedBaseAndDoesNotRotateTranslation() {
        let base = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        let fit = SenseGripFit(translation: [0.03, -0.02, 0.01],
            calibratedOrientation: base.vector, pitchDegrees: 20, yawDegrees: -15, rollDegrees: 10)
        let radians = Float.pi / 180
        let expected = base * simd_quatf(angle: 20 * radians, axis: [1, 0, 0])
            * simd_quatf(angle: 10 * radians, axis: [0, 0, 1])
            * simd_quatf(angle: -15 * radians, axis: [0, 1, 0])
        #expect(sameRotation(simd_quatf(fit.offset), expected))
        #expect(fit.offset.columns.3 == SIMD4<Float>(0.03, -0.02, 0.01, 1))
        #expect(abs(simd_determinant(fit.offset) - 1) < 0.00001)
    }

    @Test func quarterTurnPresetsKeepTiltedShaftHandleAndHeadVelocityFixed() {
        let base = simd_quatf(angle: 0.65, axis: simd_normalize(SIMD3<Float>(1, 2, -1)))
        let original = SenseGripFit(translation: [0.02, -0.03, 0.01],
            calibratedOrientation: base.vector, pitchDegrees: 28, rollDegrees: -21)
        let rotations = [simd_quatf(angle: 0, axis: [0, 1, 0]),
                         simd_quatf(angle: 1.2, axis: simd_normalize(SIMD3<Float>(-2, 1, 3)))]
        for rotation in rotations {
            let grip = pose(rotation: rotation, translation: [1.1, 1.3, -0.8])
            let before = original.mountedPose(fromGrip: grip)
            let velocity = SenseGripFit.headVelocity(worldFromAnchor: grip, mountedPose: before,
                                                     linear: [0.4, -0.2, 0.1], angular: [1, 3, -2])
            for degrees in [Float(-90), Float(90)] {
                var turned = original; turned.yawDegrees = degrees
                let after = turned.mountedPose(fromGrip: grip)
                #expect(simd_distance(before.columns.3, after.columns.3) < 0.00001)
                #expect(simd_distance(before.columns.1, after.columns.1) < 0.00001)
                #expect(simd_distance(before * SIMD4<Float>(0, 0.37, 0, 1),
                                      after * SIMD4<Float>(0, 0.37, 0, 1)) < 0.00001)
                #expect(abs(simd_dot(before.columns.2, after.columns.2)) < 0.00001)
                let turnedVelocity = SenseGripFit.headVelocity(worldFromAnchor: grip, mountedPose: after,
                    linear: [0.4, -0.2, 0.1], angular: [1, 3, -2])
                #expect(simd_distance(velocity, turnedVelocity) < 0.00001)
            }
        }
    }

    @Test func legacyRotationOrderMigrationPreservesSavedMountedPoseAndDoesNotRepeat() throws {
        let name = "SenseGripLegacyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let radians = Float.pi / 180
        let base = simd_quatf(angle: 0.6, axis: simd_normalize(SIMD3<Float>(1, -2, 1)))
        let translation = SIMD3<Float>(0.02, -0.03, 0.01)
        let legacyObject: [String: Any] = [
            "translation": [translation.x, translation.y, translation.z],
            "calibratedOrientation": [base.vector.x, base.vector.y, base.vector.z, base.vector.w],
            "pitchDegrees": 21, "yawDegrees": -37, "rollDegrees": 14]
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        let oldRotation = base * simd_quatf(angle: -37 * radians, axis: [0, 1, 0])
            * simd_quatf(angle: 21 * radians, axis: [1, 0, 0])
            * simd_quatf(angle: 14 * radians, axis: [0, 0, 1])
        var oldOffset = simd_float4x4(oldRotation)
        oldOffset.columns.3 = SIMD4<Float>(translation, 1)
        let grip = pose(rotation: simd_quatf(angle: -0.9, axis: [0, 1, 0]), translation: [0.7, 1.1, -2])
        let expected = grip * SenseGripFit.baseMount * oldOffset
        defaults.set(legacyData, forKey: "ShuttleClub.SenseGripFit.left.v1")
        let otherHand = SenseGripFit(pitchDegrees: -12, yawDegrees: 8, rollDegrees: 5)
        #expect(SenseGripFitStore.save(otherHand, left: false, defaults: defaults))
        let migrated = SenseGripFitStore.load(left: true, defaults: defaults)
        #expect(matricesMatch(migrated.mountedPose(fromGrip: grip), expected))
        #expect(migrated.translation == translation)
        #expect(migrated.pitchDegrees == 21 && migrated.yawDegrees == -37 && migrated.rollDegrees == 14)
        #expect(matricesMatch(SenseGripFitStore.load(left: false, defaults: defaults).offset, otherHand.offset))
        #expect(SenseGripFitStore.save(migrated, left: true, defaults: defaults))
        let encoded = try #require(defaults.data(forKey: "ShuttleClub.SenseGripFit.left.v1"))
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect((object["rotationOrderVersion"] as? Int) == 2)
        let relaunched = try #require(UserDefaults(suiteName: name))
        let reloaded = SenseGripFitStore.load(left: true, defaults: relaunched)
        #expect(matricesMatch(reloaded.mountedPose(fromGrip: grip), expected))
        #expect(sameRotation(simd_quatf(vector: reloaded.calibratedOrientation),
                             simd_quatf(vector: migrated.calibratedOrientation)))
    }

    @Test func calibrationPreservesTrimAndTranslationAndFollowsMovedCourt() {
        let worldRotation = simd_quatf(angle: 0.9, axis: simd_normalize([1, 2, 1]))
        let worldFromCourt = pose(rotation: worldRotation, translation: [1.5, -0.3, 2.1])
        let courtFromGrip = pose(rotation: simd_quatf(angle: -0.5, axis: [0, 1, 0]),
                                 translation: [0.4, 1.1, -0.7])
        let desiredCourt = simd_quatf(angle: -0.25, axis: [0, 0, 1])
        let original = SenseGripFit(translation: [0.02, -0.03, 0.01],
            calibratedOrientation: simd_quatf(angle: 0.3, axis: [1, 0, 0]).vector,
            pitchDegrees: 18, yawDegrees: -11, rollDegrees: 6)
        let fit = original.aligned(fromGrip: worldFromCourt * courtFromGrip,
                                   desiredOrientation: worldRotation * desiredCourt)
        let mounted = fit.mountedPose(fromGrip: worldFromCourt * courtFromGrip)
        #expect(sameRotation(simd_quatf(mounted), worldRotation * desiredCourt))
        #expect(fit.translation == original.translation)
        #expect(fit.pitchDegrees == 18 && fit.yawDegrees == -11 && fit.rollDegrees == 6)

        let movedRotation = simd_quatf(angle: -1.1, axis: simd_normalize([2, -1, 1]))
        let movedCourt = pose(rotation: movedRotation, translation: [-2.3, 0.5, -1.2])
        let moved = fit.mountedPose(fromGrip: movedCourt * courtFromGrip)
        #expect(sameRotation(simd_quatf(moved), movedRotation * desiredCourt))
        #expect(matricesMatch(moved, movedCourt * simd_inverse(worldFromCourt) * mounted))
        #expect(simd_distance(moved.columns.3, mounted.columns.3) > 1)
    }

    @Test func velocityUsesFittedHeadLeverArmAndAnchorLocalAngularVelocity() {
        let anchor = pose(rotation: simd_quatf(angle: .pi / 2, axis: [0, 0, 1]),
                          translation: [4, 2, -3])
        var anchorFromGrip = matrix_identity_float4x4
        anchorFromGrip.columns.3 = SIMD4<Float>(0.1, -0.04, 0.02, 1)
        let grip = anchor * anchorFromGrip
        let fit = SenseGripFit(translation: [0.02, -0.03, 0.01],
            calibratedOrientation: simd_quatf(angle: .pi / 2, axis: [0, 0, 1]).vector)
        let mounted = fit.mountedPose(fromGrip: grip)
        // Fitted head is (.11, .31, .05) in the anchor. Local omega (0,2,0)
        // contributes (.10,0,-.22); rotate total (.50,.20,-.32) into world.
        let result = SenseGripFit.headVelocity(worldFromAnchor: anchor, mountedPose: mounted,
                                              linear: [0.4, 0.2, -0.1], angular: [0, 2, 0])
        #expect(simd_distance(result, SIMD3<Float>(-0.2, 0.5, -0.32)) < 0.00001)
        let unfitted = SenseGripFit.headVelocity(worldFromAnchor: anchor,
            mountedPose: SenseGripFit().mountedPose(fromGrip: grip),
            linear: [0.4, 0.2, -0.1], angular: [0, 2, 0])
        #expect(simd_distance(result, unfitted) > 0.5)
    }

    @Test func finiteBoundsClampButNonfiniteAndZeroQuaternionCannotPersist() throws {
        let excessive = SenseGripFit(translation: [0.2, -0.3, 0.01],
            calibratedOrientation: [Float.greatestFiniteMagnitude, 0, 0, Float.greatestFiniteMagnitude],
            pitchDegrees: 120, yawDegrees: -180, rollDegrees: 45)
        let bounded = excessive.normalized()
        #expect(bounded.translation == SIMD3<Float>(0.08, -0.08, 0.01))
        #expect(bounded.pitchDegrees == 90 && bounded.yawDegrees == -90 && bounded.rollDegrees == 45)
        #expect(abs(simd_length(bounded.calibratedOrientation) - 1) < 0.00001)
        let decoded = try JSONDecoder().decode(SenseGripFit.self, from: JSONEncoder().encode(excessive))
        #expect(decoded.translation == bounded.translation && decoded.pitchDegrees == 90)

        let name = "SenseGripFitInvalidTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let previous = SenseGripFit(translation: [0.02, 0, 0])
        #expect(SenseGripFitStore.save(previous, left: true, defaults: defaults))
        let invalidFits = [
            SenseGripFit(translation: [Float.nan, 0, 0]),
            SenseGripFit(calibratedOrientation: [0, 0, 0, 0]),
            SenseGripFit(calibratedOrientation: [0, Float.infinity, 0, 1]),
            SenseGripFit(pitchDegrees: .infinity),
            SenseGripFit(yawDegrees: .nan),
            SenseGripFit(rollDegrees: -.infinity)]
        for invalid in invalidFits {
            #expect((try? JSONEncoder().encode(invalid)) == nil)
            #expect(!SenseGripFitStore.save(invalid, left: true, defaults: defaults))
            #expect(SenseGripFitStore.load(left: true, defaults: defaults) == previous)
            #expect(abs(simd_determinant(invalid.normalized().offset) - 1) < 0.00001)
        }
    }

    @Test func decoderRejectsNonfiniteAndMalformedPersistedData() throws {
        let valid = try JSONEncoder().encode(SenseGripFit())
        var object = try #require(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        object["pitchDegrees"] = "NaN"
        let nonfinite = try JSONSerialization.data(withJSONObject: object)
        #expect((try? decoder.decode(SenseGripFit.self, from: nonfinite)) == nil)
        object["pitchDegrees"] = 0
        object["calibratedOrientation"] = [0, 0, 0, 0]
        let zeroQuaternion = try JSONSerialization.data(withJSONObject: object)
        #expect((try? decoder.decode(SenseGripFit.self, from: zeroQuaternion)) == nil)
        object["calibratedOrientation"] = [0, 0, 1]
        let wrongDimension = try JSONSerialization.data(withJSONObject: object)
        #expect((try? decoder.decode(SenseGripFit.self, from: wrongDimension)) == nil)
    }

    private func pose(rotation: simd_quatf, translation: SIMD3<Float>) -> simd_float4x4 {
        var matrix = simd_float4x4(rotation)
        matrix.columns.3 = SIMD4<Float>(translation, 1)
        return matrix
    }

    private func sameRotation(_ a: simd_quatf, _ b: simd_quatf) -> Bool {
        abs(simd_dot(a.normalized.vector, b.normalized.vector)) > 0.99999
    }

    private func matricesMatch(_ a: simd_float4x4, _ b: simd_float4x4) -> Bool {
        simd_distance(a.columns.0, b.columns.0) < 0.00001
            && simd_distance(a.columns.1, b.columns.1) < 0.00001
            && simd_distance(a.columns.2, b.columns.2) < 0.00001
            && simd_distance(a.columns.3, b.columns.3) < 0.00001
    }
}
