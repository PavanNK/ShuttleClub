import Foundation
import simd

/// A rotation in the tracked hand grip's racket frame. The quaternion is xyzw;
/// the handle remains at the tracked palm origin when this fit is applied.
struct HandGripFit: Codable, Equatable, Sendable {
    var calibratedOrientation: SIMD4<Float> = [0, 0, 0, 1]
    var tiltDegrees: Float = 0
    var sideTiltDegrees: Float = 0
    var faceTurnDegrees: Float = 0

    init(calibratedOrientation: SIMD4<Float> = [0, 0, 0, 1],
         tiltDegrees: Float = 0, sideTiltDegrees: Float = 0, faceTurnDegrees: Float = 0) {
        self.calibratedOrientation = calibratedOrientation
        self.tiltDegrees = tiltDegrees
        self.sideTiltDegrees = sideTiltDegrees
        self.faceTurnDegrees = faceTurnDegrees
    }

    /// Live invalid data safely becomes identity. Persistence rejects that data
    /// before normalization so an invalid edit cannot replace a saved fit.
    func normalized() -> Self {
        Self(calibratedOrientation: Self.unitQuaternion(calibratedOrientation) ?? [0, 0, 0, 1],
             tiltDegrees: Self.bounded(tiltDegrees, limit: 60),
             sideTiltDegrees: Self.bounded(sideTiltDegrees, limit: 45),
             faceTurnDegrees: Self.bounded(faceTurnDegrees, limit: 90))
    }

    /// Fine controls rotate the authored racket around its palm-centred handle.
    /// The local +Y shaft twist changes the face without changing shaft direction.
    var offset: simd_float4x4 {
        let fit = normalized()
        let radians = Float.pi / 180
        let tilt = simd_quatf(angle: fit.tiltDegrees * radians, axis: [1, 0, 0])
        let sideTilt = simd_quatf(angle: fit.sideTiltDegrees * radians, axis: [0, 0, 1])
        let faceTurn = simd_quatf(angle: fit.faceTurnDegrees * radians, axis: [0, 1, 0])
        return simd_float4x4(simd_quatf(vector: fit.calibratedOrientation) * tilt * sideTilt * faceTurn)
    }

    private static func bounded(_ value: Float, limit: Float) -> Float {
        value.isFinite ? min(limit, max(-limit, value)) : 0
    }

    private var hasValidData: Bool {
        Self.unitQuaternion(calibratedOrientation) != nil && tiltDegrees.isFinite
            && sideTiltDegrees.isFinite && faceTurnDegrees.isFinite
    }

    private static func unitQuaternion(_ vector: SIMD4<Float>) -> SIMD4<Float>? {
        guard vector.x.isFinite, vector.y.isFinite, vector.z.isFinite, vector.w.isFinite else { return nil }
        // Scaling before calculating length handles both very large finite
        // inputs and nonzero subnormal quaternions without overflow/underflow.
        let largest = max(max(abs(vector.x), abs(vector.y)), max(abs(vector.z), abs(vector.w)))
        guard largest > 0 else { return nil }
        let scaled = vector / largest
        return scaled / simd_length(scaled)
    }

    private enum CodingKeys: String, CodingKey {
        case calibratedOrientation, tiltDegrees, sideTiltDegrees, faceTurnDegrees
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        calibratedOrientation = try values.decode(SIMD4<Float>.self, forKey: .calibratedOrientation)
        // Existing .v1 fits contained only the base quaternion.
        tiltDegrees = try values.decodeIfPresent(Float.self, forKey: .tiltDegrees) ?? 0
        sideTiltDegrees = try values.decodeIfPresent(Float.self, forKey: .sideTiltDegrees) ?? 0
        faceTurnDegrees = try values.decodeIfPresent(Float.self, forKey: .faceTurnDegrees) ?? 0
        guard hasValidData else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Hand grip fit requires finite angles and a finite, nonzero quaternion."))
        }
        self = normalized()
    }

    func encode(to encoder: any Encoder) throws {
        guard hasValidData else {
            throw EncodingError.invalidValue(self, .init(codingPath: encoder.codingPath,
                debugDescription: "Hand grip fit requires finite angles and a finite, nonzero quaternion."))
        }
        let fit = normalized()
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(fit.calibratedOrientation, forKey: .calibratedOrientation)
        try values.encode(fit.tiltDegrees, forKey: .tiltDegrees)
        try values.encode(fit.sideTiltDegrees, forKey: .sideTiltDegrees)
        try values.encode(fit.faceTurnDegrees, forKey: .faceTurnDegrees)
    }
}

enum HandGripFitStore {
    static func load(left: Bool, defaults: UserDefaults = .standard) -> HandGripFit {
        guard let data = defaults.data(forKey: key(left: left)),
              let fit = try? JSONDecoder().decode(HandGripFit.self, from: data) else { return HandGripFit() }
        return fit
    }

    /// Invalid edits leave the previous saved fit intact.
    @discardableResult
    static func save(_ fit: HandGripFit, left: Bool, defaults: UserDefaults = .standard) -> Bool {
        guard let data = try? JSONEncoder().encode(fit) else { return false }
        defaults.set(data, forKey: key(left: left))
        return true
    }

    private static func key(left: Bool) -> String {
        "ShuttleClub.HandGripFit.\(left ? "left" : "right").v1"
    }
}
