import Foundation
import simd
import ShuttleCore

/// Court faults share the same frame fraction as the swept string contact.
/// Side lines are evaluated on landing, not while the shuttle is in the air.
enum RallyEvents {
    enum Kind:Equatable,Sendable { case floor,net,out }
    struct Event:Sendable {
        let kind:Kind
        let fraction:Float
        let position:V3
    }
    static let floorHeight:Float=0.04
    static let maximumDistance:Float=35

    static func first(from start:V3,to end:V3)->Event? {
        guard start.isFiniteVector,end.isFiniteVector else { return nil }
        let travel=end-start
        var events:[Event]=[]
        if let height=Court.crossingHeight(from:start,to:end),height < Court.netHeight {
            let fraction=(Court.netZ-start.z)/travel.z
            events.append(Event(kind:.net,fraction:fraction,position:start+travel*fraction))
        }
        if start.y <= floorHeight {
            events.append(Event(kind:.floor,fraction:0,position:start))
        } else if end.y <= floorHeight {
            let fraction=(floorHeight-start.y)/travel.y
            events.append(Event(kind:.floor,fraction:fraction,position:start+travel*fraction))
        }
        let radiusSquared=maximumDistance*maximumDistance
        if simd_length_squared(start) > radiusSquared {
            events.append(Event(kind:.out,fraction:0,position:start))
        } else if simd_length_squared(end) > radiusSquared {
            // The positive root is the exit from the runaway-distance sphere.
            let a=simd_length_squared(travel),b=2*simd_dot(start,travel)
            let c=simd_length_squared(start)-radiusSquared
            if a > 0 {
                let fraction=min(1,max(0,(-b+sqrt(max(0,b*b-4*a*c)))/(2*a)))
                events.append(Event(kind:.out,fraction:fraction,position:start+travel*fraction))
            }
        }
        return events.min { $0.fraction < $1.fraction }
    }
}
