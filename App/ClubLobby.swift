import SwiftUI
import RealityKit
import ShuttleCore

/// Menu objects are decorative. Rally physics only runs in CourtView.
@MainActor @Observable final class ClubLobbyScene {
    let assets=ClubScene.build()
    var subscription:EventSubscription?
    var clock:Float=0
    var displayedKind:RacketKind?
    var rackets:[RacketKind:Entity]=[:]
    var platforms:[RacketKind:ModelEntity]=[:]
    let floatingShuttle=Entity()
    var reportedReady=false

    func attach(_ content:RealityViewContent,attachments:RealityViewAttachments,game:GameModel,onReady:@escaping @MainActor ()->Void) {
        let root=assets.root
        assets.racket.isEnabled=false;assets.shuttle.isEnabled=false;assets.targets.isEnabled=false
        assets.milo.position=[0.4,0,-8]
        assets.milo.scale=[1.2,1.2,1.2]
        assets.milo.orientation=simd_quatf(angle:-0.12,axis:[0,1,0])
        for kind in RacketKind.allCases {
            let racket=ClubScene.makeRacket(kind);racket.name="menu-racket-\(kind.rawValue)"
            racket.position=[0.75,0.43,-2.5];racket.scale=[3.3,3.3,3.3]
            root.addChild(racket);rackets[kind]=racket
        }
        ClubScene.makeShuttle(floatingShuttle);floatingShuttle.scale=[2.5,2.5,2.5]
        floatingShuttle.position=[-1.35,2.43,-4.6];root.addChild(floatingShuttle)
        content.add(root);select(game.racketKind)
        subscription=content.subscribe(to:SceneEvents.Update.self) { [weak self] event in
            let delta=Float(event.deltaTime)
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !reportedReady { reportedReady=true;onReady() }
                clock += min(delta,0.05)
                assets.animateMilo(time:clock,active:false,dt:delta,reducedMotion:game.reducedMotion)
                if !game.reducedMotion {
                    assets.robotFreeArm.orientation=simd_quatf(angle:2.4+sin(clock*3.4)*0.15,axis:[0,0,1])
                    assets.robotArm.orientation=simd_quatf(angle:sin(clock*1.4)*0.09,axis:[0,0,1])
                    floatingShuttle.position.y=2.43+sin(clock*1.6)*0.04
                    floatingShuttle.orientation=simd_quatf(angle:-0.4,axis:[0,0,1])*simd_quatf(angle:clock*0.24,axis:[0,1,0])
                }
                for (kind,racket) in rackets {
                    guard racket.isEnabled else { continue }
                    let selected=kind == game.racketKind
                    racket.position.y=0.43+(game.reducedMotion ? 0:sin(clock*2.2)*0.009)
                    racket.orientation=simd_quatf(angle:-0.35,axis:[0,0,1])*simd_quatf(angle:selected && !game.reducedMotion ? 0.08+sin(clock*0.85)*0.025:0.08,axis:[0,1,0])
                }
            }
        }
    }
    func place(_ attachments:RealityViewAttachments,style:ClubHomeStyle,presentingPanel:Bool,rackets:Bool) {
        func place(_ id:String,at position:SIMD3<Float>,scale:Float,visible:Bool) {
            guard let entity=attachments.entity(for:id) else { return }
            if entity.parent !== assets.root { assets.root.addChild(entity) }
            entity.position=position;entity.scale=[scale,scale,scale];entity.isEnabled=visible
        }
        place("homeTitle",at:[0,3.54,-4.3],scale:8.5,visible:!presentingPanel && style == .minimal)
        place("homeActions",at:[0,0.7,-2.55],scale:4.0,visible:!presentingPanel && style == .minimal)
        place("homePoster",at:[-2.38,1.83,-3.5],scale:6.0,visible:!presentingPanel && style == .playful)
        place("homeWelcome",at:[0,3.66,-4.3],scale:6.1,visible:!presentingPanel && style == .playful)
        place("homeGear",at:[2.65,3.02,-3.0],scale:3.5,visible:!presentingPanel && style == .playful)
        place("homeShade",at:[0,1.6,-4.4],scale:7.4,visible:!presentingPanel)
        place("panelShade",at:[0,1.6,-2.9],scale:4.8,visible:presentingPanel && rackets)
        place("main",at:[0,rackets ? 1.7:1.83,-2.8],scale:rackets ? 4.7:3.0,visible:presentingPanel)
        for (kind,entity) in self.rackets { entity.isEnabled = !presentingPanel && kind == displayedKind }
        for (kind,entity) in platforms { entity.isEnabled = !presentingPanel && kind == displayedKind }
        assets.milo.isEnabled = !presentingPanel
        floatingShuttle.isEnabled = !presentingPanel
    }
    func select(_ kind:RacketKind) {
        guard displayedKind != kind else { return };displayedKind=kind
        for (key,platform) in platforms { platform.isEnabled=key == kind;platform.scale=[1.10,1.6,1.10] }
        for (key,racket) in rackets { racket.isEnabled=key == kind }
    }
}

