import Foundation
import simd

/// A rigid adjustment in the authored racket's coordinates, saved separately
/// for each Sense controller. Translation is in metres; the quaternion is xyzw.
struct SenseGripFit: Codable, Equatable, Sendable {
    var translation: SIMD3<Float> = .zero
    var calibratedOrientation: SIMD4<Float> = [0, 0, 0, 1]
    var pitchDegrees: Float = 0
    var yawDegrees: Float = 0
    var rollDegrees: Float = 0

    // OpenXR standard grip -Z follows the curled-finger tube from little finger
    // toward thumb/index. +X is palm-normal (outward for left, inward for right).
    // The authored racket's shaft is +Y and its face normal +Z. Face roll around
    // that shaft is fitted to the user's hold; this basis does not infer a hand.
    static let baseMount = simd_float4x4(columns: (
        SIMD4<Float>(0, -1, 0, 0), SIMD4<Float>(0, 0, -1, 0),
        SIMD4<Float>(1, 0, 0, 0), SIMD4<Float>(0, 0, 0, 1)))

    /// Safe for live UI edits. Invalid components fall back to zero/identity;
    /// the persistence layer rejects invalid input rather than saving it.
    func normalized() -> Self {
        var fit = self
        for index in 0..<3 {
            fit.translation[index] = Self.bounded(translation[index], limit: 0.08)
        }
        fit.calibratedOrientation = Self.unitQuaternion(calibratedOrientation) ?? [0, 0, 0, 1]
        fit.pitchDegrees = Self.bounded(pitchDegrees, limit: 90)
        fit.yawDegrees = Self.bounded(yawDegrees, limit: 90)
        fit.rollDegrees = Self.bounded(rollDegrees, limit: 90)
        return fit
    }

    /// Translation is applied in the original racket frame. Fine rotations are
    /// local to the calibrated base: pitch(+X) * roll(+Z) * yaw(+Y). Applying
    /// shaft twist first leaves the already tilted shaft direction unchanged.
    var offset: simd_float4x4 {
        let fit = normalized()
        var result = simd_float4x4(simd_quatf(vector: fit.calibratedOrientation) * fit.localEulerAdjustment)
        result.columns.3 = SIMD4<Float>(fit.translation, 1)
        return result
    }

    func mountedPose(fromGrip worldFromGrip: simd_float4x4) -> simd_float4x4 {
        worldFromGrip * Self.baseMount * offset
    }

    /// desiredOrientation and fromGrip must share a world/court frame. Solve
    /// the base rotation while preserving the chosen translation and fine trim.
    func aligned(fromGrip worldFromGrip: simd_float4x4, desiredOrientation: simd_quatf) -> Self {
        var fit = normalized()
        guard Self.isFinite(worldFromGrip),
              let desired = Self.unitQuaternion(desiredOrientation.vector) else { return fit }
        let unadjusted = simd_quatf(worldFromGrip * Self.baseMount)
        guard let source = Self.unitQuaternion(unadjusted.vector) else { return fit }
        let calibrated = simd_quatf(vector: source).inverse
            * simd_quatf(vector: desired) * fit.localEulerAdjustment.inverse
        fit.calibratedOrientation = calibrated.vector
        return fit.normalized()
    }

    /// ARKit's linear/angular velocities use the accessory anchor's local
    /// frame. Include the fitted string centre's lever arm before rotating to
    /// world space. Both transforms must use the same ARKit correction. SDK
    /// velocity does not describe any time-varying passthrough render correction;
    /// a rendered-pose finite difference is needed if that motion is required.
    static func headVelocity(worldFromAnchor: simd_float4x4, mountedPose: simd_float4x4,
                             linear: SIMD3<Float>, angular: SIMD3<Float>) -> SIMD3<Float> {
        guard isFinite(worldFromAnchor), isFinite(mountedPose),
              isFinite(linear), isFinite(angular) else { return .zero }
        let determinant = simd_determinant(worldFromAnchor)
        guard determinant.isFinite, abs(determinant) > 0.0001 else { return .zero }
        let headWorld = mountedPose * SIMD4<Float>(0, 0.37, 0, 1)
        let headLocal = xyz(simd_inverse(worldFromAnchor) * headWorld)
        let velocity = xyz(worldFromAnchor * SIMD4<Float>(linear + simd_cross(angular, headLocal), 0))
        return isFinite(velocity) ? velocity : .zero
    }

    private var localEulerAdjustment: simd_quatf {
        let radians = Float.pi / 180
        let pitch = simd_quatf(angle: pitchDegrees * radians, axis: [1, 0, 0])
        let yaw = simd_quatf(angle: yawDegrees * radians, axis: [0, 1, 0])
        let roll = simd_quatf(angle: rollDegrees * radians, axis: [0, 0, 1])
        return pitch * roll * yaw
    }

