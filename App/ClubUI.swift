import SwiftUI
import RealityKit
import ShuttleCore

extension Color {
    static let clubInk=Color(red:0.055,green:0.15,blue:0.19)
    static let clubViolet=Color(red:0.35,green:0.16,blue:0.68)
    static let clubPaper=Color(red:0.98,green:0.965,blue:0.935)
    static let clubCoral=Color(red:1,green:0.36,blue:0.40)
    static let clubMint=Color(red:0.07,green:0.65,blue:0.64)
}
struct ClubPill:View {
    let title:String; var colour:Color = .clubViolet
    var body:some View { Text(title).font(.system(size:11,weight:.heavy,design:.rounded)).tracking(1.6).padding(.horizontal,13).padding(.vertical,8).foregroundStyle(colour).background(colour.opacity(0.10),in:Capsule()) }
}
struct ClubPrimaryButton:ButtonStyle {
    var colour:Color = .clubViolet
    func makeBody(configuration:Configuration)->some View {
        configuration.label.font(.system(size:17,weight:.bold,design:.rounded)).padding(.horizontal,24).padding(.vertical,17)
            .frame(maxWidth:.infinity).foregroundStyle(.white).background(colour.gradient,in:RoundedRectangle(cornerRadius:19))
            .shadow(color:colour.opacity(0.20),radius:12,y:5).scaleEffect(configuration.isPressed ? 0.97:1)
            .animation(.spring(response:0.25,dampingFraction:0.75),value:configuration.isPressed)
    }
}
struct AudioSettings:View {
    @Environment(GameModel.self) private var game
    @Environment(\.dismiss) private var dismiss
    var onClose:(@MainActor ()->Void)? = nil
    var body:some View {
        @Bindable var game=game
        VStack(alignment:.leading,spacing:25) {
            HStack { VStack(alignment:.leading,spacing:5) { ClubPill(title:"MAKE IT YOURS"); Text("Club settings").font(.system(size:36,weight:.bold,design:.rounded)) }; Spacer(); Button("Done") { close() }.buttonStyle(.borderedProminent).tint(.clubViolet) }
            VStack(spacing:22) {
                Toggle(isOn:$game.musicEnabled) { Label("Club music",systemImage:"music.note") }
                HStack { Text("Music volume");Spacer();Text("\(Int(game.musicVolume*100))%").monospacedDigit() }.font(.caption).foregroundStyle(.secondary)
                Slider(value:$game.musicVolume,in:0...1) { Text("Music volume") }.disabled(!game.musicEnabled)
                Toggle(isOn:$game.soundEnabled) { Label("Racket & court sounds",systemImage:"speaker.wave.2") }
                HStack { Text("Effects volume");Spacer();Text("\(Int(game.effectsVolume*100))%").monospacedDigit() }.font(.caption).foregroundStyle(.secondary)
                Slider(value:$game.effectsVolume,in:0...1) { Text("Effects volume") }.disabled(!game.soundEnabled)
            }.padding(24).background(.white,in:RoundedRectangle(cornerRadius:23))
            Toggle("Controller vibration",isOn:$game.hapticsEnabled)
            Toggle("Gentler character animation",isOn:$game.reducedMotion)
            Text("Music stays softer while paused. Tracking loss pauses the rally.").font(.subheadline).foregroundStyle(.secondary)
        }.padding(32).frame(width:540).foregroundStyle(Color.clubInk).tint(.clubViolet).background(Color.clubPaper)
    }
    private func close() { if let onClose { onClose() } else { dismiss() } }
}
@MainActor private final class MiloPreviewAnimator {
    var subscription:EventSubscription?
    var time:Float=0
    let assets=SceneAssets()
    func attach(_ content:RealityViewContent) {
        ClubScene.robot(assets)
        let model=assets.milo; model.position=[0,-0.099,0]; model.scale=[0.125,0.125,0.125]
        content.add(model); ClubScene.studioLight(model)
        subscription=content.subscribe(to:SceneEvents.Update.self) { [weak self] event in
            let delta=Float(event.deltaTime)
            Task { @MainActor [weak self] in
                guard let self else { return }; time += min(0.05,delta)
                assets.animateMilo(time:time,active:false,dt:delta)
                model.orientation=simd_quatf(angle:sin(time*0.6)*0.13,axis:[0,1,0])
            }
        }
    }
}
struct MiloPreview:View {
    @State private var animator=MiloPreviewAnimator()
    var body:some View {
        RealityView { content in animator.attach(content) }.realityViewLayoutBehavior(.fixedSize)
            .accessibilityLabel("Milo, your smiling orange robot rally partner")
            .onDisappear { animator.subscription?.cancel() }
    }
}