struct ClubLobby:View {
    @Environment(GameModel.self) private var game
    @Environment(ClubNavigation.self) private var navigation
    @AppStorage("clubHomeStyle") private var storedStyle=ClubHomeStyle.minimal.rawValue
    @State private var scene=ClubLobbyScene()
    @State private var setup=false
    @State private var choosingMode=false
    @State private var homeSettings=false
    @State private var opening=false
    var onReady:@MainActor ()->Void = {}
    private var presentingPanel:Bool { setup || choosingMode || homeSettings || game.showRackets || game.showSettings }
    private var modeTitle:String { game.mode == .practice ? "Free play":game.mode == .match ? "Quick match":"Target rush" }
    private var homeStyle:ClubHomeStyle {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-home-poster") { return .playful }
        #endif
        return ClubHomeStyle(rawValue:storedStyle) ?? .minimal
    }
    var body:some View {
        RealityView { content,attachments in
            scene.attach(content,attachments:attachments,game:game,onReady:onReady)
            scene.place(attachments,style:homeStyle,presentingPanel:presentingPanel,rackets:game.showRackets)
        } update: { _,attachments in
            scene.select(game.racketKind)
            scene.place(attachments,style:homeStyle,presentingPanel:presentingPanel,rackets:game.showRackets)
        } attachments: {
            Attachment(id:"homeTitle") { ClubHeroWordmark() }
            Attachment(id:"homeWelcome") { ClubWelcomeWordmark() }
            Attachment(id:"homeGear") { ClubHomeGear(onSettings:openSettings) }
            Attachment(id:"homeShade") {
                Group {
                    if homeStyle == .playful {
                        LinearGradient(colors:[Color.clubInk.opacity(0.72),Color.clubInk.opacity(0.27),.clear],startPoint:.leading,endPoint:.trailing)
                    } else {
                        LinearGradient(colors:[.clear,.clear,Color.clubInk.opacity(0.3)],startPoint:.top,endPoint:.bottom)
                    }
                }.frame(width:1920,height:1080).allowsHitTesting(false)
            }
            Attachment(id:"panelShade") {
                Rectangle().fill(Color.clubInk.opacity(0.87))
                    .overlay(LinearGradient(colors:[Color.clubInk.opacity(0.25),Color.clubViolet.opacity(0.28)],startPoint:.bottomLeading,endPoint:.topTrailing))
                    .frame(width:1920,height:1080).allowsHitTesting(false)
            }
            Attachment(id:"homeActions") {
                ClubHeroMenu(modeTitle:modeTitle,opening:opening,onPlay:startPlay,
                             onRacket:openRackets,onMode:openMode,onSettings:openSettings)
            }
            Attachment(id:"homePoster") {
                ClubPosterMenu(modeTitle:modeTitle,opening:opening,onPlay:startPlay,
                               onRacket:openRackets,onMode:openMode,onSettings:openSettings)
            }
            Attachment(id:"main") {
                if game.showSettings { AudioSettings(onClose:{game.showSettings=false}).environment(game) }
                else if game.showRackets { RacketSelection(onClose:{game.showRackets=false}).environment(game) }
                else if setup { PlaySetup(onClose:{setup=false}).environment(game) }
                else if choosingMode { GameModeSelection(onClose:{choosingMode=false}).environment(game) }
                else if homeSettings {
                    ClubHomeSettings(style:$storedStyle,onClose:{homeSettings=false},
                                     onTracking:{homeSettings=false;setup=true},
                                     onSound:{homeSettings=false;game.showSettings=true})
                } else { Color.clear.frame(width:1,height:1) }
            }
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--preview-rackets") { game.showRackets=true }
            if ProcessInfo.processInfo.arguments.contains("--preview-home-settings") { homeSettings=true }
            if ProcessInfo.processInfo.arguments.contains("--preview-home-mode") { choosingMode=true }
            #endif
        }
        .onDisappear { scene.subscription?.cancel() }
    }
    private func cue() { if game.soundEnabled { SoundBank.play(.select) } }
    private func openRackets() { game.showRackets=true;cue() }
    private func openMode() { choosingMode=true;cue() }
    private func openSettings() { homeSettings=true;cue() }
    private func startPlay() {
        guard !opening else { return }
        opening=true;cue()
        game.showRackets=false;game.showSettings=false;game.showPlaySetup=false;game.showCourtMenu=false
        setup=false;choosingMode=false;homeSettings=false;game.paused=false
        navigation.log.info("Entering court from the new home menu")
        navigation.playing=true
    }
}

