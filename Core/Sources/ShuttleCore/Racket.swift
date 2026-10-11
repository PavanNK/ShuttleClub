import Foundation
import simd

public enum RacketKind: String, CaseIterable, Identifiable, Sendable {
    case coral, mint, solar, midnight
    public var id: Self { self }
    public var name: String { switch self { case .coral: "Coral Club"; case .mint: "Mint Dash"; case .solar: "Solar Smash"; case .midnight: "Midnight Touch" } }
    public var subtitle: String { switch self { case .coral: "The club classic"; case .mint: "Quick hands. Fresh rallies."; case .solar: "Bring a little sunshine"; case .midnight: "Find your finesse" } }
    public var grams: Int { switch self { case .coral: 85; case .mint: 78; case .solar: 92; case .midnight: 82 } }
    public var balance: String { switch self { case .coral: "Even balance"; case .mint: "Head light"; case .solar: "Head heavy"; case .midnight: "Even balance" } }
    public var effectiveMass: Float { switch self { case .coral: 0.040; case .mint: 0.032; case .solar: 0.052; case .midnight: 0.036 } }
    public var restitution: Float { switch self { case .coral: 0.78; case .mint: 0.73; case .solar: 0.84; case .midnight: 0.68 } }
    public var radiusX: Float { self == .midnight ? 0.128 : 0.137 }
    public var radiusY: Float { self == .midnight ? 0.177 : 0.185 }
    public var description: String { switch self {
        case .coral: "A forgiving all-rounder in coral and violet. Start here and settle into a rhythm."
        case .mint: "A lighter frame with a softer rebound. Keep your returns compact and controlled."
        case .solar: "More effective head mass and a livelier rebound for stronger returns."
        case .midnight: "A smaller string bed and softer rebound for careful placement."
    } }
}

public enum RacketImpact {
    public static let shuttleMass: Float = 0.005
    /// A finite-mass, moving string-bed collision. All values are tuning estimates,
    /// not measurements of a commercial racket. No automatic landing correction.
    public static func rebound(incoming: V3, headVelocity: V3, normal: V3,
                               contact: V3, racket: RacketKind) -> V3? {
        guard incoming.isFiniteVector, headVelocity.isFiniteVector, normal.isFiniteVector, contact.isFiniteVector,
              simd_length(normal) > 0.001 else { return nil }
        var n = simd_normalize(normal)
        if simd_dot(headVelocity - incoming, n) < 0 { n = -n }
        let closing = simd_dot(headVelocity - incoming, n)
        guard closing > 0.15 else { return nil }
        let eccentricity = min(1, pow(contact.x / racket.radiusX, 2) + pow(contact.y / racket.radiusY, 2))
        let bounce = racket.restitution * (1 - 0.35 * eccentricity)
        let impulse = (1 + bounce) * closing / (1 + shuttleMass / racket.effectiveMass)
        let tangent = headVelocity - incoming - n * closing
        return incoming + n * impulse + tangent * 0.06
    }
}

public enum TrackingGate {
    public static func accepts(age: Double, fullPosition: Bool, speed: Float) -> Bool {
        age.isFinite && age >= -0.03 && age < 0.12 && fullPosition && speed.isFinite && speed < 45
    }
}

extension SIMD3 where Scalar == Float {
    public var isFiniteVector: Bool { x.isFinite && y.isFinite && z.isFinite }
}

public struct ButtonEdges {
    private var trigger = false
    private var menu = false
    public init() {}
    public mutating func update(trigger: Bool, menu: Bool) -> (serve: Bool, pause: Bool) {
        let edges = (trigger && !self.trigger, menu && !self.menu)
        self.trigger = trigger; self.menu = menu
        return edges
    }
}