    /// Older saved fits applied twist outside the tilts. Preserve their exact
    /// mounted pose when decoding, then make subsequent twist edits shaft-local.
    private var legacyEulerAdjustment: simd_quatf {
        let radians = Float.pi / 180
        let pitch = simd_quatf(angle: pitchDegrees * radians, axis: [1, 0, 0])
        let yaw = simd_quatf(angle: yawDegrees * radians, axis: [0, 1, 0])
        let roll = simd_quatf(angle: rollDegrees * radians, axis: [0, 0, 1])
        return yaw * pitch * roll
    }

    private var hasValidData: Bool {
        Self.isFinite(translation) && Self.unitQuaternion(calibratedOrientation) != nil
            && pitchDegrees.isFinite && yawDegrees.isFinite && rollDegrees.isFinite
    }

    private static func bounded(_ value: Float, limit: Float) -> Float {
        value.isFinite ? min(limit, max(-limit, value)) : 0
    }

    private static func unitQuaternion(_ vector: SIMD4<Float>) -> SIMD4<Float>? {
        guard vector.x.isFinite, vector.y.isFinite, vector.z.isFinite, vector.w.isFinite else { return nil }
        // Scaling first avoids overflow when valid input has very large values.
        let largest = max(max(abs(vector.x), abs(vector.y)), max(abs(vector.z), abs(vector.w)))
        guard largest > 0 else { return nil }
        let scaled = vector / largest
        return scaled / simd_length(scaled)
    }

    private static func xyz(_ vector: SIMD4<Float>) -> SIMD3<Float> {
        SIMD3<Float>(vector.x, vector.y, vector.z)
    }

    private static func isFinite(_ vector: SIMD3<Float>) -> Bool {
        vector.x.isFinite && vector.y.isFinite && vector.z.isFinite
    }

    private static func isFinite(_ matrix: simd_float4x4) -> Bool {
        [matrix.columns.0, matrix.columns.1, matrix.columns.2, matrix.columns.3].allSatisfy {
            $0.x.isFinite && $0.y.isFinite && $0.z.isFinite && $0.w.isFinite
        }
    }

    private enum CodingKeys: String, CodingKey {
        case translation, calibratedOrientation, pitchDegrees, yawDegrees, rollDegrees, rotationOrderVersion
    }

    init(translation: SIMD3<Float> = .zero, calibratedOrientation: SIMD4<Float> = [0, 0, 0, 1],
         pitchDegrees: Float = 0, yawDegrees: Float = 0, rollDegrees: Float = 0) {
        self.translation = translation
        self.calibratedOrientation = calibratedOrientation
        self.pitchDegrees = pitchDegrees
        self.yawDegrees = yawDegrees
        self.rollDegrees = rollDegrees
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        translation = try values.decode(SIMD3<Float>.self, forKey: .translation)
        calibratedOrientation = try values.decode(SIMD4<Float>.self, forKey: .calibratedOrientation)
        pitchDegrees = try values.decode(Float.self, forKey: .pitchDegrees)
        yawDegrees = try values.decode(Float.self, forKey: .yawDegrees)
        rollDegrees = try values.decode(Float.self, forKey: .rollDegrees)
        let rotationOrder = try values.decodeIfPresent(Int.self, forKey: .rotationOrderVersion) ?? 1
        guard rotationOrder == 1 || rotationOrder == 2 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Unsupported Sense grip rotation order."))
        }
        guard hasValidData else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Sense grip fit requires finite values and a nonzero quaternion."))
        }
        self = normalized()
        if rotationOrder == 1 {
            let base = simd_quatf(vector: calibratedOrientation)
            calibratedOrientation = (base * legacyEulerAdjustment * localEulerAdjustment.inverse).normalized.vector
        }
    }

    func encode(to encoder: any Encoder) throws {
        guard hasValidData else {
            throw EncodingError.invalidValue(self, .init(codingPath: encoder.codingPath,
                debugDescription: "Sense grip fit requires finite values and a nonzero quaternion."))
        }
        let fit = normalized()
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(fit.translation, forKey: .translation)
        try values.encode(fit.calibratedOrientation, forKey: .calibratedOrientation)
        try values.encode(fit.pitchDegrees, forKey: .pitchDegrees)
        try values.encode(fit.yawDegrees, forKey: .yawDegrees)
        try values.encode(fit.rollDegrees, forKey: .rollDegrees)
        try values.encode(2, forKey: .rotationOrderVersion)
    }
}

enum SenseGripFitStore {
    static func load(left: Bool, defaults: UserDefaults = .standard) -> SenseGripFit {
        guard let data = defaults.data(forKey: key(left: left)),
              let fit = try? JSONDecoder().decode(SenseGripFit.self, from: data) else { return SenseGripFit() }
        return fit
    }

    /// Invalid edits leave the previous saved fit intact.
    @discardableResult
    static func save(_ fit: SenseGripFit, left: Bool, defaults: UserDefaults = .standard) -> Bool {
        guard let data = try? JSONEncoder().encode(fit) else { return false }
        defaults.set(data, forKey: key(left: left))
        return true
    }

    private static func key(left: Bool) -> String {
        "ShuttleClub.SenseGripFit.\(left ? "left" : "right").v1"
    }
}