struct ClubHomeSettings:View {
    @Binding var style:String
    var onClose:()->Void
    var onTracking:()->Void
    var onSound:()->Void
    var body:some View {
        VStack(alignment:.leading,spacing:25) {
            HStack {
                Text("Make yourself at home.").font(.system(size:29,weight:.heavy,design:.rounded))
                Spacer()
                Button(action:onClose) { Image(systemName:"xmark").font(.system(size:17,weight:.semibold)).frame(width:42,height:42).background(.white,in:Circle()) }.accessibilityLabel("Close settings")
            }
            VStack(alignment:.leading,spacing:12) {
                Text("Home style").font(.headline)
                HStack(spacing:8) {
                    ForEach(ClubHomeStyle.allCases) { choice in
                        Button { style=choice.rawValue } label: {
                            HStack(spacing:8) {
                                Text(choice.title)
                                if style == choice.rawValue { Image(systemName:"checkmark") }
                            }.font(.system(size:17,weight:.bold,design:.rounded))
                                .frame(maxWidth:.infinity).frame(height:46)
                                .foregroundStyle(style == choice.rawValue ? Color.white:Color.clubInk)
                                .background(style == choice.rawValue ? Color.clubViolet:Color.white,in:RoundedRectangle(cornerRadius:15))
                        }.accessibilityAddTraits(style == choice.rawValue ? .isSelected:[])
                    }
                }
            }
            VStack(spacing:12) {
                Button(action:onTracking) { settingsRow("Racket & tracking","Hands, Sense controllers and grip",icon:"hand.raised.fill") }
                Button(action:onSound) { settingsRow("Sound & comfort","Music, effects and gentler motion",icon:"speaker.wave.2") }
            }
        }.padding(30).frame(width:560).foregroundStyle(Color.clubInk).tint(.clubViolet)
            .background(Color.clubPaper,in:RoundedRectangle(cornerRadius:30)).buttonStyle(ArcadePress())
    }
    private func settingsRow(_ title:String,_ detail:String,icon:String)->some View {
        HStack(spacing:16) {
            Image(systemName:icon).font(.system(size:24)).foregroundStyle(Color.clubViolet).frame(width:36)
            VStack(alignment:.leading,spacing:5) { Text(title).font(.system(size:19,weight:.bold,design:.rounded));Text(detail).font(.system(size:13)).foregroundStyle(Color.clubInk.opacity(0.65)) }
            Spacer();Image(systemName:"chevron.right").font(.system(size:13,weight:.semibold))
        }.padding(19).foregroundStyle(Color.clubInk).background(.white,in:RoundedRectangle(cornerRadius:22))
    }
}

