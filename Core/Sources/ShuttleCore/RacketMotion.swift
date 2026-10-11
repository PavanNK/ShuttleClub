import Foundation
import simd

/// Motion helpers use the measured pose acquisition interval. Repeating an
/// anchor or establishing a new grip must supply zero angular velocity.
public enum RacketMotion {
    public static func angularVelocity(from oldPose: simd_float4x4, to newPose: simd_float4x4,
                                       duration: Float) -> V3 {
        guard duration.isFinite, duration > 0,
              let old = RacketSweepPose(oldPose), let new = RacketSweepPose(newPose) else { return .zero }
        return rotationVector(from: old.rotation, to: new.rotation) / duration
    }

    /// Contact is measured from the string centre in racket coordinates.
    /// Invalid components propagate to the impact solver's finite-value gate.
    public static func pointVelocity(headVelocity: V3, angularVelocity: V3,
                                     pose: simd_float4x4, contact: V3) -> V3 {
        let lever = (pose * SIMD4<Float>(contact, 0)).xyz
        return headVelocity + simd_cross(angularVelocity, lever)
    }

    fileprivate static func rotationVector(from old: simd_quatf, to new: simd_quatf) -> V3 {
        var delta = (new * old.inverse).normalized
        if delta.real < 0 { delta = simd_quatf(vector: -delta.vector) }
        let length = simd_length(delta.imag)
        guard length > 0.0000001 else { return .zero }
        let angle = 2 * atan2(length, max(0, delta.real))
        return delta.imag * (angle / length)
    }
}

/// Sweeps a cork against the actual interpolated world-space string bed.
/// Interpolating local endpoint coordinates would shrink a rotating arc into
/// a chord and could manufacture contacts outside the visible strings.
public enum RacketSweep {
    public struct Contact: Sendable {
        public let fraction: Float
        /// Point on the finite strings, relative to their centre.
        public let point: V3
        public let cork: V3
        public let stringPoint: V3
        public let pose: simd_float4x4
    }

