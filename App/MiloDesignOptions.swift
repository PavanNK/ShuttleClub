import RealityKit
import UIKit
import simd
import ShuttleCore

enum MiloDesignStyle:String,CaseIterable,Identifiable {
    case sunny,playful,sport
    var id:Self { self }
}

/// Original, full-size design candidates. The shoes sit on y = 0 and the
/// character faces +Z. These are preview rigs, separate from the rally rig.
@MainActor enum MiloDesignOptions {
    @MainActor private struct Finish {
        let orange=MiloDesignOptions.shellFinish(UIColor(red:1,green:0.40,blue:0.065,alpha:1),metal:0.06,rough:0.40,coat:0.28)
        let ivory=MiloDesignOptions.shellFinish(UIColor(red:0.88,green:0.865,blue:0.815,alpha:1),metal:0.025,rough:0.44,coat:0.14)
        let rubber=ClubScene.material(UIColor(red:0.055,green:0.075,blue:0.085,alpha:1),rough:0.65)
        let trim=ClubScene.material(UIColor(red:0.29,green:0.37,blue:0.40,alpha:1),metal:0.65,rough:0.32)
        let cyan=ClubScene.glow(UIColor(red:0.18,green:0.94,blue:1,alpha:1))
        let visor=ClubScene.visorMaterial()
    }
    private static func shellFinish(_ color:UIColor,metal:Float,rough:Float,coat:Float)->PhysicallyBasedMaterial {
        var material=ClubScene.material(color,metal:metal,rough:rough)
        material.clearcoat = .init(floatLiteral:coat)
        material.clearcoatRoughness = .init(floatLiteral:0.32)
        return material
    }
    private struct Proportions {
        let hip:Float,knee:Float,shoulder:Float,head:Float
        let torsoWidth:Float,torsoDepth:Float,stance:Float,limb:Float
        let racketGrip:V3,freeElbow:V3,freeWrist:V3
        static func forStyle(_ style:MiloDesignStyle)->Self {
            switch style {
            case .sunny:
                return .init(hip:0.73,knee:0.43,shoulder:1.14,head:1.49,
                             torsoWidth:0.255,torsoDepth:0.165,stance:0.195,limb:0.069,
                             racketGrip:[-0.43,1.02,0.20],freeElbow:[0.37,1.12,0.015],freeWrist:[0.43,1.40,0.035])
            case .playful:
                return .init(hip:0.67,knee:0.39,shoulder:1.07,head:1.385,
                             torsoWidth:0.275,torsoDepth:0.19,stance:0.22,limb:0.080,
                             racketGrip:[-0.46,0.95,0.22],freeElbow:[0.41,1.10,0.01],freeWrist:[0.49,1.35,0.04])
            case .sport:
                return .init(hip:0.79,knee:0.47,shoulder:1.25,head:1.555,
                             torsoWidth:0.225,torsoDepth:0.145,stance:0.20,limb:0.057,
                             racketGrip:[-0.45,1.115,0.23],freeElbow:[0.35,1.00,0.065],freeWrist:[0.39,0.94,0.21])
            }
        }
    }

    static func make(_ style:MiloDesignStyle)->Entity {
        let robot=Entity();robot.name="Milo design \(style.rawValue)"
        let finish=Finish(),p=Proportions.forStyle(style)
        torso(robot,style:style,p:p,finish:finish)
        legs(robot,style:style,p:p,finish:finish)
        head(robot,style:style,p:p,finish:finish)
        arms(robot,style:style,p:p,finish:finish)
        return robot
    }

    /// Optional subtle head attention and wave. The feet and racket stay still.
    static func animate(_ robot:Entity,time:Float) {
        guard time.isFinite else { return }
        robot.findEntity(named:"Milo option head")?.orientation =
            simd_quatf(angle:sin(time*0.75)*0.035,axis:[0,1,0]) *
            simd_quatf(angle:sin(time*1.15)*0.025,axis:[0,0,1])
        robot.findEntity(named:"Milo option free arm")?.orientation =
            simd_quatf(angle:sin(time*1.7)*0.045,axis:[0,0,1])
    }

