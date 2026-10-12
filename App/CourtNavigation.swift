import Foundation
import simd
import ShuttleCore

enum CourtMovement: String, CaseIterable, Identifiable {
    case thumbstick, autoGlide, stationary
    var id: Self { self }
    var title: String {
        switch self {
        case .thumbstick: "Thumbstick slide"
        case .autoGlide: "Auto glide"
        case .stationary: "Stay centred"
        }
    }
    var detail: String {
        switch self {
        case .thumbstick: "Stay in place. Use the free controller's stick to move around your half."
        case .autoGlide: "Stay in place. The court glides into reach; you make every racket hit."
        case .stationary: "Stay in place. Milo aims his feeds at your current spot."
        }
    }
}

/// Horizontal virtual movement only. The room origin and tracked hand pose
/// remain physical; translating the court must never add swing velocity.
struct CourtNavigation {
    private(set) var position = SIMD2<Float>.zero // court x, z
    private(set) var velocity = SIMD2<Float>.zero
    static let speed: Float = 1.25
    static let acceleration: Float = 2.5
    static let minPosition = SIMD2<Float>(-2.35, -3.9)
    static let maxPosition = SIMD2<Float>(2.35, 0.9)

    static func direction(_ stick: SIMD2<Float>) -> SIMD2<Float> {
        guard stick.x.isFinite, stick.y.isFinite else { return .zero }
        let length = simd_length(stick)
        guard length > 0.18 else { return .zero }
        let amount = min(1, (length - 0.18) / 0.82)
        return SIMD2(stick.x, -stick.y) / length * amount
    }
    mutating func stop() { velocity = .zero }
    mutating func reset() { position = .zero; velocity = .zero }
    mutating func step(dt: Float, direction: SIMD2<Float>, allowed: Bool) {
        guard allowed, dt.isFinite, dt > 0, dt <= 0.1,
              direction.x.isFinite, direction.y.isFinite else { stop(); return }
        let length = simd_length(direction)
        let desired = direction / max(1, length) * Self.speed
        let change = desired - velocity
        let magnitude = simd_length(change)
        velocity += change / max(0.00001, magnitude) * min(magnitude, Self.acceleration * dt)
        let next = position + velocity * dt
        position = simd_clamp(next, Self.minPosition, Self.maxPosition)
        if next.x != position.x { velocity.x = 0 }
        if next.y != position.y { velocity.y = 0 }
    }
    func direction(toward target: SIMD2<Float>) -> SIMD2<Float> {
        guard target.x.isFinite, target.y.isFinite else { return .zero }
        let offset = simd_clamp(target, Self.minPosition, Self.maxPosition) - position
        let distance = simd_length(offset)
        // Slow into the destination, including a stopping distance, so hands
        // mode does not oscillate while the player prepares a swing.
        guard distance > 0.025 else { return .zero }
        let stoppingSpeed = sqrt(2 * Self.acceleration * distance)
        let approachSpeed = min(Self.speed, min(stoppingSpeed, distance * 3))
        return offset / distance * (approachSpeed / Self.speed)
    }
    static func receivingPoint(for flight: Flight, height: Float) -> V3? {
        guard flight.position.isFiniteVector, flight.velocity.isFiniteVector, height.isFinite,
              flight.velocity.z > 0 else { return nil }
        var probe = flight
        let level = min(1.85, max(1.15, height))
        for _ in 0..<384 {
            let before = probe.position
            probe.step(1 / 120)
            if probe.position.y < 0.1 { return nil }
            if before.y >= level, probe.position.y <= level, probe.position.z > Court.netZ + 0.65 {
                let fraction = (before.y - level) / max(0.00001, before.y - probe.position.y)
                return before + (probe.position - before) * fraction
            }
        }
        return nil
    }
}
