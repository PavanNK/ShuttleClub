import RealityKit
import UIKit
import simd
import ShuttleCore

struct TargetLocation { let position: V3; let radius: Float; let value: Int }

enum MiloAnimationPhase: Equatable { case ready, preparingServe, anticipating, striking, recovering, celebrating }

@MainActor final class SceneAssets {
    let root = Entity(), racket = Entity(), shuttle = Entity(), milo = Entity(), targets = Entity(), confetti = Entity()
    let interfaceRoot = Entity()
    var targetLocations: [TargetLocation] = []
    var robotBody = Entity(), robotArm = Entity(), robotRacket = Entity(), robotFreeArm = Entity(), robotFace = Entity()
    var robotTorso = Entity(), robotHead = Entity()
    var robotHoverBase = Entity(), robotHoverGlow = Entity()
    let robotTorsoRestPosition: V3 = [0, 0.9, 0]
    let robotHoverRestPosition: V3 = [0, 0.73, 0]
    var robotReaction: Float = 0
    // Kept empty for callers inspecting the former ground-contact rig.
    var robotLegs: [Entity] = []
    var robotFeet: [Entity] = []
    var robotLegRestPositions: [V3] = []
    var movement: Float = 0
    private var hoverAmount: Float = 0

    /// Only visual joints are animated here. GameModel owns the shoulder,
    /// racket and robot root used by the actual swept string collision.
    func animateMilo(time: Float, active: Bool, dt: Float = 1 / 60,
                     reducedMotion: Bool = false, phase: MiloAnimationPhase = .ready,
                     lookTarget: V3? = nil) {
        guard time.isFinite, dt.isFinite else { return }
        let delta = min(0.1, max(0, dt))
        let reaction = max(0, min(1, robotReaction))
        robotReaction = max(0, robotReaction - delta * 1.7)
        guard !reducedMotion else {
            robotTorso.position = robotTorsoRestPosition
            robotTorso.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
            robotHead.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
            robotFreeArm.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
            robotFace.scale = [1, 1, 1]
            hoverAmount = 0
            robotHoverBase.position = robotHoverRestPosition
            robotHoverBase.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
            robotHoverGlow.scale = [1, 1, 1]
            return
        }

        let blend = 1 - exp(-delta * 12)
        let speed = movement.isFinite ? max(0, movement) : 0
        let hoverTarget = min(1, speed / 3)
        hoverAmount += (hoverTarget - hoverAmount) * blend

        var lookYaw: Float = 0
        var lookPitch: Float = 0
        if let lookTarget, lookTarget.x.isFinite, lookTarget.y.isFinite, lookTarget.z.isFinite {
            let local = milo.convert(position: lookTarget, from: root) - robotHead.convert(position: .zero, to: milo)
            lookYaw = min(0.40, max(-0.40, atan2(local.x, max(0.1, local.z))))
            lookPitch = min(0.18, max(-0.18, -atan2(local.y, max(0.2, simd_length(SIMD2(local.x, local.z))))))
        } else {
            lookYaw = sin(time * 0.7) * 0.055
        }
        let headPose = simd_quatf(angle: lookYaw, axis: [0, 1, 0]) * simd_quatf(angle: lookPitch, axis: [1, 0, 0])
        robotHead.orientation = simd_slerp(robotHead.orientation, headPose, blend)

        let readySway = active ? sin(time * 4) * 0.008 : sin(time * 1.9) * 0.012
        let hoverBob = sin(time * (active ? 3.6 : 2.4)) * (0.012 + hoverAmount * 0.008)
        let winding = phase == .preparingServe
        let striking = phase == .striking
        let recovering = phase == .recovering
        let celebrating = phase == .celebrating || reaction > 0.1
        robotTorso.position = robotTorsoRestPosition + [readySway, hoverBob + reaction * 0.014, -hoverAmount * 0.015]
        let lean: Float = (winding ? 0.035 : striking ? -0.055 : active ? -0.022 : 0) - hoverAmount * 0.11
        let bank = -lookYaw * hoverAmount * 0.32 + readySway
        let torsoPose = simd_quatf(angle: lean, axis: [1, 0, 0])
            * simd_quatf(angle: bank, axis: [0, 0, 1])
        robotTorso.orientation = simd_slerp(robotTorso.orientation, torsoPose, blend)
        // The engine and armour bank separately from the physical shoulder.
        // Neither the arm pivot nor the racket's measured strings are moved.
        robotHoverBase.position = robotHoverRestPosition + [readySway * 0.25, hoverBob * 0.8, 0]
        let enginePose = simd_quatf(angle: lean * 0.6, axis: [1, 0, 0])
            * simd_quatf(angle: bank * 0.7, axis: [0, 0, 1])
        robotHoverBase.orientation = simd_slerp(robotHoverBase.orientation, enginePose, blend)
        robotHoverGlow.scale = [1, 0.8 + hoverAmount * 0.65 + sin(time * 7) * 0.045, 1]

        // The free hand balances the body while Milo reaches and recovers.
        let freeLift: Float = celebrating ? 0.55 + reaction * 0.25 : winding ? 0.22 : striking ? 0.48 : recovering ? 0.28 : active ? 0.18 : 0.06
        let freeSwing = sin(time * 4.2) * hoverAmount * 0.10
        let freePose = simd_quatf(angle: freeLift + sin(time * 2.2) * 0.035, axis: [0, 0, 1])
            * simd_quatf(angle: freeSwing + (striking ? -0.12 : 0), axis: [1, 0, 0])
        robotFreeArm.orientation = simd_slerp(robotFreeArm.orientation, freePose, blend)
        robotFace.scale.y = 1 - 0.88 * pow(max(0, sin(time * 0.83)), 60)
    }
    func animateConfetti(age: Float) {
        for (i, e) in confetti.children.enumerated() {
            let angle = Float(i) * 2.39996, speed = 0.4 + Float(i % 5) * 0.12
            e.position = [cos(angle) * speed * age, 0.2 + (1.8 + Float(i % 3) * 0.3) * age - 2 * age * age, sin(angle) * speed * age]
            e.orientation = simd_quatf(angle: age * Float(i + 4), axis: simd_normalize(V3(1, 0.3, 0.6)))
        }
    }
}

@MainActor enum ClubScene {
    private static var textureCache: [String:TextureResource] = [:]
    // Exact dimensions are keys: no unit-mesh scaling or changed tessellation.
    // Shared resources stay immutable; each entity retains its own materials,
    // transform and parent. LRU eviction only drops our retained reference.
    private enum MeshKey: Hashable {
        case box(V3, Float), sphere(Float), cylinder(Float, Float), cone(Float, Float)
        case ring(Float, Float, Float), leafBlade, racketDecal
        case tiledFloor(SIMD2<Float>, SIMD2<Float>), mergedBoxes([V3])
        case foliage(Int), daylightSky