    private static func torso(_ parent:Entity,style:MiloDesignStyle,p:Proportions,finish:Finish) {
        let bottom=p.hip+0.055,top=p.shoulder+0.075
        let shell:any Material=style == .sport ? finish.ivory:finish.orange
        // A shaped, closed shell narrows into the waist and shoulders instead
        // of stacking disconnected balls for the chest and hips.
        loft(parent,sections:[
            .init(y:bottom-0.015,x:0.04,z:0.035),
            .init(y:bottom+0.012,x:p.torsoWidth*0.62,z:p.torsoDepth*0.68),
            .init(y:bottom+0.07,x:p.torsoWidth*0.83,z:p.torsoDepth*0.90),
            .init(y:top-0.12,x:p.torsoWidth,z:p.torsoDepth),
            .init(y:top-0.045,x:p.torsoWidth*0.92,z:p.torsoDepth*0.88),
            .init(y:top-0.010,x:p.torsoWidth*0.68,z:p.torsoDepth*0.67),
            .init(y:top,x:0.045,z:0.035)
        ],mat:shell)
        ClubScene.sphere(parent,0.18,[0,p.hip,0],finish.rubber,scale:[1.06,0.36,0.78])
        ClubScene.sphere(parent,0.18,[0,p.hip-0.012,0.014],finish.ivory,scale:[1.12,0.44,0.77])
        ClubScene.panel(parent,size:[0.22,0.07],corner:0.025,bulge:0.015,
                        at:[0,p.hip+0.018,0.139],mat:finish.orange)
        let chestY=(bottom+top)/2+0.025
        let chest=ClubScene.panel(parent,size:style == .sport ? [0.30,0.25]:[0.345,0.235],
                                   corner:style == .sport ? 0.065:0.095,bulge:0.028,
                                   at:[0,chestY,p.torsoDepth-0.004],mat:style == .sport ? finish.orange:finish.ivory)
        chest.name="Milo curved chest shell"
        if style == .sport {
            // Two broad colour breaks read clearly at court distance.
            for side:Float in [-1,1] {
                let stripe=ClubScene.panel(parent,size:[0.035,0.19],corner:0.012,bulge:0.006,
                                            at:[side*0.194,chestY-0.02,p.torsoDepth*0.68],mat:finish.orange)
                stripe.orientation=simd_quatf(angle:side*0.28,axis:[0,0,1])
            }
        }
        let badge=Entity();badge.position=[0,chestY+0.014,p.torsoDepth+0.043];parent.addChild(badge)
        ClubScene.panel(badge,size:[0.072,0.072],corner:0.026,depth:0.004,
                        at:.zero,mat:finish.rubber)
        // A small original shuttle mark, authored from five feather strokes.
        ClubScene.sphere(badge,0.011,[0,-0.020,0.004],finish.cyan,scale:[1,1,0.24])
        for index in -2...2 {
            let x=Float(index)*0.008
            ClubScene.rod(badge,[x*0.25,-0.008,0.006],[x,0.019-abs(Float(index))*0.004,0.006],0.003,finish.cyan)
        }
        // Neck is a continuous dark flexible sleeve inside the helmet.
        ClubScene.rod(parent,[0,top-0.012,0],[0,p.head-0.145,0],0.052,finish.rubber)
        ClubScene.sphere(parent,0.061,[0,top+0.005,0],finish.ivory,scale:[1.05,0.40,1])
    }