struct GameModeSelection:View {
    @Environment(GameModel.self) private var game
    var onClose:@MainActor ()->Void
    var body:some View {
        VStack(alignment:.leading,spacing:22) {
            HStack { Text("How shall we play?").font(.system(size:29,weight:.bold,design:.rounded));Spacer();Button("Done",action:onClose).font(.subheadline.bold()) }
            ForEach(GameMode.allCases) { mode in
                Button { game.mode=mode;if game.soundEnabled { SoundBank.play(.select) };onClose() } label:{
                    HStack(spacing:17) {
                        Image(systemName:mode == .practice ? "infinity":mode == .match ? "trophy":"scope").font(.title2).frame(width:30)
                        VStack(alignment:.leading,spacing:5) {
                            Text(mode == .practice ? "Free play":mode == .match ? "Quick match":"Target rush").font(.headline)
                            Text(mode == .practice ? "Keep the rally going with Milo.":mode == .match ? "First to seven, win by two.":"Milo feeds shuttles. Aim for the floor targets.").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer();if game.mode == mode { Image(systemName:"checkmark.circle.fill") }
                    }.padding(20).foregroundStyle(Color.clubInk).background(game.mode == mode ? Color.clubMint.opacity(0.18):.white,in:RoundedRectangle(cornerRadius:20))
                }.buttonStyle(ArcadePress())
            }
        }.padding(30).frame(width:500).foregroundStyle(Color.clubInk).tint(.clubViolet).background(Color.clubPaper,in:RoundedRectangle(cornerRadius:28))
    }
}

struct ArcadePress:ButtonStyle {
    func makeBody(configuration:Configuration)->some View { configuration.label.contentShape(Rectangle()).scaleEffect(configuration.isPressed ? 0.95:1).animation(.spring(response:0.22,dampingFraction:0.65),value:configuration.isPressed).hoverEffect(.lift) }
}
struct RacketDockLabel:View {
    @Environment(GameModel.self) private var game
    var body:some View {
        VStack(spacing:9) {
            Text("PICK YOUR RACKET").font(.system(size:11,weight:.heavy,design:.rounded)).tracking(1.8)
            HStack(spacing:6) { ForEach(RacketKind.allCases) { kind in
                Button { game.selectRacket(kind) } label: {
                    Text(kind.name.replacingOccurrences(of:" Club",with:"" )).font(.system(size:12,weight:.bold,design:.rounded)).frame(width:87).padding(.vertical,11).foregroundStyle(game.racketKind == kind ? Color.clubInk:Color.white).background(game.racketKind == kind ? kind.colour:Color.white.opacity(0.13),in:Capsule())
                }.buttonStyle(ArcadePress())
            } }
        }.padding(14).foregroundStyle(.white).background(Color.clubViolet.opacity(0.96),in:RoundedRectangle(cornerRadius:20))
    }
}
struct PlaySetup:View {
    @Environment(GameModel.self) private var game
    @Environment(\.dismiss) private var dismiss
    @State private var adjustingController=false
    var inCourt=false
    var onClose:(@MainActor ()->Void)? = nil
    var body:some View {
        if adjustingController,inCourt,game.input == .sense {
            SenseGripSetup(onBack:{adjustingController=false})
        } else {
            setupContent
        }
    }
    @ViewBuilder private var setupContent:some View {
        @Bindable var game=game
        VStack(alignment:.leading,spacing:20) {
            HStack { Text("Ready your racket").font(.system(size:30,weight:.heavy,design:.rounded));Spacer();Button("Done") { if let onClose { onClose() } else { dismiss() } } }
            Picker("Play with",selection:$game.input) { ForEach(InputMode.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
            Picker("Racket hand",selection:$game.leftHand) { Text("Right hand").tag(false);Text("Left hand").tag(true) }.pickerStyle(.segmented)
            Picker("Milo’s pace",selection:$game.difficulty) { ForEach(Difficulty.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
            VStack(alignment:.leading,spacing:10) {
                Label(game.input == .hands ? "Your hand holds the racket":"Your controller holds the racket",systemImage:game.input == .hands ? "hand.raised.fill":"gamecontroller.fill").font(.headline)
                Text(game.input == .hands ? "Open your racket hand, then close it to grab. Your grip locks, so you can relax your fingers and swing. Open fully for a moment to release. Milo serves when you are holding the racket." : "Connect your PS VR2 Sense controllers in Vision Pro Bluetooth settings. Keep your selected controller in view. Milo serves automatically after two ready seconds; its trigger starts sooner.").font(.subheadline).foregroundStyle(.secondary)
                if inCourt {
                    Label(tracked ? "\(game.leftHand ? "Left":"Right") \(game.input == .hands ? "hand":"controller") tracked" : "Waiting for \(game.leftHand ? "left":"right") \(game.input == .hands ? "hand":"controller")",systemImage:tracked ? "checkmark.circle.fill":"exclamationmark.circle").font(.subheadline.bold()).foregroundStyle(tracked ? Color.clubViolet:Color.clubInk)
                    if !game.trackingMessage.isEmpty { Text(game.trackingMessage).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true) }
                    HStack {
                        Button("Retry tracking") { game.reconfigureTracking() }.accessibilityIdentifier("retryTracking")
                        if game.input == .hands { Button("Align racket") { game.setGrip() }.disabled(!game.canAdjustHandGrip).accessibilityIdentifier("calibrateGrip") }
                        Button("Recenter") { game.recenter() }.disabled(!game.canServe)
                    }.buttonStyle(.bordered)
                    if game.input == .hands { Text("Once grabbed, hold a comfortable ready pose and choose Align racket if the angle feels wrong. Your fit is saved for this hand.").font(.caption).foregroundStyle(.secondary) }
                    if game.input == .sense {
                        HStack {
                            Button("Set grip") { game.setGrip() }.disabled(!game.canAdjustControllerGrip).accessibilityIdentifier("calibrateControllerGrip")
                            Button("Adjust fit") { adjustingController=true }.disabled(!game.canAdjustControllerGrip).accessibilityIdentifier("adjustControllerFit")
                        }.buttonStyle(.bordered)
                        Text("Fit changes save separately for your left and right controllers.").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(game.rallyInProgress ? "Close this panel and resume your paused rally." : "Close this panel. Milo will serve when your racket is ready.").font(.caption).foregroundStyle(.secondary)
                    if game.input == .sense { Text("The controller menu button pauses play.").font(.caption).foregroundStyle(.secondary) }
                } else {
                    Text("Choose your racket hand here. Tracking starts when you enter the court; grip and connection controls are available there.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(18).frame(maxWidth:.infinity,alignment:.leading).background(.white,in:RoundedRectangle(cornerRadius:18))
            if !inCourt { Button { game.showSettings=true } label:{ Label("Sound & comfort",systemImage:"speaker.wave.2") }.font(.subheadline.bold()).buttonStyle(.bordered) }
        }.padding(30).frame(width:540).foregroundStyle(Color.clubInk).tint(.clubViolet).background(Color.clubPaper,in:RoundedRectangle(cornerRadius:26))
    }
    private var tracked:Bool { game.input == .hands ? game.handVisible:game.controllerReady }
}
