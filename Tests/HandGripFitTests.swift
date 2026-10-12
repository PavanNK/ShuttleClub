import Foundation
import Testing
import simd
@testable import ShuttleClub

@MainActor @Suite
struct HandGripFitTests {
    @Test func defaultAndRotatedOffsetsAreRigidAndKeepTheHandleOrigin() {
        #expect(HandGripFit().calibratedOrientation == SIMD4<Float>(0, 0, 0, 1))
        #expect(matricesMatch(HandGripFit().offset, matrix_identity_float4x4))
        let fit = HandGripFit(calibratedOrientation:
            simd_quatf(angle: 0.8, axis: simd_normalize(SIMD3<Float>(1, -2, 3))).vector,
            tiltDegrees: 30, sideTiltDegrees: -20, faceTurnDegrees: 45)
        let matrix = fit.offset
        #expect(matrix.columns.3 == SIMD4<Float>(0, 0, 0, 1))
        #expect(matrix.columns.0.w == 0 && matrix.columns.1.w == 0 && matrix.columns.2.w == 0)
        #expect(abs(simd_determinant(matrix) - 1) < 0.00001)
        var trackedGrip = simd_float4x4(simd_quatf(angle: -0.4, axis: [0, 1, 0]))
        trackedGrip.columns.3 = SIMD4<Float>(0.3, 1.2, -0.7, 1)
        #expect((trackedGrip * matrix).columns.3 == trackedGrip.columns.3)
        #expect(simd_distance(matrix * SIMD4<Float>(0, 0.37, 0, 1),
                              SIMD4<Float>(0, 0.37, 0, 1)) > 0.1)
    }

    @Test func fineAnglesFollowRacketAxesAndFaceTurnKeepsTheShaftDirection() {
        let radians = Float.pi / 180
        let tilt = HandGripFit(tiltDegrees: 60).offset
        #expect(simd_distance(tilt * SIMD4<Float>(0, 1, 0, 0),
                              SIMD4<Float>(0, cos(60 * radians), sin(60 * radians), 0)) < 0.00001)
        let side = HandGripFit(sideTiltDegrees: 45).offset
        #expect(simd_distance(side * SIMD4<Float>(0, 1, 0, 0),
                              SIMD4<Float>(-sin(45 * radians), cos(45 * radians), 0, 0)) < 0.00001)
        let base = simd_quatf(angle: 0.7, axis: simd_normalize(SIMD3<Float>(1, -2, 3)))
        let still = HandGripFit(calibratedOrientation: base.vector,
                                tiltDegrees: 25, sideTiltDegrees: -20).offset
        let twisted = HandGripFit(calibratedOrientation: base.vector,
                                  tiltDegrees: 25, sideTiltDegrees: -20, faceTurnDegrees: 90).offset
        #expect(simd_distance(still.columns.1, twisted.columns.1) < 0.00001)
        #expect(simd_distance(still.columns.2, twisted.columns.2) > 1)
        // Quaternion order is observable: the local shaft twist happens first,
        // followed by side tilt, front/back tilt, then the calibrated base.
        let fine = base * simd_quatf(angle: 25 * radians, axis: [1, 0, 0])
            * simd_quatf(angle: -20 * radians, axis: [0, 0, 1])
            * simd_quatf(angle: 90 * radians, axis: [0, 1, 0])
        #expect(matricesMatch(twisted, simd_float4x4(fine)))
        #expect(twisted.columns.3 == SIMD4<Float>(0, 0, 0, 1))
    }

    @Test func fineAngleRangesClampAndLegacyQuaternionDataMigratesInPlace() throws {
        let fit = HandGripFit(tiltDegrees: 1_000, sideTiltDegrees: -1_000, faceTurnDegrees: 180)
        let bounded = fit.normalized()
        #expect(bounded.tiltDegrees == 60 && bounded.sideTiltDegrees == -45 && bounded.faceTurnDegrees == 90)
        let reloaded = try JSONDecoder().decode(HandGripFit.self, from: JSONEncoder().encode(fit))
        #expect(reloaded == bounded)
        let opposite = HandGripFit(tiltDegrees: -100, sideTiltDegrees: 100, faceTurnDegrees: -180).normalized()
        #expect(opposite.tiltDegrees == -60 && opposite.sideTiltDegrees == 45 && opposite.faceTurnDegrees == -90)
        let legacyData = Data("{\"calibratedOrientation\":[0,0,2,2]}".utf8)
        let legacy = try JSONDecoder().decode(HandGripFit.self, from: legacyData)
        #expect(legacy.tiltDegrees == 0 && legacy.sideTiltDegrees == 0 && legacy.faceTurnDegrees == 0)
        #expect(matricesMatch(legacy.offset, simd_float4x4(simd_quatf(angle: .pi / 2, axis: [0, 0, 1]))))
        let name = "HandGripFitLegacyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(legacyData, forKey: "ShuttleClub.HandGripFit.right.v1")
        #expect(matricesMatch(HandGripFitStore.load(left: false, defaults: defaults).offset, legacy.offset))
        var trimmed = legacy; trimmed.tiltDegrees = -15; trimmed.faceTurnDegrees = 30
        #expect(HandGripFitStore.save(trimmed, left: false, defaults: defaults))
        let relaunched = try #require(UserDefaults(suiteName: name))
        let saved = HandGripFitStore.load(left: false, defaults: relaunched)
        #expect(saved.tiltDegrees == -15 && saved.faceTurnDegrees == 30 && saved.sideTiltDegrees == 0)
        #expect(matricesMatch(saved.offset, trimmed.offset))
        #expect(HandGripFitStore.load(left: true, defaults: relaunched) == HandGripFit())
    }

    @Test func normalizationHandlesExtremeFiniteValuesAndEquivalentSigns() throws {
        for magnitude in [Float.greatestFiniteMagnitude, Float.leastNonzeroMagnitude, Float(7)] {
            let fit = HandGripFit(calibratedOrientation: [magnitude, 0, 0, magnitude])
            let normalized = fit.normalized()
            #expect(abs(simd_length(normalized.calibratedOrientation) - 1) < 0.00001)
            #expect(matricesMatch(normalized.offset,
                simd_float4x4(simd_quatf(angle: .pi / 2, axis: [1, 0, 0]))))
            let reloaded = try JSONDecoder().decode(HandGripFit.self, from: JSONEncoder().encode(fit))
            #expect(matricesMatch(reloaded.offset, normalized.offset))
        }
        let vector = simd_quatf(angle: 1.3, axis: simd_normalize(SIMD3<Float>(1, 2, -1))).vector
        let positive = HandGripFit(calibratedOrientation: vector * 3)
        let negative = HandGripFit(calibratedOrientation: -vector * 3)
        #expect(matricesMatch(positive.offset, negative.offset))
        let reloadedNegative = try JSONDecoder().decode(HandGripFit.self, from: JSONEncoder().encode(negative))
        #expect(matricesMatch(positive.offset, reloadedNegative.offset))
    }

    @Test func leftAndRightFitsPersistSeparatelyAndResetIndependently() throws {
        let name = "HandGripFitTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(HandGripFitStore.load(left: true, defaults: defaults) == HandGripFit())
        #expect(HandGripFitStore.load(left: false, defaults: defaults) == HandGripFit())
        let left = HandGripFit(calibratedOrientation: simd_quatf(angle: 0.7, axis: [0, 0, 1]).vector * 2,
                               tiltDegrees: -20, sideTiltDegrees: 10, faceTurnDegrees: 45)
        let right = HandGripFit(calibratedOrientation: simd_quatf(angle: -0.9, axis: [1, 0, 0]).vector * 4,
                                tiltDegrees: 35, sideTiltDegrees: -15, faceTurnDegrees: -60)
        #expect(HandGripFitStore.save(left, left: true, defaults: defaults))
        #expect(HandGripFitStore.save(right, left: false, defaults: defaults))
        #expect(defaults.data(forKey: "ShuttleClub.HandGripFit.left.v1") != nil)
        #expect(defaults.data(forKey: "ShuttleClub.HandGripFit.right.v1") != nil)
        let anotherDefaults = try #require(UserDefaults(suiteName: name))
        #expect(matricesMatch(HandGripFitStore.load(left: true, defaults: anotherDefaults).offset, left.offset))
        #expect(matricesMatch(HandGripFitStore.load(left: false, defaults: anotherDefaults).offset, right.offset))
        #expect(HandGripFitStore.load(left: true, defaults: anotherDefaults).faceTurnDegrees == 45)
        #expect(HandGripFitStore.load(left: false, defaults: anotherDefaults).tiltDegrees == 35)
        #expect(HandGripFitStore.save(HandGripFit(), left: true, defaults: defaults))
        #expect(HandGripFitStore.load(left: true, defaults: defaults) == HandGripFit())
        #expect(matricesMatch(HandGripFitStore.load(left: false, defaults: defaults).offset, right.offset))
    }

    @Test func nonfiniteAngleEditsCannotReplaceSavedFitsOrDecodeFromJSON() throws {
        let name = "HandGripFitInvalidAngleTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let previous = HandGripFit(tiltDegrees: 20, sideTiltDegrees: -10, faceTurnDegrees: 45)
        #expect(HandGripFitStore.save(previous, left: false, defaults: defaults))
        let saved = try #require(defaults.data(forKey: "ShuttleClub.HandGripFit.right.v1"))
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        for value in [Float.nan, .infinity, -.infinity] {
            for field in 0..<3 {
                var invalid = previous
                let key: String
                if field == 0 { invalid.tiltDegrees = value; key = "tiltDegrees" }
                else if field == 1 { invalid.sideTiltDegrees = value; key = "sideTiltDegrees" }
                else { invalid.faceTurnDegrees = value; key = "faceTurnDegrees" }
                let safe = invalid.normalized()
                #expect(safe.tiltDegrees.isFinite && safe.sideTiltDegrees.isFinite && safe.faceTurnDegrees.isFinite)
                #expect(!HandGripFitStore.save(invalid, left: false, defaults: defaults))
                #expect(defaults.data(forKey: "ShuttleClub.HandGripFit.right.v1") == saved)
                let encodedName = value.isNaN ? "NaN" : value > 0 ? "Infinity" : "-Infinity"
                let data = Data("{\"calibratedOrientation\":[0,0,0,1],\"\(key)\":\"\(encodedName)\"}".utf8)
                #expect((try? decoder.decode(HandGripFit.self, from: data)) == nil)
            }
        }
        #expect(HandGripFitStore.load(left: false, defaults: defaults) == previous)
        #expect(HandGripFitStore.load(left: true, defaults: defaults) == HandGripFit())
    }

    @Test func invalidQuaternionsCannotReplacePreviousSavedData() throws {
        let name = "HandGripFitInvalidTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let previous = HandGripFit(calibratedOrientation: simd_quatf(angle: 0.5, axis: [0, 1, 0]).vector)
        #expect(HandGripFitStore.save(previous, left: true, defaults: defaults))
        let previousData = try #require(defaults.data(forKey: "ShuttleClub.HandGripFit.left.v1"))
        let invalidVectors: [SIMD4<Float>] = [[0, 0, 0, 0], [.nan, 0, 0, 1],
                                             [0, .infinity, 0, 1], [0, 0, -.infinity, 1]]
        for vector in invalidVectors {
            let invalid = HandGripFit(calibratedOrientation: vector)
            #expect(invalid.normalized() == HandGripFit())
            #expect(matricesMatch(invalid.offset, matrix_identity_float4x4))
            #expect((try? JSONEncoder().encode(invalid)) == nil)
            #expect(!HandGripFitStore.save(invalid, left: true, defaults: defaults))
            #expect(defaults.data(forKey: "ShuttleClub.HandGripFit.left.v1") == previousData)
            #expect(matricesMatch(HandGripFitStore.load(left: true, defaults: defaults).offset, previous.offset))
        }
    }

    @Test func corruptedPersistedDataFallsBackWithoutChangingTheOtherHand() throws {
        let name = "HandGripFitCorruptionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let right = HandGripFit(calibratedOrientation: simd_quatf(angle: 0.3, axis: [1, 0, 0]).vector)
        #expect(HandGripFitStore.save(right, left: false, defaults: defaults))
        for raw in ["not JSON", "{}", "{\"calibratedOrientation\":[0,0,0,0]}",
                    "{\"calibratedOrientation\":[0,0,1]}", "{\"calibratedOrientation\":null}",
                    "{\"calibratedOrientation\":[0,0,0,\"NaN\"]}"] {
            let data = Data(raw.utf8)
            #expect((try? JSONDecoder().decode(HandGripFit.self, from: data)) == nil)
            defaults.set(data, forKey: "ShuttleClub.HandGripFit.left.v1")
            #expect(HandGripFitStore.load(left: true, defaults: defaults) == HandGripFit())
            #expect(matricesMatch(HandGripFitStore.load(left: false, defaults: defaults).offset, right.offset))
        }
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        for invalid in ["NaN", "Infinity", "-Infinity"] {
            let data = Data("{\"calibratedOrientation\":[0,0,0,\"\(invalid)\"]}".utf8)
            #expect((try? decoder.decode(HandGripFit.self, from: data)) == nil)
        }
    }

    private func matricesMatch(_ a: simd_float4x4, _ b: simd_float4x4) -> Bool {
        simd_distance(a.columns.0, b.columns.0) < 0.00001
            && simd_distance(a.columns.1, b.columns.1) < 0.00001
            && simd_distance(a.columns.2, b.columns.2) < 0.00001
            && simd_distance(a.columns.3, b.columns.3) < 0.00001
    }
}