    private static func head(_ parent:Entity,style:MiloDesignStyle,p:Proportions,finish:Finish) {
        let helmet=Entity();helmet.name="Milo option head";helmet.position=[0,p.head,0];parent.addChild(helmet)
        let visorWidth:Float,visorHeight:Float,visorZ:Float
        switch style {
        case .sunny:
            ClubScene.box(helmet,[0.515,0.425,0.375],.zero,finish.orange,round:0.14)
            ClubScene.panel(helmet,size:[0.425,0.11],corner:0.045,bulge:0.018,
                            at:[0,-0.155,0.145],mat:finish.ivory)
            visorWidth=0.427;visorHeight=0.244;visorZ=0.191
        case .playful:
            ClubScene.sphere(helmet,0.26,.zero,finish.orange,scale:[1.18,1.0,0.95])
            ClubScene.sphere(helmet,0.20,[0,-0.155,0.028],finish.ivory,scale:[1.14,0.38,0.82])
            visorWidth=0.490;visorHeight=0.278;visorZ=0.231
        case .sport:
            ClubScene.box(helmet,[0.46,0.35,0.335],.zero,finish.ivory,round:0.115)
            ClubScene.panel(helmet,size:[0.35,0.044],corner:0.018,bulge:0.006,
                            at:[0,0.125,0.143],mat:finish.orange)
            ClubScene.panel(helmet,size:[0.325,0.064],corner:0.025,bulge:0.012,
                            at:[0,-0.139,0.132],mat:finish.orange)
            visorWidth=0.385;visorHeight=0.200;visorZ=0.174
        }
        // A single slim gasket frames a continuous curved dark face.
        ClubScene.panel(helmet,size:[visorWidth+0.018,visorHeight+0.018],corner:visorHeight*0.45,
                        depth:0.014,bulge:0.018,at:[0,0.013,visorZ-0.006],mat:finish.rubber)
        ClubScene.panel(helmet,size:[visorWidth,visorHeight],corner:visorHeight*0.44,
                        depth:0.012,bulge:0.027,at:[0,0.013,visorZ],mat:finish.visor)
        // Flush side pads form a deliberate helmet silhouette without antennae
        // or exposed screws. Their front faces meet the rounded outer shell.
        let sideX:Float=style == .playful ? 0.298:style == .sport ? 0.224:0.252
        for sign:Float in [-1,1] {
            ClubScene.box(helmet,[0.065,style == .playful ? 0.135:0.125,0.155],
                          [sign*sideX,-0.002,-0.022],style == .sport ? finish.orange:finish.ivory,round:0.027)
        }
        let face=Entity();face.name="Milo option smile";face.position=[0,0.018,visorZ+0.036];helmet.addChild(face)
        let eyeX:Float=style == .playful ? 0.105:style == .sport ? 0.077:0.087
        let eyeWidth:Float=style == .playful ? 0.046:style == .sport ? 0.033:0.038
        let eyeHeight:Float=style == .playful ? 0.031:style == .sport ? 0.017:0.025
        for sign:Float in [-1,1] {
            arc(face,centre:[sign*eyeX,0.006,0],radius:[eyeWidth,eyeHeight],smile:false,thickness:0.0055,mat:finish.cyan)
        }
        arc(face,centre:[0,-0.039,0],radius:[style == .playful ? 0.047:0.036,0.019],
            smile:true,thickness:0.0038,mat:finish.cyan)
        if style == .playful {
            let cheek=ClubScene.glow(UIColor(red:1,green:0.64,blue:0.39,alpha:1))
            for sign:Float in [-1,1] {
                ClubScene.sphere(face,0.012,[sign*0.155,-0.034,-0.001],cheek,scale:[1.4,0.6,0.12])
            }
        }
    }

    private static func legs(_ parent:Entity,style:MiloDesignStyle,p:Proportions,finish:Finish) {
        for sign:Float in [-1,1] {
            let hip=V3(sign*0.115,p.hip,0),knee=V3(sign*(p.stance-0.025),p.knee,0.035)
            let ankle=V3(sign*p.stance,0.137,0.025)
            ClubScene.sphere(parent,p.limb*0.88,hip,finish.rubber)
            segment(parent,from:hip,to:knee,radius:p.limb*1.03,end:p.limb*0.91,mat:finish.ivory)
            ClubScene.sphere(parent,p.limb*0.77,knee,finish.rubber)
            ClubScene.panel(parent,size:[p.limb*1.55,p.limb*1.40],corner:p.limb*0.55,bulge:0.015,
                            at:knee+[0,0,0.062],mat:style == .sport ? finish.orange:finish.ivory)
            segment(parent,from:knee,to:ankle,radius:p.limb*0.84,end:p.limb*0.60,mat:finish.ivory)
            ClubScene.sphere(parent,p.limb*0.61,ankle,finish.rubber)
            let shoe=Entity();shoe.name="Milo floor-contact shoe";shoe.position=[sign*p.stance,0,0.08];parent.addChild(shoe)
            let width:Float=style == .playful ? 0.205:0.180
            ClubScene.box(shoe,[width,0.036,0.305],[0,0.018,0],finish.rubber,round:0.016)
            ClubScene.box(shoe,[width-0.012,0.022,0.293],[0,0.034,0],finish.ivory,round:0.010)
            ClubScene.sphere(shoe,0.10,[0,0.087,0.012],finish.ivory,
                             scale:[(width-0.02)/0.20,0.54,1.39])
            ClubScene.sphere(shoe,0.061,[0,0.104,-0.070],style == .sport ? finish.orange:finish.trim,
                             scale:[0.97,0.60,0.72])
            ClubScene.panel(shoe,size:[0.067,0.031],corner:0.010,bulge:0.002,
                            at:[sign*(width/2-0.011),0.077,0.015],mat:finish.orange).orientation =
                simd_quatf(angle:sign * .pi/2,axis:[0,1,0])
            for index in 0..<3 {
                let z=Float(index)*0.024-0.006
                func lacePoint(_ x:Float)->V3 {
                    let rx=(width-0.02)/2,rz:Float=0.139
                    let height=0.087+0.054*sqrt(max(0,1-pow(x/rx,2)-pow((z-0.012)/rz,2)))
                    return [x,height+0.002,z]
                }
                for segment in 0..<6 {
                    let x=Float(segment)*0.012-0.036
                    ClubScene.rod(shoe,lacePoint(x),lacePoint(x+0.012),0.0028,finish.trim)
                }
            }
        }
    }

