import simd
import ShuttleCore

/// A measured palm frame, independent of ARKit's wrist-joint axis convention.
/// The racket handle is centred in the palm and its +Y axis exits on the
/// index/thumb side of the knuckles. The string plane has a palm-normal +Z.
enum HandRacketPose {
    struct Joint:Sendable {
        let position:V3
        let isTracked:Bool
    }

    static func make(wrist:Joint,indexKnuckle:Joint,middleKnuckle:Joint,littleKnuckle:Joint)->simd_float4x4? {
        let joints=[wrist,indexKnuckle,middleKnuckle,littleKnuckle]
        guard joints.allSatisfy({ $0.isTracked && $0.position.isFiniteVector }) else { return nil }
        let across=indexKnuckle.position-littleKnuckle.position
        let forward=middleKnuckle.position-wrist.position
        guard simd_length(across)>0.015,simd_length(forward)>0.025 else { return nil }
        let y=simd_normalize(across)
        let normal=simd_cross(y,simd_normalize(forward))
        guard simd_length(normal)>0.25 else { return nil }
        let z=simd_normalize(normal),x=simd_normalize(simd_cross(y,z))
        let origin=wrist.position+forward*0.55
        return simd_float4x4(columns:(SIMD4(x,0),SIMD4(y,0),SIMD4(z,0),SIMD4(origin,1)))
    }
}

/// Acquires a palm-centred mount once, then follows the measured wrist rigidly.
/// Curling fingers or losing knuckle tracking cannot refit an acquired mount.
/// The caller gates grabbing and sample freshness, and resets on release or
/// hand/provider changes. Merely showing an open hand must not call update.
struct HandGripTracker {
    private var wristFromGrip: simd_float4x4?

    /// Locks an open-hand preview at deliberate grab closure. Both transforms
    /// must describe the same measured wrist sample; reproject a previously
    /// saved wrist-local preview through the current wrist before capturing.
    /// Invalid capture attempts retain any existing mount.
    @discardableResult
    mutating func capture(worldFromWrist: simd_float4x4,
                          worldFromGrip: simd_float4x4) -> Bool {
        guard Self.isRigid(worldFromWrist), Self.isRigid(worldFromGrip) else { return false }
        let localMount = simd_inverse(worldFromWrist) * worldFromGrip
        guard Self.isRigid(localMount), simd_length(Self.position(localMount)) <= 0.14 else { return false }
        wristFromGrip = localMount
        return true
    }

    /// Knuckle positions and the full wrist transform share world coordinates.
    /// An invalid wrist returns no pose while retaining the local attachment,
    /// so a freshly tracked wrist can recover without a new knuckle fit.
    mutating func update(worldFromWrist: simd_float4x4, isTracked: Bool,
                         indexKnuckle: HandRacketPose.Joint,
                         middleKnuckle: HandRacketPose.Joint,
                         littleKnuckle: HandRacketPose.Joint) -> simd_float4x4? {
        guard isTracked, Self.isRigid(worldFromWrist) else { return nil }
        if wristFromGrip == nil {
            let wristPosition = Self.position(worldFromWrist)
            let knuckles = [indexKnuckle, middleKnuckle, littleKnuckle]
            // A corrupt distant joint must not become a permanent attachment.
            guard knuckles.allSatisfy({
                $0.isTracked && $0.position.isFiniteVector &&
                    simd_distance($0.position, wristPosition) <= 0.25
            }), let measuredGrip = HandRacketPose.make(
                wrist: .init(position: wristPosition, isTracked: true),
                indexKnuckle: indexKnuckle, middleKnuckle: middleKnuckle,
                littleKnuckle: littleKnuckle), Self.isRigid(measuredGrip) else { return nil }
            guard capture(worldFromWrist: worldFromWrist, worldFromGrip: measuredGrip) else { return nil }
        }
        guard let wristFromGrip else { return nil }
        let mounted = worldFromWrist * wristFromGrip
        return Self.isRigid(mounted) ? mounted : nil
    }

    mutating func reset() { wristFromGrip = nil }

    private static func position(_ matrix: simd_float4x4) -> V3 {
        V3(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z)
    }

    private static func isRigid(_ matrix: simd_float4x4) -> Bool {
        for column in 0..<4 {
            let value = matrix[column]
            guard value.x.isFinite, value.y.isFinite, value.z.isFinite, value.w.isFinite else { return false }
        }
        guard abs(matrix.columns.0.w) < 0.0001, abs(matrix.columns.1.w) < 0.0001,
              abs(matrix.columns.2.w) < 0.0001, abs(matrix.columns.3.w - 1) < 0.0001 else { return false }
        let x = V3(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z)
        let y = V3(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z)
        let z = V3(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z)
        let tolerance: Float = 0.005
        guard abs(simd_length(x) - 1) < tolerance, abs(simd_length(y) - 1) < tolerance,
              abs(simd_length(z) - 1) < tolerance,
              abs(simd_dot(x, y)) < tolerance, abs(simd_dot(y, z)) < tolerance,
              abs(simd_dot(z, x)) < tolerance else { return false }
        return abs(simd_determinant(simd_float3x3(columns: (x, y, z))) - 1) < tolerance
    }
}
