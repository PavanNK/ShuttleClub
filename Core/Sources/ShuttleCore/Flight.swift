import Foundation
import simd

public typealias V3 = SIMD3<Float>

public struct Flight: Sendable {
    public var position: V3
    public var velocity: V3
    public static let gravity: Float = 9.81
    // Quadratic drag per metre; provisional calibration gives a ~9 m/s terminal speed.
    public static let drag: Float = 0.12

    public init(position: V3, velocity: V3) { self.position = position; self.velocity = velocity }

    public mutating func step(_ duration: Float) {
        // Bounded substeps keep fast smashes and slow device frames consistent.
        guard duration.isFinite, position.isFiniteVector, velocity.isFiniteVector else { return }
        var remaining = max(0, duration)
        while remaining > 0 {
            let dt = min(remaining, 1 / 240)
            let acceleration = V3(0, -Self.gravity, 0) - velocity * (Self.drag * simd_length(velocity))
            position += velocity * dt + acceleration * (dt * dt * 0.5)
            velocity += acceleration * dt
            remaining -= dt
        }
    }

    public func advanced(_ duration: Float) -> Flight { var copy = self; copy.step(duration); return copy }

    public static func aimed(from origin: V3, to target: V3, duration: Float) -> Flight {
        let time = max(0.25, duration)
        var velocity = (target - origin) / time + V3(0, 0.5 * gravity * time, 0)
        // Solve for drag, rather than pretending the shuttle is a tennis ball.
        for _ in 0..<7 {
            let base = Flight(position: origin, velocity: velocity).advanced(time).position
            let error = target - base
            if simd_length(error) < 0.002 { break }
            let epsilon: Float = 0.03
            var jacobian = simd_float3x3()
            for axis in 0..<3 {
                var shifted = velocity; shifted[axis] += epsilon
                jacobian[axis] = (Flight(position: origin, velocity: shifted).advanced(time).position - base) / epsilon
            }
            guard abs(simd_determinant(jacobian)) > 0.00001 else { break }
            velocity += simd_inverse(jacobian) * error
        }
        return Flight(position: origin, velocity: velocity)
    }

    public static func clearanceShot(from origin: V3, to target: V3, duration: Float) -> Flight {
        var time = duration
        var shot = aimed(from: origin, to: target, duration: time)
        for _ in 0..<12 {
            var probe = shot
            var cleared = false
            for _ in 0..<600 {
                let before = probe.position; probe.step(1 / 240)
                if let height = Court.crossingHeight(from: before, to: probe.position) { cleared = height > 1.72; break }
                if probe.position.y < 0 { break }
            }
            if cleared { return shot }
            time += 0.1
            shot = aimed(from: origin, to: target, duration: time)
        }
        return shot
    }
}

public enum Side: Sendable { case player, milo
    public var other: Side { self == .player ? .milo : .player }
}

public enum Court {
    public static let netZ: Float = -5
    public static let netHeight: Float = 1.55
    public static func crossingHeight(from a: V3, to b: V3) -> Float? {
        guard (a.z > netZ && b.z <= netZ) || (a.z < netZ && b.z >= netZ) else { return nil }
        let t = (netZ - a.z) / (b.z - a.z)
        return a.y + (b.y - a.y) * t
    }
    public static func contains(_ p: V3) -> Bool { abs(p.x) <= 3.05 && p.z >= -11.7 && p.z <= 1.7 }
    public static func winner(landing: V3, lastHitter: Side) -> Side {
        guard contains(landing) else { return lastHitter.other }
        let landedOn: Side = landing.z > netZ ? .player : .milo
        // A shot landing on the hitter's own side is their fault.
        return landedOn == lastHitter ? lastHitter.other : lastHitter
    }
}

public struct MatchScore: Sendable {
    public private(set) var player = 0
    public private(set) var milo = 0
    public let goal: Int
    public init(goal: Int = 7) { self.goal = goal }
    public var winner: Side? {
        guard max(player, milo) >= goal && abs(player - milo) >= 2 else { return nil }
        return player > milo ? .player : .milo
    }
    public mutating func award(_ side: Side) { if side == .player { player += 1 } else { milo += 1 } }
}

public enum RacketContact {
    public struct Intersection: Sendable {
        public let fraction: Float
        public let point: V3
    }
    /// Continuous sphere sweep against the finite elliptical string bed.
    /// Edge contact uses the nearest point on the actual strings, not an enlarged
    /// invisible ellipse. Departing or tangential motion cannot create a rebound.
    public static func intersection(from a: V3, to b: V3, radiusX: Float = 0.137,
                                    radiusY: Float = 0.185, corkRadius: Float = 0.04) -> Intersection? {
        guard a.isFiniteVector, b.isFiniteVector, radiusX > 0, radiusY > 0, corkRadius >= 0 else { return nil }
        let travel=b-a, speed=simd_length(travel)
        guard speed > 0.000001 else { return nil }
        var t:Float=0
        for _ in 0..<80 {
            let centre=a+travel*t
            let point=nearestStringPoint(to:centre,radiusX:radiusX,radiusY:radiusY)
            let offset=centre-point, distance=simd_length(offset)
            guard simd_dot(offset,travel) < -0.0000001 else { return nil }
            if distance <= corkRadius+0.000005 {
                return Intersection(fraction:t,point:point)
            }
            // Distance to a convex surface is Lipschitz continuous. This step
            // cannot jump over a collision, even at smash speeds.
            t += (distance-corkRadius)/speed
            if t > 1 { return nil }
        }
        return nil
    }
    private static func nearestStringPoint(to centre:V3,radiusX:Float,radiusY:Float) -> V3 {
        let x=abs(centre.x),y=abs(centre.y)
        if pow(x/radiusX,2)+pow(y/radiusY,2) <= 1 { return [centre.x,centre.y,0] }
        let rx2=radiusX*radiusX,ry2=radiusY*radiusY
        var low:Float=0,high=max(radiusX*x,radiusY*y)
        for _ in 0..<32 {
            let value=(low+high)*0.5
            let ellipse=pow(radiusX*x/(value+rx2),2)+pow(radiusY*y/(value+ry2),2)
            if ellipse > 1 { low=value } else { high=value }
        }
        let value=(low+high)*0.5
        return [rx2*centre.x/(value+rx2),ry2*centre.y/(value+ry2),0]
    }
    public static func hit(from a: V3, to b: V3, radiusX: Float = 0.137, radiusY: Float = 0.185) -> V3? {
        intersection(from:a,to:b,radiusX:radiusX,radiusY:radiusY)?.point
    }
}

public enum OpponentPlan {
    /// Pick a reachable, descending contact on the opponent's half, including short drops.
    public static func interception(_ flight: Flight, maximumHeight: Float = 2.1) -> V3? {
        var probe = flight
        for _ in 0..<480 {
            probe.step(1 / 120)
            if probe.position.y < 0.35 { return nil }
            if probe.position.z < Court.netZ - 0.45 && probe.position.z > -11.7,
               probe.velocity.y < 0, probe.position.y < maximumHeight {
                return probe.position
            }
        }
        return nil
    }
}