        var canCache: Bool {
            func positive(_ value:Float)->Bool { value.isFinite && value > 0 }
            switch self {
            case let .box(size,corner): return positive(size.x) && positive(size.y) && positive(size.z) && corner.isFinite && corner >= 0
            case let .sphere(radius): return positive(radius)
            case let .cylinder(height,radius),let .cone(height,radius): return positive(height) && positive(radius)
            case let .ring(rx,ry,tube): return positive(rx) && positive(ry) && positive(tube)
            case let .tiledFloor(size,uv): return positive(size.x) && positive(size.y) && uv.x.isFinite && uv.y.isFinite
            case let .mergedBoxes(values):
                // Zero-width string ends are intentional in the authored mesh.
                return values.count <= 2048 && values.enumerated().allSatisfy { index,value in
                    value.isFiniteVector && (index % 2 != 0 || (value.x >= 0 && value.y >= 0 && value.z >= 0))
                }
            case .leafBlade,.racketDecal,.foliage,.daylightSky: return true
            }
        }
    }
    private struct CachedMesh {
        let resource: MeshResource
        var lastUse: UInt64
    }
    private static let meshCacheCapacity = 256
    private static var meshCache: [MeshKey:CachedMesh] = [:]
    private static var meshUseClock: UInt64 = 0
    #if DEBUG
    struct MeshCacheMetrics: Equatable {
        let entries: Int
        let capacity: Int
        let hits: Int
        let generations: Int
        let evictions: Int
    }
    private static var meshHits = 0, meshGenerations = 0, meshEvictions = 0
    static var meshCacheMetrics: MeshCacheMetrics {
        .init(entries:meshCache.count,capacity:meshCacheCapacity,hits:meshHits,
              generations:meshGenerations,evictions:meshEvictions)
    }
    /// Clears only retained mesh references/counters, never a live entity.
    static func resetMeshCacheForTesting() {
        meshCache.removeAll(keepingCapacity:true);meshUseClock=0
        meshHits=0;meshGenerations=0;meshEvictions=0
    }
    #endif
    private static func cachedMesh(_ key:MeshKey,generate:() throws -> MeshResource) rethrows -> MeshResource {
        guard key.canCache else { return try generate() }
        meshUseClock &+= 1
        if var cached=meshCache[key] {
            cached.lastUse=meshUseClock;meshCache[key]=cached
            #if DEBUG
            meshHits += 1
            #endif
            return cached.resource
        }
        let resource=try generate()
        if meshCache.count >= meshCacheCapacity,
           let oldest=meshCache.min(by:{ $0.value.lastUse < $1.value.lastUse })?.key {
            meshCache.removeValue(forKey:oldest)
            #if DEBUG
            meshEvictions += 1
            #endif
        }
        meshCache[key]=CachedMesh(resource:resource,lastUse:meshUseClock)
        #if DEBUG
        meshGenerations += 1
        #endif
        return resource
    }
    static let teal = UIColor(red: 0.035, green: 0.67, blue: 0.69, alpha: 1)
    static let purple = UIColor(red: 0.36, green: 0.12, blue: 0.65, alpha: 1)
    static let coral = UIColor(red: 1, green: 0.29, blue: 0.36, alpha: 1)
    static let gold = UIColor(red: 1, green: 0.66, blue: 0.1, alpha: 1)
    static let cream = UIColor(red: 0.94, green: 0.92, blue: 0.85, alpha: 1)
    static let dark = UIColor(red: 0.055, green: 0.07, blue: 0.11, alpha: 1)
    static func material(_ color: UIColor, metal: Float = 0, rough: Float = 0.45) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial(); m.baseColor = .init(tint: color)
        m.metallic = .init(floatLiteral: metal); m.roughness = .init(floatLiteral: rough)
        return m
    }
    static func glow(_ color: UIColor) -> UnlitMaterial { UnlitMaterial(color: color) }
    @discardableResult static func box(_ parent: Entity, _ size: V3, _ position: V3, _ mat: any Material, round: Float = 0) -> ModelEntity {
        let mesh=cachedMesh(.box(size,round)) { .generateBox(size:size,cornerRadius:round) }
        let e = ModelEntity(mesh:mesh, materials: [mat]); e.position = position; parent.addChild(e); return e
    }
    @discardableResult static func sphere(_ parent: Entity, _ radius: Float, _ position: V3, _ mat: any Material, scale: V3 = [1,1,1]) -> ModelEntity {
        let mesh=cachedMesh(.sphere(radius)) { .generateSphere(radius:radius) }
        let e = ModelEntity(mesh:mesh, materials: [mat]); e.position = position; e.scale = scale; parent.addChild(e); return e
    }
    @discardableResult static func rod(_ parent: Entity, _ a: V3, _ b: V3, _ radius: Float, _ mat: any Material) -> ModelEntity {
        let d = b-a
        let height=max(0.001,simd_length(d))
        let mesh=cachedMesh(.cylinder(height,radius)) { .generateCylinder(height:height,radius:radius) }
        let e = ModelEntity(mesh:mesh, materials: [mat])
        e.position = (a+b)/2; e.orientation = simd_quatf(from: [0,1,0], to: simd_normalize(d)); parent.addChild(e); return e
    }
    @discardableResult static func ring(_ parent: Entity, rx: Float, ry: Float, tube: Float, at position: V3, mat: any Material) -> ModelEntity? {
        let mesh=try? cachedMesh(.ring(rx,ry,tube)) {
            var p: [V3] = [], n: [V3] = [], idx: [UInt32] = []
            let steps = 80, sides = 8
            for i in 0...steps {
                let a = Float(i)/Float(steps) * .pi * 2
                for j in 0...sides {
                    let b = Float(j)/Float(sides) * .pi * 2
                    let normal = V3(cos(a)*cos(b), sin(a)*cos(b), sin(b))
                    p.append(V3(rx*cos(a), ry*sin(a), 0) + normal*tube); n.append(normal)
                    if i < steps && j < sides {
                        let k = UInt32(i*(sides+1)+j), s = UInt32(sides+1)
                        idx += [k,k+1,k+s,k+1,k+s+1,k+s]
                    }
                }
            }
            var d = MeshDescriptor(name: "elliptical rim"); d.positions = .init(p); d.normals = .init(n); d.primitives = .triangles(idx)
            return try MeshResource.generate(from:[d])
        }
        if let mesh { let e = ModelEntity(mesh: mesh, materials: [mat]); e.position = position; parent.addChild(e); return e }
        return nil
    }
    static func tiledFloor(_ parent: Entity, size: SIMD2<Float>, repeatUV: SIMD2<Float>, at position: V3, mat: any Material) {
        let mesh=try? cachedMesh(.tiledFloor(size,repeatUV)) {
            let x=size.x/2,z=size.y/2
            var d=MeshDescriptor(name:"tiled floor"); d.positions = .init([[-x,0,-z],[-x,0,z],[x,0,z],[x,0,-z]])
            d.normals = .init(Array(repeating:[0,1,0],count:4)); d.textureCoordinates = .init([[0,0],[0,repeatUV.y],repeatUV,[repeatUV.x,0]])
            d.primitives = .triangles([0,1,2,0,2,3])
            return try MeshResource.generate(from:[d])
        }
        if let mesh { let e=ModelEntity(mesh:mesh,materials:[mat]); e.position=position; parent.addChild(e) }
    }
    static func texture(_ name: String, width: Int, height: Int, draw: (CGContext, CGSize) -> Void) -> TextureResource? {
        if let cached=textureCache[name] { return cached }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let size = CGSize(width: width, height: height)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { draw($0.cgContext, size) }
        guard let cg = image.cgImage else { return nil }
        let result=try? TextureResource(image:cg,withName:name,options:.init(semantic:.color))
        textureCache[name]=result; return result
    }
    static func mural() -> PhysicallyBasedMaterial {
        var m = material(coral, rough: 0.8)
        if let t = texture("club mural", width: 2048, height: 1024, draw: { c,s in
            coral.setFill(); c.fill(CGRect(origin: .zero, size: s))
            UIColor(red: 0.99, green: 0.36, blue: 0.53, alpha: 1).setFill()
            c.move(to: .init(x: 0,y: 100)); c.addLine(to: .init(x: 650,y: 1024)); c.addLine(to: .init(x: 0,y: 1024)); c.fillPath()
            gold.setFill(); c.fillEllipse(in: .init(x: 1390,y: -550,width: 1250,height: 1250))
            for (offset,color,width) in [(0.0,purple,215.0),(270.0,gold,60.0),(420.0,teal,85.0)] {
                color.setStroke(); c.setLineWidth(width); c.move(to: .init(x: 1000+offset,y: 1250)); c.addLine(to: .init(x: 2140+offset,y: 40)); c.strokePath()
            }
        }) {
            m.baseColor = .init(texture: .init(t))
            // A little reflected wall colour keeps the mural lively in shade.
            m.emissiveColor = .init(color:.white,texture:.init(t)); m.emissiveIntensity=0.12
        }
        return m
    }
    static func wood() -> PhysicallyBasedMaterial {
        var m = material(.brown, rough: 0.42)
        if let t = texture("maple planks", width: 1024, height: 1024, draw: { c,s in
            UIColor(red: 0.78,green: 0.52,blue: 0.28,alpha: 1).setFill(); c.fill(CGRect(origin:.zero,size:s))
            for row in 0..<16 {
                for col in 0..<5 {
                    let x = col*256 - (row%2)*128
                    let shade = CGFloat((row*13+col*7)%11)/100
                    UIColor(red: 0.83+shade,green: 0.60+shade,blue: 0.34+shade,alpha: 1).setFill()
                    c.fill(CGRect(x:x,y:row*64+1,width:255,height:62))
                }
                for g in 0..<8 {
                    UIColor(red:0.46,green:0.27,blue:0.12,alpha:0.15).setStroke(); c.setLineWidth(0.7)
                    c.move(to: .init(x:0,y:row*64+g*7+4)); c.addCurve(to: .init(x:1024,y:row*64+g*7+2), control1:.init(x:250,y:row*64+g*7+10), control2:.init(x:600,y:row*64+g*7-3)); c.strokePath()
                }
            }
        }) { m.baseColor = .init(texture: .init(t)) }
        return m
    }
    static func build() -> SceneAssets {
        let a = SceneAssets(), r = a.root
        r.addChild(a.interfaceRoot)
        a.interfaceRoot.name="Player interface"
        r.name = "Shuttle Club indoor court"
        let white = material(.white), steel = material(dark, metal:0.65)
        var violet = material(purple,rough:0.38)
        violet.emissiveColor = .init(color:purple); violet.emissiveIntensity=0.045
        daylightSurround(r)
        box(r,[18,0.12,24],[0,-0.09,-5],material(.brown))
        tiledFloor(r,size:[18,24],repeatUV:[3,5],at:[0,-0.025,-5],mat:wood())
        tiledFloor(r,size:[6.1,13.4],repeatUV:[1,1],at:[0,0,-5],mat:courtSurface())
        for x: Float in [-3.05,-2.59,2.59,3.05] { box(r,[0.04,0.003,13.4],[x,0.003,-5],white) }
        for z: Float in [-11.7,-10.94,-6.98,-3.02,0.94,1.7] { box(r,[6.1,0.003,0.04],[0,0.003,z],white) }
        for z: Float in [-8.86,-1.14] { box(r,[0.04,0.003,5.68],[0,0.003,z],white) }
        // An enclosed indoor club following the reference's palette and arrangement.
        box(r,[12,5.8,0.25],[0,2.9,-13.5],material(.init(white:0.3,alpha:1)))
        box(r,[10.8,4.5,0.04],[0,3.05,-13.34],mural())
        box(r,[10.8,0.85,0.06],[0,0.425,-13.3],violet)
        box(r,[0.25,5.8,24],[5.9,2.9,-5],material(.init(white:0.4,alpha:1)))
        box(r,[0.04,4.7,14],[5.76,2.8,-6],violet)
        // A complete rear wall is beyond the player's baseline and clear of
        // the rally. Turning around should still show the indoor club.
        let rearWall=box(r,[12,5.8,0.25],[0,2.9,6.875],material(cream,rough:0.78));rearWall.name="rear club wall"
        box(r,[11.8,0.85,0.06],[0,0.425,6.72],violet)
        box(r,[11.8,0.055,0.08],[0,0.875,6.7],material(gold,rough:0.45))
        for x:Float in [-5.5,5.5] { box(r,[0.16,5.5,0.24],[x,2.75,6.6],steel) }
        // Closed club entry, inset into the rear wall rather than an opening
        // onto the immersive space's empty background.
        box(r,[1.56,2.56,0.11],[3.6,1.28,6.66],steel,round:0.025)
        box(r,[1.38,2.38,0.035],[3.6,1.24,6.59],material(purple,rough:0.43),round:0.02)
        box(r,[1.10,0.50,0.015],[3.6,1.86,6.56],material(.init(red:0.64,green:0.83,blue:0.88,alpha:1),rough:0.2),round:0.018)
        rod(r,[3.08,0.91,6.52],[3.08,1.24,6.52],0.022,material(cream,metal:0.5))
        for (index,x) in [Float(-4.1),-3.3,-2.5].enumerated() {
            let lockerColor=[purple,teal,coral][index]
            box(r,[0.74,1.85,0.32],[x,0.925,6.47],material(lockerColor,metal:0.18,rough:0.4),round:0.035)
            box(r,[0.68,0.83,0.018],[x,1.38,6.30],material(lockerColor,metal:0.1,rough:0.36),round:0.018)
            box(r,[0.68,0.83,0.018],[x,0.48,6.30],material(lockerColor,metal:0.1,rough:0.36),round:0.018)
            for y:Float in [0.50,1.40] {
                rod(r,[x+0.22,y-0.04,6.27],[x+0.22,y+0.06,6.27],0.012,white)
                for vent:Float in [-0.12,-0.07,-0.02] { box(r,[0.28,0.012,0.005],[x,y+0.20+vent,6.28],steel) }
            }
        }
        box(r,[12,0.15,24],[0,5.8,-5],material(.init(white:0.27,alpha:1)))
        for z: Float in [-14,-10,-6,-2,2,6] { box(r,[12,0.25,0.3],[0,5.48,z],steel) }
        for x: Float in [-5.7,-2.8,0,2.8,5.7] { box(r,[0.2,0.3,24],[x,5.62,-5],steel) }
        // Window openings look onto a bright, layered garden; opaque frames avoid transparent overdraw.
        let gardenSky=box(r,[0.05,7.2,24],[-10.5,3.2,-5],gardenBackdrop()); gardenSky.name="gardenSky"
        for (index,z) in [Float(-14),-8.5,-2.0,4.0].enumerated() {
            let tree=Entity(); tree.position=[-8.0-Float(index%2)*0.65,0,z]; r.addChild(tree)
            let bark=material(.init(red:0.31,green:0.35,blue:0.21,alpha:1),rough:0.92)
            rod(tree,[0,0,0],[0,5.8,0],0.055,bark)
            rod(tree,[0,2.0,0],[0.18,4.3,0.8],0.028,bark)
            rod(tree,[0,2.5,0],[-0.28,5.2,-0.75],0.024,bark)
            foliage(tree,seed:Int(abs(z)*91)+5)
        }
        for z: Float in stride(from:-16,through:6,by:2.4) { box(r,[0.12,5.8,0.12],[-5.8,2.9,z],steel) }
        for y: Float in [0.3,2.75,5.5] { box(r,[0.18,0.12,24],[-5.8,y,-5],steel) }
        box(r,[0.65,0.25,24],[-5.8,0.25,-5],material(cream))
        // Close the small gap between the top window rail and the roof.
        box(r,[0.24,0.38,24],[-5.8,5.61,-5],steel)
        box(r,[0.20,5.8,0.24],[-5.8,2.9,6.65],steel)
        for x: Float in [-4.85,4.85] {
            bench(r,at:[x,0,-3],wood:wood(),metal:steel)
            bench(r,at:[x,0,-11],wood:wood(),metal:steel)
            for z: Float in [-7,-12.5,0.5] { plant(r,at:[x,0,z]) }
        }
        sportsBag(r,at:[-4.9,0,-1.3]); bottle(r,at:[-4.2,0,-1.4])
        box(r,[0.34,0.025,0.75],[-4.85,0.52,-3],white,round:0.005)
        for x:Float in [-5.5,5.5] {
            box(r,[0.16,5.5,0.24],[x,2.75,-13.1],steel)
            box(r,[0.5,0.08,0.3],[x,0.06,-13.1],steel,round:0.02)
        }
        // Net: merged wires are one mesh rather than hundreds of separately drawn entities.
        var wires: [(V3,V3)] = []
        for x: Float in stride(from:-3.05,through:3.05,by:0.07) { wires.append(([0.008,0.77,0.008],[x,1.145,-5])) }
        for y: Float in stride(from:0.77,through:1.55,by:0.065) { wires.append(([6.1,0.008,0.008],[0,y,-5])) }
        mergedBoxes(r,wires,mat:material(dark))
        box(r,[6.3,0.055,0.025],[0,1.55,-5],white)
        for x: Float in [-3.16,3.16] {
            rod(r,[x,0,-5],[x,1.66,-5],0.055,violet)
            box(r,[0.26,0.08,0.3],[x,0.04,-5],violet,round:0.02)
            sphere(r,0.056,[x,1.66,-5],violet,scale:[1,0.25,1])
        }
        // Wall badge and diagonal court stripes.
        let badge=Entity(); badge.position=[5.7,3.4,-10.7]; badge.orientation=simd_quatf(angle:-.pi/2,axis:[0,1,0]); r.addChild(badge)
        shuttleLogo(badge)
        for offset: Float in [0,0.55] { let e=box(badge,[5,0.25,0.015],[0,-1.7+offset,0],material(gold)); e.orientation=simd_quatf(angle:.pi/5,axis:[0,0,1]) }
        a.racket.addChild(makeRacket()); r.addChild(a.racket)
        makeShuttle(a.shuttle); r.addChild(a.shuttle)
        robot(a); a.milo.scale=[1.35,1.35,1.35]; r.addChild(a.milo)
        addContactShadow(a.milo,size:[0.9,0.65],at:[0,0.004,0.06],opacity:0.38)
        r.addChild(a.targets)
        a.targetLocations = [.init(position:[-1.8,0.01,-7],radius:0.6,value:30),.init(position:[0,0.01,-11],radius:0.75,value:20),.init(position:[1.8,0.01,-9.3],radius:0.65,value:40)]
        for (i,t) in a.targetLocations.enumerated() {
            let e=Entity(); e.position=t.position; e.orientation=simd_quatf(angle:-.pi/2,axis:[1,0,0]); a.targets.addChild(e)
            ring(e,rx:t.radius,ry:t.radius,tube:0.014,at:.zero,mat:glow([coral,gold,purple][i]))
            let label=ModelEntity(mesh:.generateText("\(t.value)",extrusionDepth:0.001,font:.systemFont(ofSize:0.22,weight:.bold)),materials:[glow(.white)])
            label.position=[-0.14,-0.08,0.005]; e.addChild(label)
        }
        r.addChild(a.confetti)
        for i in 0..<32 { box(a.confetti,[0.035,0.014,0.02],.zero,material([coral,gold,teal,purple][i%4])) }
        a.confetti.isEnabled=false
        lights(r)
        return a
    }
    static func mergedBoxes(_ parent: Entity, _ boxes: [(V3,V3)], mat: any Material) {
        let key=MeshKey.mergedBoxes(boxes.flatMap { [$0.0,$0.1] })
        let mesh=try? cachedMesh(key) {
            var positions: [V3]=[], normals:[V3]=[], indices:[UInt32]=[]
            let faces: [(V3,[V3])] = [([0,0,1],[[-1,-1,1],[1,-1,1],[1,1,1],[-1,1,1]]),([0,0,-1],[[1,-1,-1],[-1,-1,-1],[-1,1,-1],[1,1,-1]]),([1,0,0],[[1,-1,1],[1,-1,-1],[1,1,-1],[1,1,1]]),([-1,0,0],[[-1,-1,-1],[-1,-1,1],[-1,1,1],[-1,1,-1]]),([0,1,0],[[-1,1,1],[1,1,1],[1,1,-1],[-1,1,-1]]),([0,-1,0],[[-1,-1,-1],[1,-1,-1],[1,-1,1],[-1,-1,1]])]
            for (size,center) in boxes { for (normal,vertices) in faces { let base=UInt32(positions.count); positions += vertices.map{ center+$0*size/2 }; normals += Array(repeating:normal,count:4); indices += [base,base+1,base+2,base,base+2,base+3] } }
            var d=MeshDescriptor(name:"batched structure"); d.positions = .init(positions); d.normals = .init(normals); d.primitives = .triangles(indices)
            return try MeshResource.generate(from:[d])
        }
        if let mesh { parent.addChild(ModelEntity(mesh:mesh,materials:[mat])) }
    }
    static func makeRacket(_ kind: RacketKind = .coral) -> Entity {
        let r=Entity(), head: V3=[0,0.37,0], frame=material(kind.frameColour,metal:0.65,rough:0.2), violet=material(kind.gripColour,metal:0.45,rough:0.28)
        ring(r,rx:kind.radiusX,ry:kind.radiusY,tube:0.006,at:head,mat:frame)
        ring(r,rx:kind.radiusX-0.007,ry:kind.radiusY-0.007,tube:0.002,at:head,mat:violet)
        rod(r,[0,-0.06,0],[0,0.19,0],0.005,violet)
        rod(r,[0,-0.075,0],[0,0.065,0],0.012,material(kind.gripColour,rough:0.7))
        for i in 0..<14 { ring(r,rx:0.0125,ry:0.0125,tube:0.0015,at:[0,-0.073+Float(i)*0.01,0],mat:material(.init(red:0.67,green:0.35,blue:0.88,alpha:1)))?.orientation = simd_quatf(angle:.pi/2,axis:[1,0,0]) }
        var wires:[(V3,V3)]=[]
        for x: Float in stride(from:-0.12,through:0.12,by:0.015) { let h=(kind.radiusY-0.008)*sqrt(max(0,1-pow(x/(kind.radiusX-0.007),2))); wires.append(([0.0008,2*h,0.0008],[x,0.37,0])) }
        for y: Float in stride(from:-0.16,through:0.16,by:0.015) { let w=(kind.radiusX-0.007)*sqrt(max(0,1-pow(y/(kind.radiusY-0.008),2))); wires.append(([2*w,0.0008,0.0008],[0,0.37+y,0])) }
        mergedBoxes(r,wires,mat:material(.init(white:0.95,alpha:1),rough:0.58))
        for i in 0..<40 {
            let angle=Float(i)/40*2*Float.pi
            sphere(r,0.0025,[cos(angle)*kind.radiusX,0.37+sin(angle)*kind.radiusY,0],material(dark,rough:0.7))
        }
        for i in 0..<11 {
            rod(r,[-0.009,-0.07+Float(i)*0.012,0.009],[0.009,-0.058+Float(i)*0.012,0.009],0.0007,material(.init(white:0.83,alpha:1),rough:0.8))
        }
        let decalMaterial=material(.white)
        let decalMesh=cachedMesh(.racketDecal) {
            let source=panel(Entity(),size:[0.013,0.048],corner:0.004,depth:0.001,at:.zero,mat:decalMaterial)
            return source.model?.mesh ?? .generateBox(size:[0.013,0.048,0.001])
        }
        let decal=ModelEntity(mesh:decalMesh,materials:[decalMaterial]);decal.position=[0,0.10,0.006];r.addChild(decal)
        decal.name="original club racket decal"
        return r
    }
    static func makeShuttle(_ parent: Entity) {
        let r=Entity(); parent.addChild(r); r.position=[0,0.04,0]
        // The Flight position is the visible cork centre, not the feather base.
        sphere(r,0.025,[0,-0.025,0],material(cream),scale:[1,1,1])
        rod(r,[0,-0.013,0],[0,0.012,0],0.026,material(purple))
        for i in 0..<16 {
            let a = Float(i) * .pi / 8, base=V3(cos(a)*0.021,0.005,sin(a)*0.021), top=V3(cos(a)*0.058,0.10,sin(a)*0.058)
            rod(r,base,top,0.00065,material(cream))
            let leaf=sphere(r,0.025,(base+top)/2+[0,0.017,0],material(.init(white:0.98,alpha:1),rough:0.65),scale:[0.30,1.25,0.055])
            leaf.orientation=simd_quatf(angle:-a,axis:[0,1,0])*simd_quatf(angle:-0.23,axis:[0,0,1])
        }
        // Slightly enlarged for readable headset play while preserving the feather construction.
        r.scale=[1.6,1.6,1.6]
    }
    static func robot(_ a: SceneAssets) {
        let b=a.robotBody; a.milo.addChild(b)
        b.name="Milo physical shoulder rig"
        let torso=a.robotTorso;torso.name="Milo visual torso";b.addChild(torso)
        let head=a.robotHead;head.name="Milo head look pivot";torso.addChild(head)
        let orange=varnish(.init(red:1,green:0.43,blue:0.055,alpha:1),metal:0.18,rough:0.23)
        let ivory=varnish(.init(red:0.94,green:0.93,blue:0.87,alpha:1),metal:0.08,rough:0.28)
        let black=material(.init(red:0.024,green:0.036,blue:0.047,alpha:1),metal:0.5,rough:0.26)
        let aluminium=material(.init(white:0.63,alpha:1),metal:0.88,rough:0.28)
        let glass=visorMaterial()
        // Sculpted helmet, visor gasket and ivory jaw are separate curved shells.
        sphere(head,0.245,[0,1.43,0],orange,scale:[1.20,0.94,0.93])
        sphere(head,0.216,[0,1.29,0.035],ivory,scale:[1.28,0.30,0.85])
        panel(head,size:[0.548,0.325],corner:0.145,bulge:0.025,at:[0,1.445,0.186],mat:aluminium)
        panel(head,size:[0.525,0.307],corner:0.135,bulge:0.025,at:[0,1.445,0.199],mat:black)
        panel(head,size:[0.493,0.276],corner:0.12,bulge:0.027,at:[0,1.445,0.212],mat:glass)
        // Small trim details give the helmet a manufactured silhouette close up.
        panel(head,size:[0.10,0.030],corner:0.012,bulge:0.003,at:[0,1.667,0.055],mat:black)
        for x:Float in [-0.19,0.19] {
            panel(head,size:[0.031,0.046],corner:0.008,depth:0.004,at:[x,1.275,0.145],mat:black)
        }
        for x:Float in [-0.29,0.29] {
            let ear=Entity(); ear.position=[x,1.44,0]; ear.orientation=simd_quatf(angle:.pi/2,axis:[0,0,1]); head.addChild(ear)
            rod(ear,[0,-0.036,0],[0,0.036,0],0.079,black)
            rod(ear,[0,-0.027,0],[0,0.027,0],0.083,orange)
            rod(ear,[0,-0.043,0],[0,-0.030,0],0.056,aluminium)
            rod(head,[x,1.51,0],[x,1.65,0],0.006,aluminium)
            sphere(head,0.008,[x,1.655,0],ivory)
        }
        rod(head,[-0.15,1.642,-0.015],[0.15,1.642,-0.015],0.027,black)
        rod(head,[-0.15,1.665,-0.015],[0.15,1.665,-0.015],0.023,orange)
        let face=a.robotFace; face.position=[0,1.445,0.25]; head.addChild(face)
        for x:Float in [-0.108,0.108] {
            for j in 0..<20 {
                let t=Float(j)/20 * .pi,u=Float(j+1)/20 * .pi
                rod(face,[x+cos(t)*0.042,sin(t)*0.033,0],[x+cos(u)*0.042,sin(u)*0.033,0],0.006,glow(.init(red:0.17,green:0.94,blue:1,alpha:1)))
            }
        }
        for j in 0..<16 {
            let t=Float(j)/16 * .pi,u=Float(j+1)/16 * .pi
            rod(face,[cos(t)*0.037,-0.045-sin(t)*0.015,0.005],[cos(u)*0.037,-0.045-sin(u)*0.015,0.005],0.003,glow(.cyan))
        }
        // Move the head geometry into a pivot at the centre of the helmet.
        for child in head.children { child.position -= [0,1.43,0] }
        head.position=[0,1.43,0]
        rod(torso,[0,1.14,0],[0,1.26,0],0.058,black)
        for y:Float in [1.16,1.19,1.22] { ring(torso,rx:0.061,ry:0.061,tube:0.005,at:[0,y,0],mat:aluminium)?.orientation=simd_quatf(angle:.pi/2,axis:[1,0,0]) }
        sphere(torso,0.224,[0,0.975,0],orange,scale:[1.15,1.0,0.72])
        panel(torso,size:[0.29,0.19],corner:0.07,bulge:0.04,at:[0,1.02,0.14],mat:ivory)
        ring(torso,rx:0.040,ry:0.040,tube:0.006,at:[0,1.025,0.207],mat:aluminium)
        sphere(torso,0.032,[0,1.025,0.211],glow(.init(red:0.08,green:0.76,blue:0.86,alpha:1)),scale:[1,1,0.18])
        for i in 0..<4 { box(torso,[0.044,0.007,0.018],[Float(i)*0.054-0.081,0.89,0.148],black,round:0.003) }
        for side:Float in [-1,1] {
            panel(torso,size:[0.075,0.12],corner:0.025,bulge:0.02,at:[side*0.174,0.99,0.112],mat:ivory)
            sphere(torso,0.017,[side*0.192,1.07,0.115],aluminium,scale:[1,1,0.2])
            panel(torso,size:[0.043,0.022],corner:0.009,depth:0.006,at:[side*0.15,1.118,0.108],mat:black)
            panel(torso,size:[0.023,0.009],corner:0.004,depth:0.006,at:[side*0.15,1.118,0.118],mat:ivory)
        }
        for child in torso.children { child.position -= a.robotTorsoRestPosition }
        torso.position=a.robotTorsoRestPosition
        let hover=a.robotHoverBase;hover.name="Milo floating engine";hover.position=a.robotHoverRestPosition;b.addChild(hover)
        sphere(hover,0.174,[0,0.045,0],black,scale:[1,0.46,0.67])
        sphere(hover,0.19,[0,0,0.015],ivory,scale:[1.18,0.60,0.75])
        panel(hover,size:[0.18,0.08],corner:0.028,bulge:0.025,at:[0,0.045,0.13],mat:orange)
        ring(hover,rx:0.137,ry:0.137,tube:0.010,at:[0,-0.075,0],mat:aluminium)?.orientation=simd_quatf(angle:.pi/2,axis:[1,0,0])
        rod(hover,[0,-0.085,0],[0,-0.115,0],0.112,black)
        let thrust=a.robotHoverGlow;thrust.name="Milo hover light";thrust.position=[0,-0.13,0];hover.addChild(thrust)
        let engineLight=glow(.init(red:0.08,green:0.76,blue:0.86,alpha:1))
        let halo=ring(thrust,rx:0.097,ry:0.097,tube:0.006,at:.zero,mat:engineLight)
        halo?.orientation=simd_quatf(angle:.pi/2,axis:[1,0,0]);halo?.name="Milo hover light"
        let plume=sphere(thrust,0.095,[0,-0.025,0],engineLight,scale:[1,0.35,1]);plume.name="Milo hover light"
        for side:Float in [-1,1] {
            let shoulder=V3(side*0.25,1.07,0),elbow=V3(side*0.38,0.89,0.02),wrist=V3(side*0.40,0.80,0.18)
            let arm=side < 0 ? a.robotArm : a.robotFreeArm; arm.position=shoulder; b.addChild(arm)
            sphere(arm,0.073,.zero,black); sphere(arm,0.076,[side*0.024,0.004,0.01],orange,scale:[1.05,0.82,1])
            taperedRod(arm,[side*0.045,-0.02,0],elbow-shoulder+[0,0.03,0],radius:0.063,endRadius:0.051,mat:orange)
            sphere(arm,0.053,elbow-shoulder,black); sphere(arm,0.018,elbow-shoulder+[side*0.054,0,0],aluminium)
            taperedRod(arm,elbow-shoulder-[0,0.025,0],wrist-shoulder+[0,0.026,0],radius:0.052,endRadius:0.036,mat:ivory)
            sphere(arm,0.048,wrist-shoulder,black)
            for f in 0..<4 { let x=Float(f)*0.016-0.023
                rod(arm,wrist-shoulder+[x,-0.008,0.023],wrist-shoulder+[x,-0.046,0.029],0.008,ivory)
                sphere(arm,0.009,wrist-shoulder+[x,-0.047,0.029],ivory)
            }
            rod(arm,wrist-shoulder+[side*0.035,0.0,0.01],wrist-shoulder+[side*0.045,-0.025,0.036],0.010,ivory)
        }
        // This grip position and fixed reach are shared with the real AI sweep.
        a.robotRacket.addChild(makeRacket()); a.robotRacket.position=[-0.15,-0.27,0.18]; a.robotArm.addChild(a.robotRacket)
    }
    static func bench(_ r: Entity,at p: V3,wood: any Material,metal: any Material) {
        let e=Entity(); e.position=p; r.addChild(e)
        box(e,[0.65,0.08,2.5],[0,0.46,0],wood,round:0.015)
        for z: Float in [-0.95,0.95] { box(e,[0.5,0.4,0.06],[0,0.22,z],metal) }
    }
    static func plant(_ r: Entity,at p: V3) {
        let e=Entity(); e.position=p; r.addChild(e)
        rod(e,[0,0,0],[0,0.48,0],0.22,material(cream,rough:0.85))
        ring(e,rx:0.218,ry:0.218,tube:0.013,at:[0,0.48,0],mat:material(cream))?.orientation = simd_quatf(angle:.pi/2,axis:[1,0,0])
        sphere(e,0.208,[0,0.476,0],material(.init(red:0.14,green:0.08,blue:0.04,alpha:1)),scale:[1,0.025,1])
        var leafMaterial=material(.init(red:0.23,green:0.48,blue:0.10,alpha:1),rough:0.38)
        if let tex=texture("banana leaf veins",width:256,height:512,draw:{ c,s in
            UIColor(red:0.2,green:0.44,blue:0.08,alpha:1).setFill(); c.fill(CGRect(origin:.zero,size:s))
            UIColor(red:0.48,green:0.64,blue:0.19,alpha:0.65).setStroke(); c.setLineWidth(2)
            c.move(to:.init(x:128,y:0)); c.addLine(to:.init(x:128,y:512)); c.strokePath()
            c.setLineWidth(0.7)
            for j in stride(from:20,to:490,by:18) { c.move(to:.init(x:128,y:j)); c.addLine(to:.init(x:0,y:j+45)); c.move(to:.init(x:128,y:j)); c.addLine(to:.init(x:256,y:j+45)); c.strokePath() }
        }) { leafMaterial.baseColor = .init(texture:.init(tex)) }
        let leafMesh=leafBlade()
        for i in 0..<10 {
            let angle=Float(i)*2.4, height=0.8+Float(i%4)*0.18, end=V3(cos(angle)*0.4,height,sin(angle)*0.4)
            rod(e,[0,0.3,0],end,0.01,material(.init(red:0.16,green:0.32,blue:0.05,alpha:1)))
            if let leafMesh {
                let leaf=ModelEntity(mesh:leafMesh,materials:[leafMaterial]); leaf.position=end-[0,0.18,0]; leaf.scale=[1,0.65+Float(i%3)*0.14,1]
                leaf.orientation=simd_quatf(angle:-angle,axis:[0,1,0])*simd_quatf(angle:0.45+Float(i%2)*0.3,axis:[0,0,1]); e.addChild(leaf)
            }
        }
    }
    static func leafBlade() -> MeshResource? {
        try? cachedMesh(.leafBlade) {
            var p:[V3]=[],n:[V3]=[],uv:[SIMD2<Float>]=[],indices:[UInt32]=[]
            let rows=20, columns=6
            for row in 0...rows { for col in 0...columns {
                let t=Float(row)/Float(rows), u=Float(col)/Float(columns)*2-1, width=0.145*pow(max(0.001,sin(t * .pi)),0.75)
                p.append([u*width,t*0.65,0.08*sin(t * .pi)-0.025*u*u]); n.append(simd_normalize(V3(u*0.3,-0.25*cos(t * .pi),1))); uv.append([(u+1)/2,t])
                if row < rows && col < columns {
                    let k=UInt32(row*(columns+1)+col),s=UInt32(columns+1)
                    indices += [k,k+1,k+s,k+1,k+s+1,k+s,k,k+s,k+1,k+1,k+s,k+s+1]
                }
            } }
            var d=MeshDescriptor(name:"curved leaf blade"); d.positions = .init(p); d.normals = .init(n); d.textureCoordinates = .init(uv); d.primitives = .triangles(indices)
            return try MeshResource.generate(from:[d])
        }
    }
    static func foliage(_ parent: Entity, seed: Int) {
        let mesh=try? cachedMesh(.foliage(seed)) {
            var state=UInt64(seed+1)
            func random() -> Float { state = state &* 6364136223846793005 &+ 1; return Float((state >> 32) % 100000)/100000 }
            var positions:[V3]=[], normals:[V3]=[], indices:[UInt32]=[], faces:[UInt32]=[]
            for _ in 0..<1150 {
                let y=2.0+random()*4.7, a=random()*2*Float.pi, radius=sqrt(random())*(0.95+1.0*sin((y-2.0)/4.7 * .pi))
                let center=V3(cos(a)*radius,y,sin(a)*radius)
                let normal=simd_normalize(V3(random()-0.5,0.35+random(),random()-0.5))
                let tangent=simd_normalize(simd_cross(normal,V3(0,0,1))), other=simd_cross(normal,tangent)
                let length: Float=0.046+random()*0.056, width=length*0.52, index=UInt32(positions.count), color=UInt32(random()*4)
                positions.append(center+normal*0.018); normals.append(normal)
                for j in 0..<8 { let angle=Float(j) * .pi/4; positions.append(center+tangent*cos(angle)*length+other*sin(angle)*width); normals.append(normal) }
                for j in 0..<8 { let first=index+UInt32(j)+1,next=index+UInt32((j+1)%8)+1; indices += [index,first,next,index,next,first]; faces += [color,color] }
            }
            var d=MeshDescriptor(name:"individual garden leaves"); d.positions = .init(positions); d.normals = .init(normals); d.primitives = .triangles(indices); d.materials = .perFace(faces)
            return try MeshResource.generate(from:[d])
        }
        let mats: [any Material]=(0..<4).map{ material(UIColor(red:0.26+CGFloat($0)*0.05,green:0.49+CGFloat($0)*0.055,blue:0.14+CGFloat($0)*0.025,alpha:1),rough:0.85) }
        if let mesh { let leaves=ModelEntity(mesh:mesh,materials:mats); leaves.name="garden leaves";parent.addChild(leaves) }
    }
    static func shuttleLogo(_ r: Entity) {
        sphere(r,0.25,[0,-0.45,0],glow(.white),scale:[1,1,0.08])
        for i in -2...2 { let x=Float(i)*0.18; let e=box(r,[0.15,0.85,0.025],[x,0.14+Float(2-abs(i))*0.12,0],glow(.white),round:0.07); e.orientation=simd_quatf(angle:-Float(i)*0.16,axis:[0,0,1]) }
    }
    static func daylightSurround(_ r: Entity) {
        var sky = glow(.init(red:0.70,green:0.86,blue:0.94,alpha:1))
        if let image = texture("original continuous daylight sky",width:1024,height:512,draw:{ context,size in
            let colors=[UIColor(red:0.54,green:0.77,blue:0.95,alpha:1).cgColor,
                        UIColor(red:0.83,green:0.92,blue:0.96,alpha:1).cgColor,
                        UIColor(red:0.88,green:0.94,blue:0.87,alpha:1).cgColor,
                        UIColor(red:0.50,green:0.67,blue:0.43,alpha:1).cgColor] as CFArray
            if let gradient=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:colors,locations:[0,0.44,0.56,1]) {
                context.drawLinearGradient(gradient,start:.zero,end:CGPoint(x:0,y:size.height),options:[])
            }
        }) { sky.color = .init(texture:.init(image)) }

        // Explicit inward triangles keep the entire outdoor background visible
        // from inside. It sits beyond the club and cannot obstruct play.
        let mesh=try? cachedMesh(.daylightSky) {
            let rows=32,columns=64,radius:Float=40
            var positions:[V3]=[],normals:[V3]=[],uv:[SIMD2<Float>]=[],indices:[UInt32]=[]
            for row in 0...rows { for column in 0...columns {
                let v=Float(row)/Float(rows),u=Float(column)/Float(columns)
                let latitude=v * .pi,longitude=u * .pi * 2
                let normal=V3(sin(latitude)*cos(longitude),cos(latitude),sin(latitude)*sin(longitude))
                positions.append(normal*radius);normals.append(-normal);uv.append([u,v])
                if row < rows && column < columns {
                    let index=UInt32(row*(columns+1)+column),nextRow=UInt32(columns+1)
                    indices += [index,index+nextRow,index+1,index+1,index+nextRow,index+nextRow+1]
                }
            } }
            var descriptor=MeshDescriptor(name:"continuous inward daylight sky")
            descriptor.positions = .init(positions);descriptor.normals = .init(normals)
            descriptor.textureCoordinates = .init(uv);descriptor.primitives = .triangles(indices)
            return try MeshResource.generate(from:[descriptor])
        }
        if let mesh {
            let surround=ModelEntity(mesh:mesh,materials:[sky]);surround.name="daylight sky surround"
            surround.position=[0,3,0];surround.components.set(DynamicLightShadowComponent(castsShadow:false));r.addChild(surround)
        }
        let lawn=box(r,[28,0.04,32],[-20,-0.02,-4],material(.init(red:0.32,green:0.52,blue:0.24,alpha:1),rough:1))
        lawn.name="exterior garden ground"
    }
    static func lights(_ r: Entity) {
        func enableShadows(_ entity: Entity) {
            if entity.components[ModelComponent.self] != nil { entity.components.set(DynamicLightShadowComponent(castsShadow:entity.name != "gardenSky" && entity.name != "daylight sky surround" && entity.name != "garden leaves" && entity.name != "soft contact shadow" && entity.name != "Milo hover light")) }
            for child in entity.children { enableShadows(child) }
        }
        enableShadows(r)
        let image=UIGraphicsImageRenderer(size:CGSize(width:512,height:256)).image { context in
            let c=context.cgContext
            let colors=[UIColor(white:0.92,alpha:1).cgColor,UIColor(red:0.68,green:0.77,blue:0.85,alpha:1).cgColor,UIColor(red:0.38,green:0.28,blue:0.21,alpha:1).cgColor] as CFArray
            if let g=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:colors,locations:[0,0.55,1]) { c.drawLinearGradient(g,start:.zero,end:CGPoint(x:0,y:256),options:[]) }
            UIColor.white.setFill(); c.fillEllipse(in:CGRect(x:35,y:45,width:100,height:70))
        }
        if let cg=image.cgImage,let env=try? EnvironmentResource(equirectangular:cg) {
            let light=Entity(); light.components.set(ImageBasedLightComponent(source:.single(env),intensityExponent:0.45)); r.addChild(light)
            r.components.set(ImageBasedLightReceiverComponent(imageBasedLight:light))
        }
        let sun=DirectionalLight(); sun.light.color = .init(red:1,green:0.94,blue:0.85,alpha:1); sun.light.intensity=17000
        sun.shadow = .init(shadowProjection:.automatic(maximumDistance:18),depthBias:0.025)
        sun.orientation=simd_quatf(from:[0,0,-1],to:simd_normalize(V3(0.95,-0.45,-0.35))); r.addChild(sun)
        let fill=DirectionalLight(); fill.name="soft front bounce"
        fill.light.color = .init(red:0.88,green:0.96,blue:1,alpha:1); fill.light.intensity=5000
        fill.orientation=simd_quatf(from:[0,0,-1],to:simd_normalize(V3(-0.1,-0.65,-1)))
        r.addChild(fill)
        for x: Float in [-3.8,0,3.8] { for z: Float in [-10,-2] {
            rod(r,[x,5.5,z],[x,5.0,z],0.02,material(dark))
            let lampMesh=cachedMesh(.cone(0.18,0.16)) { .generateCone(height:0.18,radius:0.16) }
            let lamp=ModelEntity(mesh:lampMesh,materials:[material(dark,metal:0.4)]); lamp.position=[x,4.95,z]; r.addChild(lamp)
            sphere(r,0.13,[x,4.87,z],glow(.init(red:1,green:0.92,blue:0.72,alpha:1)),scale:[1,0.2,1])
        } }
    }
}