    public static func intersection(from corkFrom: V3, to corkTo: V3,
                                    oldPose: simd_float4x4, newPose: simd_float4x4,
                                    radiusX: Float = 0.137, radiusY: Float = 0.185,
                                    corkRadius: Float = 0.04) -> Contact? {
        guard corkFrom.isFiniteVector, corkTo.isFiniteVector,
              radiusX.isFinite, radiusY.isFinite, corkRadius.isFinite,
              radiusX > 0, radiusY > 0, corkRadius >= 0,
              let old = RacketSweepPose(oldPose), let new = RacketSweepPose(newPose) else { return nil }
        let headLocal = V3(0, 0.37, 0)
        let corkTravel = corkTo - corkFrom
        let translationTravel = new.position - old.position
        let rotationTravel = RacketMotion.rotationVector(from: old.rotation, to: new.rotation)
        let angle = simd_length(rotationTravel)
        let scaleTravel = new.scale - old.scale
        let maxScale = max(old.scale, new.scale)
        let bedRadius = max(radiusX, radiusY)
        // The distance to a moving surface is Lipschitz continuous. This bound
        // includes translation, the head offset and every point in the bed.
        let rotationalTravel = simd_length(simd_cross(rotationTravel, old.rotation.act(headLocal)))
            + angle * bedRadius
        let motionBound = simd_length(corkTravel - translationTravel)
            + rotationalTravel * maxScale + abs(scaleTravel) * (0.37 + bedRadius)
        guard motionBound.isFinite, motionBound > 0.0000001 else { return nil }
        let segments = max(1, min(36, Int(ceil(angle / (Float.pi / 36)))))
        let tolerance: Float = 0.000005

        func state(at fraction: Float) -> (Contact, Float, Float) {
            let rotation = simd_slerp(old.rotation, new.rotation, fraction)
            let scale = old.scale + scaleTravel * fraction
            let position = old.position + translationTravel * fraction
            let cork = corkFrom + corkTravel * fraction
            let local = rotation.inverse.act((cork - position) / scale) - headLocal
            let point = RacketContact.nearestStringPoint(to: local, radiusX: radiusX, radiusY: radiusY)
            let localFromHandle = point + headLocal
            let lever = rotation.act(localFromHandle * scale)
            let stringPoint = position + lever
            let offset = cork - stringPoint
            let surfaceTravel = translationTravel + simd_cross(rotationTravel, lever)
                + rotation.act(localFromHandle) * scaleTravel
            let approach = simd_dot(offset, corkTravel - surfaceTravel)
            var pose = simd_float4x4(rotation)
            pose.columns.0 *= scale; pose.columns.1 *= scale; pose.columns.2 *= scale
            pose.columns.3 = SIMD4<Float>(position, 1)
            return (Contact(fraction: fraction, point: point, cork: cork,
                            stringPoint: stringPoint, pose: pose), simd_length(offset), approach)
        }

        // With a fixed orientation and scale, local interpolation is exact.
        // Reuse the established linear solver instead of angular refinement.
        if angle < 0.0000001 && abs(scaleTravel) < 0.0000001 {
            let a = old.rotation.inverse.act((corkFrom - old.position) / old.scale) - headLocal
            let b = old.rotation.inverse.act((corkTo - new.position) / old.scale) - headLocal
            guard let hit = RacketContact.intersection(from: a, to: b, radiusX: radiusX,
                radiusY: radiusY, corkRadius: corkRadius / old.scale) else { return nil }
            let (contact, distance, _) = state(at: hit.fraction)
            if distance <= corkRadius + tolerance { return contact }
            // A scaled solver tolerance can exceed the world-space tolerance;
            // refine rather than accepting the larger reconstructed distance.
        }

        for segment in 0..<segments {
            let lower = Float(segment) / Float(segments)
            let upper = Float(segment + 1) / Float(segments)
            var fraction = lower
            var previousDistance = Float.infinity
            // Exact world-space distance is evaluated at every step. Bounded
            // angular intervals limit both work and grazing-contact refinement.
            for _ in 0..<64 {
                let (contact, distance, approach) = state(at: fraction)
                if distance <= corkRadius + tolerance {
                    let approaching = approach < -0.000000001
                        || (distance < tolerance && previousDistance.isFinite && previousDistance > distance + tolerance)
                    if approaching { return contact }
                    // A departing fixed surface cannot become a later collision
                    // on this linear path. A rotating surface can turn back.
                    if angle < 0.0000001 && abs(scaleTravel) < 0.0000001 { return nil }
                    if fraction >= upper { break }
                    previousDistance = distance
                    fraction = min(upper, fraction + (upper - lower) / 16)
                    continue
                }
                let separation = distance - corkRadius
                if separation > motionBound * (upper - fraction) + tolerance { break }
                if fraction >= upper { break }
                previousDistance = distance
                let advance = separation / motionBound
                let next = min(upper, fraction + advance)
                if next <= fraction { break }
                fraction = next
            }
        }
        return nil
    }
}

/// A uniformly scaled rigid pose. Rackets use scale1 for the player and a
/// constant authored model scale for Milo; sheared or singular poses are invalid.
private struct RacketSweepPose {
    let position: V3
    let rotation: simd_quatf
    let scale: Float

    init?(_ matrix: simd_float4x4) {
        guard [matrix.columns.0, matrix.columns.1, matrix.columns.2, matrix.columns.3].allSatisfy({
            $0.x.isFinite && $0.y.isFinite && $0.z.isFinite && $0.w.isFinite
        }), abs(matrix.columns.0.w) < 0.0001, abs(matrix.columns.1.w) < 0.0001,
            abs(matrix.columns.2.w) < 0.0001, abs(matrix.columns.3.w - 1) < 0.0001 else { return nil }
        let lengths = V3(simd_length(matrix.columns.0.xyz), simd_length(matrix.columns.1.xyz),
                         simd_length(matrix.columns.2.xyz))
        let scale = lengths.x
        guard scale.isFinite, scale > 0.0001,
              abs(lengths.y - scale) < scale * 0.005,
              abs(lengths.z - scale) < scale * 0.005 else { return nil }
        let x = matrix.columns.0.xyz / scale, y = matrix.columns.1.xyz / scale,
            z = matrix.columns.2.xyz / scale
        let basis = simd_float3x3(columns: (x, y, z))
        guard abs(simd_dot(x, y)) < 0.005, abs(simd_dot(y, z)) < 0.005,
              abs(simd_dot(z, x)) < 0.005, abs(simd_determinant(basis) - 1) < 0.01 else { return nil }
        position = matrix.columns.3.xyz
        rotation = simd_quatf(basis).normalized
        self.scale = scale
    }
}

private extension SIMD4 where Scalar == Float {
    var xyz: V3 { [x, y, z] }
}
