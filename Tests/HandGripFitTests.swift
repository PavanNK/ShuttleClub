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
            simd_quatf(angle: 0.8, axis: simd_normalize(SIMD3<Float>(1, -2, 3))).vector)
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
        let left = HandGripFit(calibratedOrientation: simd_quatf(angle: 0.7, axis: [0, 0, 1]).vector * 2)
        let right = HandGripFit(calibratedOrientation: simd_quatf(angle: -0.9, axis: [1, 0, 0]).vector * 4)
        #expect(HandGripFitStore.save(left, left: true, defaults: defaults))
        #expect(HandGripFitStore.save(right, left: false, defaults: defaults))
        #expect(defaults.data(forKey: "ShuttleClub.HandGripFit.left.v1") != nil)
        #expect(defaults.data(forKey: "ShuttleClub.HandGripFit.right.v1") != nil)
        let anotherDefaults = try #require(UserDefaults(suiteName: name))
        #expect(matricesMatch(HandGripFitStore.load(left: true, defaults: anotherDefaults).offset, left.offset))
        #expect(matricesMatch(HandGripFitStore.load(left: false, defaults: anotherDefaults).offset, right.offset))
        #expect(HandGripFitStore.save(HandGripFit(), left: true, defaults: defaults))
        #expect(HandGripFitStore.load(left: true, defaults: defaults) == HandGripFit())
        #expect(matricesMatch(HandGripFitStore.load(left: false, defaults: defaults).offset, right.offset))
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
