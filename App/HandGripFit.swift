import Foundation
import simd

/// A rotation in the tracked hand grip's racket frame. The quaternion is xyzw;
/// the handle remains at the tracked palm origin when this fit is applied.
struct HandGripFit: Codable, Equatable, Sendable {
    var calibratedOrientation: SIMD4<Float> = [0, 0, 0, 1]

    init(calibratedOrientation: SIMD4<Float> = [0, 0, 0, 1]) {
        self.calibratedOrientation = calibratedOrientation
    }

    /// Live invalid data safely becomes identity. Persistence rejects that data
    /// before normalization so an invalid edit cannot replace a saved fit.
    func normalized() -> Self {
        Self(calibratedOrientation: Self.unitQuaternion(calibratedOrientation) ?? [0, 0, 0, 1])
    }

    var offset: simd_float4x4 {
        simd_float4x4(simd_quatf(vector: normalized().calibratedOrientation))
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
        case calibratedOrientation
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let orientation = try values.decode(SIMD4<Float>.self, forKey: .calibratedOrientation)
        guard let unit = Self.unitQuaternion(orientation) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Hand grip fit requires a finite, nonzero quaternion."))
        }
        calibratedOrientation = unit
    }

    func encode(to encoder: any Encoder) throws {
        guard let unit = Self.unitQuaternion(calibratedOrientation) else {
            throw EncodingError.invalidValue(self, .init(codingPath: encoder.codingPath,
                debugDescription: "Hand grip fit requires a finite, nonzero quaternion."))
        }
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(unit, forKey: .calibratedOrientation)
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
