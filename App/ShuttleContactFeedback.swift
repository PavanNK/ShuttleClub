import RealityKit
import UIKit
import simd
import ShuttleCore

/// Reused visual feedback for a confirmed string contact. Coordinates and
/// normal are local to the supplied court root; no physical entity is moved.
@MainActor final class ShuttleContactFeedback {
    private let effect = Entity(), ring = Entity(), sparks = Entity()
    private let duration: Float = 0.15
    private var age: Float = 0.15
    private var strength: Float = 0
    var isActive: Bool { effect.isEnabled && age < duration }

    init(root: Entity) {
        effect.name = "confirmed shuttle contact"
        root.addChild(effect); effect.addChild(ring); effect.addChild(sparks)
        let mint = ClubScene.glow(UIColor(red: 0.55, green: 1, blue: 0.94, alpha: 1))
        if let rim = ClubScene.ring(ring, rx: 0.038, ry: 0.038, tube: 0.0013, at: .zero, mat: mint) {
            rim.components.set(DynamicLightShadowComponent(castsShadow: false))
        }
        let gold = ClubScene.glow(UIColor(red: 1, green: 0.83, blue: 0.40, alpha: 1))
        for index in 0..<6 {
            let angle = Float(index) * .pi / 3
            let direction = V3(cos(angle), sin(angle), 0)
            let spark = ClubScene.rod(sparks, direction * 0.041, direction * 0.054, 0.0012, gold)
            spark.components.set(DynamicLightShadowComponent(castsShadow: false))
        }
        reset()
    }

    func show(at position: V3, normal: V3, strength requested: Float) {
        let length = simd_length(normal)
        guard position.isFiniteVector, normal.isFiniteVector, length.isFinite, length > 0.0001,
              requested.isFinite else { reset(); return }
        age = 0; strength = min(1, max(0, requested))
        effect.position = position
        effect.orientation = simd_quatf(from: [0, 0, 1], to: normal / length)
        ring.scale = [1, 1, 1]; sparks.scale = [1, 1, 1]; sparks.isEnabled = true
        effect.components.set(OpacityComponent(opacity: 0.78 + strength * 0.17))
        effect.isEnabled = true
    }

    func update(dt: Float, reducedMotion: Bool) {
        guard isActive else { return }
        guard dt.isFinite, dt >= 0 else { reset(); return }
        age += dt
        guard age < duration else { reset(); return }
        let progress = age / duration
        let ringSize: Float = reducedMotion ? 1 : 1 + progress * (0.6 + strength * 0.4)
        ring.scale = SIMD3(repeating: ringSize)
        sparks.isEnabled = !reducedMotion
        sparks.scale = SIMD3(repeating: reducedMotion ? 1 : 1 + progress * 0.35)
        effect.components.set(OpacityComponent(opacity: (1 - progress) * (0.78 + strength * 0.17)))
    }

    func reset() {
        age = duration; strength = 0
        effect.isEnabled = false
        ring.scale = [1, 1, 1]; sparks.scale = [1, 1, 1]
        sparks.isEnabled = false
    }
}
