import Testing
import simd
import ShuttleCore
@testable import ShuttleClub

@Suite struct HandGripTrackerTests {
    private func wrist(rotation: simd_quatf = simd_quatf(angle: 0, axis: [0, 1, 0]),
                       position: V3 = .zero) -> simd_float4x4 {
        var matrix = simd_float4x4(rotation)
        matrix.columns.3 = SIMD4(position, 1)
        return matrix
    }

    private func joint(_ position: V3, tracked: Bool = true) -> HandRacketPose.Joint {
        .init(position: position, isTracked: tracked)
    }

    private func knuckles(_ worldFromWrist: simd_float4x4 = matrix_identity_float4x4,
                          mirror: Float = 1) -> [HandRacketPose.Joint] {
        let positions: [V3] = [[0.04 * mirror, 0.09, 0], [0, 0.1, 0], [-0.035 * mirror, 0.085, 0]]
        return positions.map {
            let world = worldFromWrist * SIMD4($0, 1)
            return joint(V3(world.x, world.y, world.z))
        }
    }

    private func update(_ tracker: inout HandGripTracker, wrist: simd_float4x4,
                        tracked: Bool = true, joints: [HandRacketPose.Joint]) -> simd_float4x4? {
        tracker.update(worldFromWrist: wrist, isTracked: tracked,
                       indexKnuckle: joints[0], middleKnuckle: joints[1], littleKnuckle: joints[2])
    }

