import SwiftUI
import Observation
import OSLog

@MainActor @Observable final class ClubNavigation {
    var playing=false
    var spaceOpen=false
    var sceneReady=false
    var opening=false
    var error:String?
    let log=Logger(subsystem:"com.shuttleclub.vision",category:"Entry")

    func reportReady() {
        guard !sceneReady else { return }
        sceneReady=true
        log.info("Immersive scene received its first update")
    }
}

@main
struct ShuttleClubApp:App {
    @State private var game=GameModel()
    @State private var navigation=ClubNavigation()
    var body:some Scene {
        WindowGroup(id:"lobby") { ClubGateway().environment(game).environment(navigation) }
            .defaultSize(width:480,height:300)
        ImmersiveSpace(id:"club") { ClubSpace().environment(game).environment(navigation) }
            .immersionStyle(selection:.constant(.full),in:.full)
    }
}

struct ClubSpace:View {
    @Environment(ClubNavigation.self) private var navigation
    @Environment(\.dismissWindow) private var dismissWindow
    var body:some View {
        Group {
            #if DEBUG
            if let designStyle {
                ClubDesignReview(style: designStyle, onReady: ready)
            } else if navigation.playing { CourtView(onReady:ready) }
            else { ClubLobby(onReady:ready) }
            #else
            if navigation.playing { CourtView(onReady:ready) }
            else { ClubLobby(onReady:ready) }
            #endif
        }.onDisappear { navigation.spaceOpen=false;navigation.sceneReady=false }
    }
    #if DEBUG
    private var designStyle: MiloDesignStyle? {
        guard let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--design-review=") }) else { return nil }
        return MiloDesignStyle(rawValue: String(argument.dropFirst("--design-review=".count)))
    }
    #endif
    private func ready() {
        navigation.reportReady()
        dismissWindow(id:"lobby")
    }
}

struct ClubGateway:View {
    @Environment(GameModel.self) private var game
    @Environment(ClubNavigation.self) private var navigation
    @Environment(\.openImmersiveSpace) private var enter
    @Environment(\.dismissWindow) private var dismissWindow
    var body:some View {
        VStack(spacing:18) {
            Image(systemName:"figure.badminton").font(.system(size:44)).foregroundStyle(.white)
            Text(navigation.error == nil ? "Opening your club…":"Let’s try that again").font(.title2.bold())
            if let error=navigation.error {
                Text(error).font(.subheadline).multilineTextAlignment(.center)
                Button("Enter Shuttle Club") { Task { await open() } }.buttonStyle(.borderedProminent)
            } else {
                ProgressView().tint(.white)
                Text("Preparing the court and racket display.").font(.subheadline)
            }
        }.padding(32).frame(maxWidth:.infinity,maxHeight:.infinity).foregroundStyle(.white).background(Color.clubViolet.gradient)
            .task { SoundBank.prepare();game.syncAudio();await open() }
    }
    private func open() async {
        guard !navigation.opening else { return }
        if navigation.spaceOpen {
            if navigation.sceneReady { dismissWindow(id:"lobby") }
            return
        }
        navigation.opening=true;navigation.sceneReady=false;navigation.error=nil
        #if DEBUG
        navigation.playing=ProcessInfo.processInfo.arguments.contains("--preview-court")
        #endif
        navigation.log.info("Opening the club immersive space")
        switch await enter(id:"club") {
        case .opened:
            navigation.spaceOpen=true
            if navigation.sceneReady { dismissWindow(id:"lobby") }
        case .userCancelled:navigation.error="Opening was cancelled. You can enter when you’re ready."
        case .error:navigation.error="The court could not open. Please try again."
        @unknown default:navigation.error="The court could not open. Please try again."
        }
        navigation.opening=false
    }
}
