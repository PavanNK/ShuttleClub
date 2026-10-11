import RealityKit
import UIKit
import simd
import ShuttleCore

@MainActor extension ClubScene {
    /// A rounded, curved panel with a genuine rounded silhouette, independent
    /// of its thickness. Used for Milo's visor, armour and shoe details.
    @discardableResult static func panel(_ parent:Entity,size:SIMD2<Float>,corner:Float,depth:Float=0.025,
                                        bulge:Float=0,at position:V3,mat:any Material) -> ModelEntity {
        var edge:[SIMD2<Float>]=[]
        let radius=min(corner,min(size.x,size.y)/2),steps=12
        for quadrant in 0..<4 {
            let signX:Float=quadrant == 0 || quadrant == 3 ? 1 : -1
            let signY:Float=quadrant < 2 ? 1 : -1
            let centre=SIMD2(signX*(size.x/2-radius),signY*(size.y/2-radius))
            for index in 0..<steps {
                let angle=Float(quadrant) * .pi/2+Float(index)/Float(steps) * .pi/2
                edge.append(centre+SIMD2(cos(angle),sin(angle))*radius)
            }
        }
        var p:[V3]=[[0,0,depth/2+bulge]],n:[V3]=[[0,0,1]],uv:[SIMD2<Float>]=[[0.5,0.5]],idx:[UInt32]=[]
        let rings=6,count=edge.count
        for ring in 1...rings {
            let fraction=Float(ring)/Float(rings)
            for e in edge {
                p.append([e.x*fraction,e.y*fraction,depth/2+bulge*(1-fraction*fraction)])
                n.append(simd_normalize(V3(2*bulge*e.x*fraction/(size.x*size.x/4),2*bulge*e.y*fraction/(size.y*size.y/4),1)))
                uv.append([e.x*fraction/size.x+0.5,0.5-e.y*fraction/size.y])
            }
        }
        for i in 0..<count { idx += [0,UInt32(i+1),UInt32((i+1)%count+1)] }
        for ring in 0..<(rings-1) { for i in 0..<count {
            let a=UInt32(1+ring*count+i),b=UInt32(1+ring*count+(i+1)%count),c=a+UInt32(count),d=b+UInt32(count)
            idx += [a,c,b,b,c,d]
        } }
        var descriptor=MeshDescriptor(name:"curved rounded armour"); descriptor.positions = .init(p); descriptor.normals = .init(n)
        descriptor.textureCoordinates = .init(uv); descriptor.primitives = .triangles(idx)
        let mesh=(try? MeshResource.generate(from:[descriptor])) ?? .generateBox(size:[size.x,size.y,depth])
        let model=ModelEntity(mesh:mesh,materials:[mat]); model.position=position; parent.addChild(model); return model
    }
    static func varnish(_ color:UIColor,metal:Float=0.15,rough:Float=0.28) -> PhysicallyBasedMaterial {
        var m=material(color,metal:metal,rough:rough); m.clearcoat = .init(floatLiteral:0.7); m.clearcoatRoughness = .init(floatLiteral:0.16); return m
    }
    /// Smooth tapering armour fitted between the existing animated joints.
    @discardableResult static func taperedRod(_ parent:Entity,_ a:V3,_ b:V3,radius:Float,endRadius:Float,mat:any Material)->ModelEntity {
        let delta=b-a,length=max(0.001,simd_length(delta)),segments=24,rings=8
        var p:[V3]=[],n:[V3]=[],idx:[UInt32]=[]
        for ring in 0...rings {
            let t=Float(ring)/Float(rings),r=(radius*(1-t)+endRadius*t)*(0.92+0.08*sin(t * .pi))
            for segment in 0...segments {
                let angle=Float(segment)/Float(segments)*2 * .pi
                p.append([cos(angle)*r,(t-0.5)*length,sin(angle)*r])
                n.append(simd_normalize(V3(cos(angle),(radius-endRadius)/length,sin(angle))))
                if ring < rings && segment < segments {
                    let k=UInt32(ring*(segments+1)+segment),s=UInt32(segments+1)
                    idx += [k,k+s,k+1,k+1,k+s,k+s+1]
                }
            }
        }
        for end in 0..<2 {
            let y=(Float(end)-0.5)*length,r=(end == 0 ? radius : endRadius)*0.92
            let centre=UInt32(p.count); p.append([0,y,0]); n.append([0,end == 0 ? -1 : 1,0])
            for segment in 0...segments {
                let angle=Float(segment)/Float(segments)*2 * .pi
                p.append([cos(angle)*r,y,sin(angle)*r]); n.append([0,end == 0 ? -1 : 1,0])
                if segment < segments {
                    let first=centre+UInt32(segment)+1,next=first+1
                    idx += end == 0 ? [centre,first,next] : [centre,next,first]
                }
            }
        }
        var d=MeshDescriptor(name:"smooth fitted limb shell"); d.positions = .init(p); d.normals = .init(n); d.primitives = .triangles(idx)
        let mesh=(try? MeshResource.generate(from:[d])) ?? .generateCylinder(height:length,radius:radius)
        let e=ModelEntity(mesh:mesh,materials:[mat]); e.position=(a+b)/2
        e.orientation=simd_quatf(from:[0,1,0],to:simd_normalize(delta)); parent.addChild(e); return e
    }
    static func courtSurface() -> PhysicallyBasedMaterial {
        var m=material(teal,rough:0.62)
        if let t=texture("sunlit turquoise court",width:2048,height:2048,draw:{ c,s in
            let colours=[UIColor(red:0.055,green:0.69,blue:0.70,alpha:1).cgColor,UIColor(red:0.018,green:0.62,blue:0.65,alpha:1).cgColor] as CFArray
            if let g=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:colours,locations:[0,1]) { c.drawLinearGradient(g,start:.init(x:0,y:600),end:.init(x:2048,y:1400),options:[.drawsBeforeStartLocation,.drawsAfterEndLocation]) }
            var grain:UInt64=0xA711C09
            func sample()->CGFloat { grain=grain &* 6364136223846793005 &+ 1442695040888963407; return CGFloat((grain >> 32) & 65535)/65535 }
            for i in 0..<90000 {
                let x=sample()*s.width,y=sample()*s.height
                UIColor(white:i%3 == 0 ? 1 : 0,alpha:0.018).setFill(); c.fillEllipse(in:CGRect(x:x,y:y,width:1.4,height:1.4))
            }
            // Architectural shadows come from the scene lights rather than
            // repeating dark bands in the court's surface texture.
            UIColor.white.withAlphaComponent(0.018).setFill()
            for _ in 0..<350 { c.fillEllipse(in:CGRect(x:sample()*s.width,y:sample()*s.height,width:3,height:2)) }
        }) { m.baseColor = .init(texture:.init(t)) }
        m.clearcoat = .init(floatLiteral:0.05); m.clearcoatRoughness = .init(floatLiteral:0.44); return m
    }
    static func visorMaterial() -> PhysicallyBasedMaterial {
        var m=varnish(.init(red:0.012,green:0.039,blue:0.058,alpha:1),metal:0.42,rough:0.11)
        if let t=texture("Milo original curved visor finish",width:512,height:256,draw:{ c,s in
            let colours=[UIColor(red:0.055,green:0.11,blue:0.14,alpha:1).cgColor,UIColor(red:0.008,green:0.018,blue:0.027,alpha:1).cgColor] as CFArray
            if let g=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:colours,locations:[0,1]) { c.drawLinearGradient(g,start:.zero,end:.init(x:0,y:s.height),options:[]) }
            UIColor(red:0.64,green:0.82,blue:0.9,alpha:0.13).setStroke(); c.setLineWidth(9); c.setLineCap(.round)
            c.move(to:.init(x:75,y:57)); c.addCurve(to:.init(x:300,y:20),control1:.init(x:145,y:31),control2:.init(x:238,y:17)); c.strokePath()
            UIColor.white.withAlphaComponent(0.06).setStroke(); c.setLineWidth(4)
            c.move(to:.init(x:71,y:76)); c.addCurve(to:.init(x:213,y:46),control1:.init(x:112,y:59),control2:.init(x:164,y:43)); c.strokePath()
        }) { m.baseColor = .init(texture:.init(t)) }
        m.clearcoat = .init(floatLiteral:1); return m
    }
    static func gardenBackdrop() -> UnlitMaterial {
        var m=glow(.init(red:0.70,green:0.86,blue:0.94,alpha:1))
        if let t=texture("original garden daylight",width:1024,height:512,draw:{ c,s in
            let colours=[UIColor(red:0.69,green:0.83,blue:0.94,alpha:1).cgColor,UIColor(red:0.87,green:0.94,blue:0.87,alpha:1).cgColor,UIColor(red:0.36,green:0.56,blue:0.31,alpha:1).cgColor] as CFArray
            if let g=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:colours,locations:[0,0.68,1]) { c.drawLinearGradient(g,start:.zero,end:.init(x:0,y:s.height),options:[]) }
            // Low-contrast distant foliage, drawn locally rather than a photograph.
            for i in 0..<72 {
                let x=CGFloat((i*313)%1041)-60,y=CGFloat((i*137)%90)+330,r=CGFloat(35+(i*31)%46)
                UIColor(red:0.34+CGFloat(i%3)*0.035,green:0.54+CGFloat(i%4)*0.025,blue:0.29,alpha:0.19).setFill()
                c.fillEllipse(in:CGRect(x:x,y:y,width:r*2,height:r))
            }
        }) { m.color = .init(texture:.init(t)) }
        return m
    }
    static func addContactShadow(_ parent:Entity,size:SIMD2<Float>,at position:V3,opacity:CGFloat=0.3) {
        let format=UIGraphicsImageRendererFormat(); format.scale=1; format.opaque=false
        let im=UIGraphicsImageRenderer(size:CGSize(width:256,height:256),format:format).image { context in
            let colours=[UIColor.black.withAlphaComponent(opacity).cgColor,UIColor.clear.cgColor] as CFArray
            if let gradient=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:colours,locations:[0,1]) {
                context.cgContext.drawRadialGradient(gradient,startCenter:.init(x:128,y:128),startRadius:3,endCenter:.init(x:128,y:128),endRadius:122,options:[])
            }
        }
        guard let cg=im.cgImage,let texture=try? TextureResource(image:cg,options:.init(semantic:.color)) else { return }
        var mat=UnlitMaterial(); mat.color = .init(texture:.init(texture)); mat.blending = .transparent(opacity:.init(floatLiteral:1))
        let entity=Entity(); parent.addChild(entity); entity.name="baked soft contact shadow"
        tiledFloor(entity,size:size,repeatUV:[1,1],at:position,mat:mat)
        for child in entity.children { child.name="soft contact shadow"; child.components.set(DynamicLightShadowComponent(castsShadow:false)) }
    }
    static func bottle(_ parent:Entity,at p:V3) {
        let body=Entity(); body.position=p; parent.addChild(body)
        rod(body,[0,0,0],[0,0.25,0],0.042,varnish(.init(red:0.12,green:0.30,blue:0.37,alpha:1),metal:0.5))
        rod(body,[0,0.25,0],[0,0.29,0],0.025,material(purple))
        ring(body,rx:0.043,ry:0.043,tube:0.004,at:[0,0.08,0],mat:material(gold))?.orientation=simd_quatf(angle:.pi/2,axis:[1,0,0])
    }
    static func sportsBag(_ parent:Entity,at p:V3) {
        let bag=Entity(); bag.position=p; parent.addChild(bag)
        sphere(bag,0.30,[0,0.22,0],material(purple,rough:0.55),scale:[1.5,0.85,0.65])
        panel(bag,size:[0.72,0.32],corner:0.12,bulge:0.025,at:[0,0.22,0.18],mat:material(.init(red:0.37,green:0.14,blue:0.63,alpha:1),rough:0.65))
        let mark=Entity(); mark.position=[0,0.23,0.22]; mark.scale=[0.12,0.12,0.12]; bag.addChild(mark); shuttleLogo(mark)
        for x:Float in [-0.16,0.16] { rod(bag,[x,0.33,0.09],[x,0.62,0],0.013,material(dark)); rod(bag,[x,0.62,0],[x,0.33,-0.09],0.013,material(dark)) }
        rod(bag,[-0.27,0.4,0.08],[0.27,0.4,0.08],0.005,material(cream,metal:0.5))
    }
}

@MainActor extension ClubScene {
    static func studioLight(_ parent:Entity) {
        let image=UIGraphicsImageRenderer(size:CGSize(width:128,height:64)).image { context in
            UIColor(red:0.91,green:0.93,blue:1,alpha:1).setFill(); context.fill(CGRect(x:0,y:0,width:128,height:64))
            UIColor.white.setFill(); context.fill(CGRect(x:12,y:8,width:20,height:32))
            UIColor(red:1,green:0.78,blue:0.52,alpha:1).setFill(); context.fill(CGRect(x:98,y:15,width:20,height:32))
        }
        if let cg=image.cgImage,let env=try? EnvironmentResource(equirectangular:cg) {
            let light=Entity(); light.components.set(ImageBasedLightComponent(source:.single(env),intensityExponent:0.4)); parent.addChild(light)
            parent.components.set(ImageBasedLightReceiverComponent(imageBasedLight:light))
        }
        parent.components.set(GroundingShadowComponent(castsShadow:true))
    }
}