    private func expectPose(_ actual: simd_float4x4, _ expected: simd_float4x4) {
        for column in 0..<4 { #expect(simd_distance(actual[column], expected[column]) < 0.0001) }
    }

    @Test func translatedAndRotatedWristFollowsTheAcquiredMountExactly() throws {
        var tracker = HandGripTracker()
        let firstWrist = wrist(rotation: simd_quatf(angle: 0.6, axis: simd_normalize(V3(1, 2, 3))),
                               position: [0.3, 1.2, -0.7])
        let initialResult = update(&tracker, wrist: firstWrist, joints: knuckles(firstWrist))
        let initial = try #require(initialResult)
        let localMount = simd_inverse(firstWrist) * initial
        let nextWrist = wrist(rotation: simd_quatf(angle: -1.1, axis: simd_normalize(V3(2, -1, 1))),
                              position: [-0.4, 1.6, -0.2])
        let nextResult = update(&tracker, wrist: nextWrist, joints: knuckles(firstWrist))
        let actual = try #require(nextResult)
        expectPose(actual, nextWrist * localMount)
    }

    @Test func movedAndLostKnucklesDoNotRefitAnAcquiredGrip() throws {
        var tracker = HandGripTracker()
        let initialResult = update(&tracker, wrist: wrist(), joints: knuckles())
        let initial = try #require(initialResult)
        let curled = [joint([0.01, 0.05, -0.04]), joint([-0.01, 0.07, -0.02]), joint([-0.025, 0.06, -0.03])]
        let curledResult = update(&tracker, wrist: wrist(), joints: curled)
        expectPose(try #require(curledResult), initial)
        let lost = [joint([.nan, 0, 0], tracked: false), joint(.zero, tracked: false), joint(.zero, tracked: false)]
        let lostResult = update(&tracker, wrist: wrist(), joints: lost)
        expectPose(try #require(lostResult), initial)
    }

    @Test func missingWristHidesTheRacketAndFreshWristUsesCachedLocalMount() throws {
        var tracker = HandGripTracker()
        let initialResult = update(&tracker, wrist: wrist(), joints: knuckles())
        let initial = try #require(initialResult)
        let lostKnuckles = knuckles().map { joint($0.position, tracked: false) }
        let missing = update(&tracker, wrist: wrist(position: [9, 9, 9]), tracked: false, joints: lostKnuckles)
        #expect(missing == nil)
        let recoveredWrist = wrist(rotation: simd_quatf(angle: 0.9, axis: [0, 1, 0]), position: [0.2, 1.1, -0.4])
        let recovered = update(&tracker, wrist: recoveredWrist, joints: lostKnuckles)
        expectPose(try #require(recovered), recoveredWrist * initial)
    }

    @Test func incompleteDegenerateAndDistantInitialKnucklesCannotEstablishAMount() throws {
        var tracker = HandGripTracker()
        for missing in 0..<3 {
            let incomplete = knuckles().enumerated().map { joint($0.element.position, tracked: $0.offset != missing) }
            let result = update(&tracker, wrist: wrist(), joints: incomplete)
            #expect(result == nil)
        }
        let degenerate = update(&tracker, wrist: wrist(), joints: Array(repeating: joint([0, 0.1, 0]), count: 3))
        #expect(degenerate == nil)
        let distant = knuckles().map { joint($0.position + V3(0, 1, 0)) }
        let distantResult = update(&tracker, wrist: wrist(), joints: distant)
        #expect(distantResult == nil)
        let invalid = update(&tracker, wrist: wrist(), joints: [joint([.nan, 0, 0]), knuckles()[1], knuckles()[2]])
        #expect(invalid == nil)
        let valid = update(&tracker, wrist: wrist(), joints: knuckles())
        let actual = try #require(valid)
        #expect(simd_distance(actual.columns.3, SIMD4<Float>(0, 0.055, 0, 1)) < 0.0001)
    }

    @Test func resetRequiresFreshKnuckleAcquisition() throws {
        var tracker = HandGripTracker()
        let initial = update(&tracker, wrist: wrist(), joints: knuckles())
        #expect(initial != nil)
        tracker.reset()
        let missing = knuckles().map { joint($0.position, tracked: false) }
        let result = update(&tracker, wrist: wrist(), joints: missing)
        #expect(result == nil)
        let mirrored = update(&tracker, wrist: wrist(), joints: knuckles(mirror: -1))
        let actual = try #require(mirrored)
        #expect(actual.columns.1.x < -0.99)
    }

    @Test func mirroredHandsKeepProperRotationsWhenFollowingTheWrist() throws {
        for mirror: Float in [1, -1] {
            var tracker = HandGripTracker()
            let initialResult = update(&tracker, wrist: wrist(), joints: knuckles(mirror: mirror))
            let initial = try #require(initialResult)
            #expect(initial.columns.1.x * mirror > 0.99)
            let movedWrist = wrist(rotation: simd_quatf(angle: -0.7, axis: simd_normalize(V3(1, 3, 2))),
                                   position: [0.7, 1.3, -0.5])
            let result = update(&tracker, wrist: movedWrist, joints: knuckles(mirror: mirror))
            let mounted = try #require(result)
            expectPose(mounted, movedWrist * initial)
            let rotation = simd_float3x3(columns: (
                V3(mounted.columns.0.x, mounted.columns.0.y, mounted.columns.0.z),
                V3(mounted.columns.1.x, mounted.columns.1.y, mounted.columns.1.z),
                V3(mounted.columns.2.x, mounted.columns.2.y, mounted.columns.2.z)))
            #expect(abs(simd_determinant(rotation) - 1) < 0.0001)
        }
    }

    @Test func invalidWristMatricesCannotCreateOrReviveAWorldPose() throws {
        var nonfinite = wrist(); nonfinite.columns.3.x = .nan
        var scaled = wrist(); scaled.columns.0.x = 2
        var reflected = wrist(); reflected.columns.0.x = -1
        var sheared = wrist(); sheared.columns.1.x = 0.2
        var singular = wrist(); singular.columns.0 = .zero
        var nonaffine = wrist(); nonaffine.columns.3.w = 0
        let invalidMatrices = [nonfinite, scaled, reflected, sheared, singular, nonaffine]
        var tracker = HandGripTracker()
        for matrix in invalidMatrices {
            let result = update(&tracker, wrist: matrix, joints: knuckles())
            #expect(result == nil)
        }
        let acquiredResult = update(&tracker, wrist: wrist(), joints: knuckles())
        let acquired = try #require(acquiredResult)
        for matrix in invalidMatrices {
            let result = update(&tracker, wrist: matrix, joints: knuckles())
            #expect(result == nil)
        }
        let missing = knuckles().map { joint($0.position, tracked: false) }
        let recovered = update(&tracker, wrist: wrist(), joints: missing)
        expectPose(try #require(recovered), acquired)
    }

    @Test func captureLocksAnOpenHandPreviewThroughGrabClosure() throws {
        var tracker = HandGripTracker()
        let openResult = update(&tracker, wrist: wrist(), joints: knuckles())
        let openPreview = try #require(openResult)
        tracker.reset()
        let closureWrist = wrist(rotation: simd_quatf(angle: 0.4, axis: [1, 0, 0]), position: [0.2, 1.2, -0.5])
        let captured = tracker.capture(worldFromWrist: closureWrist, worldFromGrip: closureWrist * openPreview)
        #expect(captured)
        let missing = knuckles().map { joint($0.position, tracked: false) }
        let held = update(&tracker, wrist: closureWrist, joints: missing)
        expectPose(try #require(held), closureWrist * openPreview)
        let movedWrist = wrist(rotation: simd_quatf(angle: -0.8, axis: [0, 0, 1]), position: [-0.1, 1.4, -0.4])
        let moved = update(&tracker, wrist: movedWrist, joints: missing)
        expectPose(try #require(moved), movedWrist * openPreview)
    }

    @Test func invalidCaptureDoesNotAttachOrOverwriteAGoodMount() throws {
        var tracker = HandGripTracker()
        var nonrigid = wrist(); nonrigid.columns.0.x = 2
        let badWrist = tracker.capture(worldFromWrist: nonrigid, worldFromGrip: wrist())
        #expect(!badWrist)
        let badGrip = tracker.capture(worldFromWrist: wrist(), worldFromGrip: nonrigid)
        #expect(!badGrip)
        let distant = tracker.capture(worldFromWrist: wrist(), worldFromGrip: wrist(position: [0, 0.3, 0]))
        #expect(!distant)
        let missing = knuckles().map { joint($0.position, tracked: false) }
        let unattached = update(&tracker, wrist: wrist(), joints: missing)
        #expect(unattached == nil)
        let mounted = wrist(rotation: simd_quatf(angle: -0.2, axis: [0, 0, 1]), position: [0, 0.055, 0])
        let captured = tracker.capture(worldFromWrist: wrist(), worldFromGrip: mounted)
        #expect(captured)
        let rejected = tracker.capture(worldFromWrist: wrist(), worldFromGrip: nonrigid)
        #expect(!rejected)
        let preserved = update(&tracker, wrist: wrist(), joints: missing)
        expectPose(try #require(preserved), mounted)
    }
}