    private static func arms(_ parent:Entity,style:MiloDesignStyle,p:Proportions,finish:Finish) {
        let shoulderX=p.torsoWidth-0.012
        let rightShoulder=V3(-shoulderX,p.shoulder,0)
        let racketRotation=simd_quatf(angle:style == .sport ? 0.20:0.34,axis:[0,0,1]) *
            simd_quatf(angle:0.04,axis:[1,0,0])
        let wrist=p.racketGrip+racketRotation.act(V3(0.023,-0.050,-0.008))
        let elbow=V3(-shoulderX-0.105,p.shoulder-0.185,0.065)
        arm(parent,shoulder:rightShoulder,elbow:elbow,wrist:wrist,radius:p.limb,finish:finish)
        let hand=Entity();hand.name="Milo closed racket hand";hand.position=p.racketGrip;hand.orientation=racketRotation;parent.addChild(hand)
        closedGrip(hand,finish:finish)
        let racket=ClubScene.makeRacket(style == .playful ? .mint:style == .sport ? .solar:.coral)
        racket.name="Milo actual racket at closed grip";hand.addChild(racket)

        let leftShoulder=V3(shoulderX,p.shoulder,0)
        let free=Entity();free.name="Milo option free arm";free.position=leftShoulder;parent.addChild(free)
        arm(free,shoulder:.zero,elbow:p.freeElbow-leftShoulder,wrist:p.freeWrist-leftShoulder,radius:p.limb,finish:finish)
        let palm=Entity();palm.position=p.freeWrist-leftShoulder;free.addChild(palm)
        if style == .sport { palm.orientation=simd_quatf(angle:0.70,axis:[1,0,0]) }
        openHand(palm,finish:finish,spread:style != .sport)
    }
    private static func arm(_ parent:Entity,shoulder:V3,elbow:V3,wrist:V3,radius:Float,finish:Finish) {
        ClubScene.sphere(parent,radius*0.91,shoulder,finish.rubber)
        ClubScene.sphere(parent,radius*1.06,shoulder+[0,0.008,0.006],finish.orange,scale:[1.05,0.87,1.0])
        segment(parent,from:shoulder,to:elbow,radius:radius*0.93,end:radius*0.79,mat:finish.orange)
        ClubScene.sphere(parent,radius*0.70,elbow,finish.rubber)
        segment(parent,from:elbow,to:wrist,radius:radius*0.79,end:radius*0.51,mat:finish.ivory)
        ClubScene.sphere(parent,radius*0.48,wrist,finish.rubber)
    }
    private static func segment(_ parent:Entity,from a:V3,to b:V3,radius:Float,end:Float,mat:any Material) {
        let d=simd_normalize(b-a),inset=min(0.025,simd_distance(a,b)*0.10)
        ClubScene.taperedRod(parent,a+d*inset,b-d*inset,radius:radius,endRadius:end,mat:mat)
        ClubScene.sphere(parent,radius*0.92,a+d*inset,mat)
        ClubScene.sphere(parent,end*0.92,b-d*inset,mat)
    }
    private static func closedGrip(_ parent:Entity,finish:Finish) {
        // The shaft's existing grip is centred at the hand origin. Four fingers
        // curl around its front; the thumb closes diagonally over those fingers.
        ClubScene.sphere(parent,0.03,[0.022,-0.012,-0.007],finish.ivory,scale:[0.70,1.20,0.62])
        ClubScene.sphere(parent,0.020,[0.022,-0.047,-0.007],finish.ivory,scale:[0.83,0.73,0.85])
        for index in 0..<4 {
            let y=Float(index)*0.014-0.034
            let points:[V3]=[[0.029,y,-0.004],[0.031,y,0.016],[0.005,y,0.026],[-0.019,y,0.015],[-0.017,y,-0.003]]
            for pair in 0..<(points.count-1) { ClubScene.rod(parent,points[pair],points[pair+1],0.006,finish.ivory) }
            for point in points.dropFirst().dropLast() { ClubScene.sphere(parent,0.006,point,finish.ivory) }
        }
        ClubScene.rod(parent,[0.033,0.019,-0.007],[0.020,0.025,0.018],0.009,finish.ivory)
        ClubScene.rod(parent,[0.020,0.025,0.018],[-0.006,0.011,0.026],0.008,finish.ivory)
        ClubScene.sphere(parent,0.009,[0.020,0.025,0.018],finish.ivory)
    }
    private static func openHand(_ parent:Entity,finish:Finish,spread:Bool) {
        ClubScene.sphere(parent,0.042,[0,0.034,0.004],finish.ivory,scale:[0.91,1.06,0.43])
        ClubScene.sphere(parent,0.023,.zero,finish.ivory,scale:[0.86,1.0,0.79])
        for index in 0..<4 {
            let x=(Float(index)-1.5)*0.017
            let length:Float=index == 1 || index == 2 ? 0.058:0.046
            let tip=V3(x*(spread ? 1.35:1.03),0.061+length,spread ? 0.005:0.025)
            ClubScene.rod(parent,[x,0.059,0.004],tip,0.0075,finish.ivory)
            ClubScene.sphere(parent,0.0075,tip,finish.ivory)
        }
        ClubScene.rod(parent,[-0.031,0.018,0.003],[-0.055,0.051,0.01],0.0095,finish.ivory)
        ClubScene.sphere(parent,0.0095,[-0.055,0.051,0.01],finish.ivory)
    }
    private static func arc(_ parent:Entity,centre:V3,radius:SIMD2<Float>,smile:Bool,thickness:Float,mat:any Material) {
        let count=20
        for index in 0..<count {
            let t=Float(index)/Float(count)*Float.pi,u=Float(index+1)/Float(count)*Float.pi
            let a=centre+V3(cos(t)*radius.x,sin(t)*radius.y*(smile ? -1:1),0)
            let b=centre+V3(cos(u)*radius.x,sin(u)*radius.y*(smile ? -1:1),0)
            ClubScene.rod(parent,a,b,thickness,mat)
            if index == 0 { ClubScene.sphere(parent,thickness,a,mat) }
            if index == count-1 { ClubScene.sphere(parent,thickness,b,mat) }
        }
    }
    private struct Section { let y:Float,x:Float,z:Float }
    private static func loft(_ parent:Entity,sections:[Section],mat:any Material) {
        let count=48
        var positions:[V3]=[],normals:[V3]=[],indices:[UInt32]=[]
        for (index,s) in sections.enumerated() {
            let before=sections[max(0,index-1)],after=sections[min(sections.count-1,index+1)]
            let dy=max(0.001,after.y-before.y),dx=(after.x-before.x)/dy,dz=(after.z-before.z)/dy
            for segment in 0...count {
                let angle=Float(segment)/Float(count)*2 * .pi,c=cos(angle),v=sin(angle)
                positions.append([s.x*c,s.y,s.z*v])
                normals.append(simd_normalize(V3(c/s.x,-dx/s.x*c*c-dz/s.z*v*v,v/s.z)))
                if index<sections.count-1 && segment<count {
                    let a=UInt32(index*(count+1)+segment),b=a+UInt32(count+1)
                    indices += [a,b,a+1,a+1,b,b+1]
                }
            }
        }
        for end in 0..<2 {
            let section=end == 0 ? 0:sections.count-1,centre=UInt32(positions.count)
            positions.append([0,sections[section].y,0]);normals.append([0,end == 0 ? -1:1,0])
            for segment in 0..<count {
                let a=UInt32(section*(count+1)+segment),b=a+1
                indices += end == 0 ? [centre,a,b]:[centre,b,a]
            }
        }
        var descriptor=MeshDescriptor(name:"Milo original continuous torso shell")
        descriptor.positions = .init(positions);descriptor.normals = .init(normals)
        descriptor.primitives = .triangles(indices)
        guard let mesh=try? MeshResource.generate(from:[descriptor]) else { return }
        parent.addChild(ModelEntity(mesh:mesh,materials:[mat]))
    }
}
