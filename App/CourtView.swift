import SwiftUI
import RealityKit
import GameController
import OSLog
import ShuttleCore

struct CourtView:View {
    @Environment(GameModel.self) private var game
    @Environment(\.scenePhase) private var phase
    var onReady: @MainActor () -> Void = {}
    var body:some View {
        RealityView { content,attachments in
            game.prepare();content.add(game.assets.root)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--preview-court-tracking") { game.showPlaySetup=true }
            #endif
            if let hud=attachments.entity(for:"score") { hud.position=[0,3.40,-5.5];hud.scale=[8.5,8.5,8.5];game.assets.root.addChild(hud) }
            if let controls=attachments.entity(for:"controls") { placeControls(controls);game.assets.root.addChild(controls) }
            game.subscribe(to:content,onReady:onReady)
        } update: { _,attachments in
            if let controls=attachments.entity(for:"controls") {
                if controls.parent !== game.assets.root { game.assets.root.addChild(controls) }
                placeControls(controls)
            }
        } attachments: {
            Attachment(id:"score") { ScoreView().environment(game) }
            Attachment(id:"controls") {
                Group {
                    if game.showPlaySetup {
                        PlaySetup(inCourt:true,onClose:{ game.showPlaySetup=false }).environment(game)
                    } else if game.showSettings {
                        AudioSettings(onClose:{ game.showSettings=false }).environment(game)
                    } else if game.showRackets {
                        RacketSelection(onClose:{ game.showRackets=false }).environment(game)
                    } else if game.showCourtMenu {
                        CourtMenu().environment(game)
                    } else {
                        CourtControls().environment(game)
                    }
                }
            }
        }.handlesGameControllerEvents(matching:.gamepad)
            .onDisappear { game.stop() }
            .onChange(of:phase) { _,p in game.sceneActivityChanged(active:p == .active) }
            .onChange(of:game.input) { _,_ in game.reconfigureTracking() }
            .onChange(of:game.leftHand) { _,_ in game.reconfigureTracking() }
    }
    private func placeControls(_ controls:Entity) {
        if game.showPlaySetup || game.showCourtMenu || game.showSettings || game.showRackets {
            controls.position=[0,1.65,-2.2];controls.scale=[2.8,2.8,2.8]
        } else if game.canServe || game.paused || game.score.winner != nil || !game.racketReady {
            controls.position=[0,1.35,-2.2];controls.scale=[3,3,3]
        } else {
            controls.position=[-1.1,0.85,-2.2];controls.scale=[1.7,1.7,1.7]
        }
    }
}
struct ScoreView:View {
    @Environment(GameModel.self) private var game
    var body:some View {
        VStack(spacing:7) {
          HStack(spacing:22) {
            Text(game.mode == .targets ? "POINTS":"YOU").font(.system(size:13,weight:.bold,design:.rounded))
            Text("\(game.mode == .targets ? game.targetPoints:game.score.player)").font(.system(size:35,weight:.bold,design:.rounded)).monospacedDigit().contentTransition(.numericText())
            Rectangle().fill(Color.clubInk.opacity(0.15)).frame(width:1,height:31)
            Text(game.mode == .targets ? "STREAK":"MILO").font(.system(size:13,weight:.bold,design:.rounded))
            Text(game.mode == .targets ? "\(game.streak)×":"\(game.score.milo)").font(.system(size:35,weight:.bold,design:.rounded)).monospacedDigit().contentTransition(.numericText())
          }
          if game.mode != .targets {
              HStack(spacing:13) {
                  Text("RALLY \(game.rallyHits)").contentTransition(.numericText())
                  Text("BEST \(game.bestRally)").foregroundStyle(Color.clubInk.opacity(0.55))
              }.font(.system(size:9,weight:.heavy,design:.rounded)).monospacedDigit().tracking(0.7)
          }
        }.padding(.horizontal,24).padding(.vertical,13).foregroundStyle(Color.clubInk).background(.white,in:RoundedRectangle(cornerRadius:23))
            .animation(.spring(response:0.35,dampingFraction:0.7),value:game.score.player)
            .animation(.spring(response:0.35,dampingFraction:0.7),value:game.score.milo)
    }
}
struct CourtControls:View {
    @Environment(GameModel.self) private var game
    var body:some View {
        VStack(spacing:10) {
            if game.canServe || game.paused || game.isPreparingServe || game.score.winner != nil {
                Text(game.message).font(.system(size:13,weight:.bold,design:.rounded)).multilineTextAlignment(.center).frame(maxWidth:290)
            } else {
                Text(game.message).font(.system(size:11,weight:.bold,design:.rounded)).multilineTextAlignment(.center).frame(maxWidth:200)
            }
            if game.isPreparingServe {
                if game.paused { Text("Serve paused").font(.caption.bold()) }
                ProgressView(value:Double(0.65-game.serveCountdown),total:0.65).tint(.clubViolet).frame(width:180).accessibilityLabel("Serve windup")
            } else if game.canServe && tracked && !game.paused && game.automaticServing {
                Label("Milo serves in \(max(1,Int(ceil(game.nextServeCountdown))))…",systemImage:"figure.badminton").font(.caption.bold()).monospacedDigit()
            }
            HStack(spacing:12) {
                if game.mode == .match && game.score.winner != nil { Button { game.restart() } label:{ Label("Play again",systemImage:"arrow.clockwise") }.accessibilityIdentifier("playAgain") }
                else if game.paused { Button { game.paused=false;if game.soundEnabled { SoundBank.play(.pause) } } label:{ Label("Resume",systemImage:"play.fill") }.disabled(!tracked).accessibilityIdentifier("resumeRally") }
                else { Button { game.paused=true; if game.soundEnabled { SoundBank.play(.pause) } } label:{ Label("Pause",systemImage:"pause.fill") } }
                Button { Logger(subsystem:"com.shuttleclub.vision",category:"Court").info("Court menu selected");if game.rallyInProgress { game.paused=true };game.showCourtMenu=true;if game.soundEnabled { SoundBank.play(.menu) } } label:{ Image(systemName:"ellipsis") }.accessibilityLabel("Open club menu")
            }.font(.system(size:13,weight:.bold,design:.rounded)).buttonStyle(.bordered).tint(.clubViolet)
            if game.collisionPreview { Text("Collision preview · simulated hands").font(.system(size:9)).foregroundStyle(.secondary) }
            else if !tracked {
                RacketTrackingStatus(compact:true).frame(maxWidth:290)
                Button("Set up tracking") { if game.rallyInProgress { game.paused=true };game.showPlaySetup=true }.font(.caption.bold()).buttonStyle(.bordered).accessibilityIdentifier("setupTracking")
            }
        }.padding(14).foregroundStyle(Color.clubInk).background(Color.clubPaper.opacity(0.93),in:RoundedRectangle(cornerRadius:21))
    }
    private var tracked:Bool { game.racketReady }
}
struct CourtMenu:View {
    @Environment(GameModel.self) private var game
    @Environment(ClubNavigation.self) private var navigation
    var body:some View {
        VStack(alignment:.leading,spacing:23) {
            HStack {
                Text("Club menu").font(.system(size:30,weight:.heavy,design:.rounded));Spacer()
                Button { closeMenus() } label:{ Image(systemName:"xmark").font(.system(size:17,weight:.semibold)).frame(width:42,height:42).background(.white,in:Circle()) }.buttonStyle(.plain).hoverEffect(.lift).accessibilityLabel("Close court menu")
            }
            Button { game.showRackets=true } label:{ menuRow(game.racketKind.name,"Choose your racket","figure.badminton") }.disabled(!game.canServe)
            Button { game.showPlaySetup=true } label:{ menuRow("Racket & tracking","Hands, Sense controllers and grip","hand.raised.fill") }.accessibilityIdentifier("courtPlaySetup")
            Button { game.showSettings=true } label:{ menuRow("Sound & comfort","Music, effects and animation","slider.horizontal.3") }
            HStack { Button("Align angle") { game.setGrip() }.disabled(game.input == .hands ? !game.canAdjustHandGrip:!game.canAdjustControllerGrip);Button("Recenter") { game.recenter() }.disabled(!game.canServe);Button("Restart") { game.restart();closeMenus() } }.buttonStyle(.bordered).font(.system(size:15,weight:.semibold))
            if !game.racketReady { RacketTrackingStatus(compact:true) }
            Button { game.paused=false;closeMenus() } label:{ Label(game.rallyInProgress ? "Resume rally":"Back to court",systemImage:"play.fill") }.buttonStyle(ClubPrimaryButton(colour:.clubCoral)).disabled(!game.racketReady)
            Button("Leave the court") { closeMenus();game.stop();navigation.playing=false }.font(.subheadline).frame(maxWidth:.infinity)
        }.padding(30).frame(width:510).foregroundStyle(Color.clubInk).tint(.clubViolet).background(Color.clubPaper,in:RoundedRectangle(cornerRadius:26))
    }
    private func closeMenus() { game.showCourtMenu=false;game.showSettings=false;game.showRackets=false;game.showPlaySetup=false }
    private func menuRow(_ title:String,_ subtitle:String,_ icon:String)->some View { HStack(spacing:15) { Image(systemName:icon).font(.title2).foregroundStyle(Color.clubViolet).frame(width:42);VStack(alignment:.leading,spacing:4) { Text(title).font(.system(size:18,weight:.bold,design:.rounded));Text(subtitle).font(.system(size:14)).foregroundStyle(.secondary) };Spacer();Image(systemName:"chevron.right") }.padding(16).foregroundStyle(Color.clubInk).background(.white,in:RoundedRectangle(cornerRadius:19)) }
}
