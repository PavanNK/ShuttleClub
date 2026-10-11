import SwiftUI
import RealityKit
import ShuttleCore

extension RacketKind {
    var colour: Color { Color(uiColor: frameColour) }
    var frameColour: UIColor { switch self {
        case .coral: .init(red:1,green:0.32,blue:0.39,alpha:1)
        case .mint: .init(red:0.10,green:0.84,blue:0.69,alpha:1)
        case .solar: .init(red:1,green:0.72,blue:0.08,alpha:1)
        case .midnight: .init(red:0.42,green:0.33,blue:0.92,alpha:1)
    } }
    var gripColour: UIColor { self == .solar ? .init(red:0.95,green:0.27,blue:0.35,alpha:1) : self == .mint ? .init(red:0.02,green:0.23,blue:0.3,alpha:1) : .init(red:0.48,green:0.18,blue:0.72,alpha:1) }
}

struct RacketSelection: View {
    @Environment(GameModel.self) private var game
    @Environment(\.dismiss) private var dismiss
    @State private var pendingKind: RacketKind = .coral
    @State private var showingSolar = false
    var onClose: (@MainActor () -> Void)? = nil

    private var collection: [RacketKind] { [.coral, .mint, showingSolar ? .solar : .midnight] }

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                HStack {
                    Button(action: close) {
                        Image(systemName: "arrow.left").font(.system(size: 23, weight: .semibold))
                            .frame(width: 50, height: 50)
                            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 17))
                            .overlay(RoundedRectangle(cornerRadius: 17).stroke(.white.opacity(0.30), lineWidth: 1).allowsHitTesting(false))
                    }.buttonStyle(.plain).hoverEffect(.lift)
                        .accessibilityLabel("Back to the club").keyboardShortcut(.cancelAction)
                    Spacer()
                }
                HStack(spacing: 13) {
                    RacketCollectionMark().frame(width: 27, height: 36)
                    Text("SHUTTLE CLUB").font(.system(size: 17, weight: .heavy, design: .rounded)).tracking(1.5)
                }.frame(width: 300, height: 82)
                    .foregroundStyle(Color.clubInk)
                    .background(collectionPaper, in: RoundedRectangle(cornerRadius: 27))
            }.frame(width: 1500, height: 82)
            VStack(spacing: 10) {
                Text("MAKE IT YOURS").font(.system(size: 16, weight: .heavy, design: .rounded))
                    .tracking(2.6).foregroundStyle(collectionGold)
                Text("Find your favourite racket.")
                    .font(.system(size: 58, weight: .bold, design: .rounded)).tracking(-1.8)
                Text("Three colours. Three ways to play.")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundStyle(collectionPaper.opacity(0.75))
            }.frame(width: 1000).padding(.bottom, 30)
            HStack(spacing: 20) {
                ForEach(collection) { kind in
                    Button {
                        withAnimation(game.reducedMotion ? nil : .easeInOut(duration: 0.2)) { pendingKind = kind }
                    } label: {
                        racketCard(kind)
                    }.buttonStyle(.plain).hoverEffect(.lift)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(kind.name). \(kind.description)")
                        .accessibilityValue(pendingKind == kind ? "Selected preview" : "")
                        .accessibilityHint("Preview this racket, then use Choose to save your selection.")
                        .accessibilityAddTraits(pendingKind == kind ? .isSelected : [])
                        .accessibilityIdentifier("racketCard.\(kind.rawValue)")
                }
            }.frame(width: 1000).padding(.bottom, 30)
            Button(action: choose) {
                HStack(spacing: 20) {
                    Text("Choose \(pendingKind.collectionName)").font(.system(size: 25, weight: .heavy, design: .rounded))
                    Spacer()
                    Image(systemName: "arrow.right").font(.system(size: 21, weight: .semibold))
                }.padding(.horizontal, 25).frame(width: 310, height: 72)
                    .foregroundStyle(Color.clubInk)
                    .background(collectionGold, in: RoundedRectangle(cornerRadius: 23))
                    .shadow(color: Color(red: 0.70, green: 0.36, blue: 0.14).opacity(0.7), radius: 0, y: 4)
            }.buttonStyle(.plain).hoverEffect(.lift).disabled(game.rallyInProgress)
                .keyboardShortcut(.defaultAction).accessibilityIdentifier("chooseRacket")
            HStack(spacing: 16) {
                Text("You can change your racket between rallies.")
                    .font(.system(size: 16, weight: .medium)).foregroundStyle(collectionPaper.opacity(0.73))
                Button(showingSolar ? "Also try Midnight" : "Also try Solar") {
                    showingSolar.toggle()
                    pendingKind = showingSolar ? .solar : .midnight
                }.font(.system(size: 16, weight: .semibold)).foregroundStyle(collectionGold)
                    .buttonStyle(.plain).hoverEffect(.highlight)
                    .accessibilityIdentifier("alternateRacket")
            }.frame(width: 1000)
            if game.rallyInProgress {
                Text("Finish this rally before choosing a new racket.")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(collectionGold)
            }
        }.padding(.horizontal, 28).padding(.vertical, 10).frame(width: 1600, height: 820)
            .foregroundStyle(collectionPaper)
            .onAppear {
                pendingKind = game.racketKind
                showingSolar = game.racketKind == .solar
            }
    }

    private var collectionPaper: Color { Color(red: 1, green: 0.97, blue: 0.89) }
    private var collectionGold: Color { Color(red: 1, green: 0.85, blue: 0.40) }

    private func racketCard(_ kind: RacketKind) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            RacketPreview(kind: kind, reducedMotion: game.reducedMotion, highlighted: pendingKind == kind)
                .frame(width: 220, height: 232).allowsHitTesting(false)
            Text(kind.collectionName).font(.system(size: 25, weight: .heavy, design: .rounded))
            Text(kind.collectionSummary).font(.system(size: 16, weight: .medium))
                .foregroundStyle(collectionPaper.opacity(0.78))
                .lineSpacing(2).frame(height: 40, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
        }.padding(16).frame(width: 270, height: 350, alignment: .topLeading)
            .background(LinearGradient(colors: [kind.colour.opacity(0.16), .white.opacity(0.12)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 28))
            .background(Color(red: 0.035, green: 0.13, blue: 0.17).opacity(0.40),
                        in: RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28)
                .stroke(pendingKind == kind ? collectionGold : .white.opacity(0.23), lineWidth: pendingKind == kind ? 2.3 : 1)
                .allowsHitTesting(false))
            .overlay(alignment: .topTrailing) {
                if pendingKind == kind {
                    Image(systemName: "checkmark").font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Color.clubInk).frame(width: 27, height: 27)
                        .background(collectionGold, in: Circle()).padding(16).allowsHitTesting(false)
                }
            }
    }

    private func choose() {
        guard !game.rallyInProgress else { return }
        let unchanged = pendingKind == game.racketKind
        game.selectRacket(pendingKind)
        guard game.racketKind == pendingKind else { return }
        if unchanged, game.soundEnabled { SoundBank.play(.select) }
        close()
    }
    private func close() { if let onClose { onClose() } else { dismiss() } }
}

private struct RacketCollectionMark: View {
    var body: some View {
        Canvas { context, size in
            let violet = Color(red: 0.46, green: 0.27, blue: 0.72)
            let base = CGPoint(x: size.width * 0.5, y: size.height * 0.68)
            for feather in 0..<5 {
                let x = size.width * (0.08 + CGFloat(feather) * 0.21)
                let top = CGPoint(x: x, y: size.height * (feather == 0 || feather == 4 ? 0.17 : 0.05))
                var plume = Path()
                plume.move(to: CGPoint(x: base.x + (x - base.x) * 0.24, y: base.y))
                plume.addQuadCurve(to: top, control: CGPoint(x: x, y: size.height * 0.43))
                context.stroke(plume, with: .color(violet), style: StrokeStyle(lineWidth: 3.3, lineCap: .round))
            }
            let band = CGRect(x: size.width * 0.31, y: size.height * 0.63, width: size.width * 0.38, height: size.height * 0.12)
            context.fill(Path(roundedRect: band, cornerRadius: 1.5), with: .color(violet))
            let cork = CGRect(x: size.width * 0.33, y: size.height * 0.75, width: size.width * 0.34, height: size.height * 0.20)
            context.fill(Path(roundedRect: cork, cornerRadius: 4), with: .color(violet))
        }.accessibilityHidden(true)
    }
}

private extension RacketKind {
    var collectionName: String {
        switch self { case .coral: "Coral"; case .mint: "Mint"; case .solar: "Solar"; case .midnight: "Midnight" }
    }
    var collectionSummary: String {
        switch self {
        case .coral: "Balanced & forgiving."
        case .mint: "Lighter frame. Softer rebound."
        case .solar: "More head mass. Livelier rebound."
        case .midnight: "Smaller strings. Softer rebound."
        }
    }
}

@MainActor private final class RacketCardScene {
    let root = Entity(), model = Entity()
    var subscription: EventSubscription?
    var kind: RacketKind?
    var reducedMotion = false
    var highlighted = false
    private var frameUpdates: FrameUpdateGate?
    private var studioLightInstalled = false
    private var clock: Float = 0

    func attach(_ content: RealityViewContent, kind: RacketKind, reducedMotion: Bool, highlighted: Bool) {
        stop()
        if model.parent !== root { root.addChild(model) }
        root.position = [0, -0.067, 0]
        root.scale = [0.27, 0.27, 0.27]
        content.add(root)
        if !studioLightInstalled { ClubScene.studioLight(root); studioLightInstalled = true }
        configure(kind: kind, reducedMotion: reducedMotion, highlighted: highlighted)
        let updates = FrameUpdateGate(onFrame: { [weak self] delta in
            guard let self else { return }
            clock += Float(delta)
            pose()
        })
        frameUpdates = updates
        subscription = content.subscribe(to: SceneEvents.Update.self) { event in
            updates.submit(delta: event.deltaTime)
        }
    }
    func configure(kind: RacketKind, reducedMotion: Bool, highlighted: Bool) {
        if self.kind != kind {
            model.children.forEach { $0.removeFromParent() }
            model.addChild(ClubScene.makeRacket(kind))
            self.kind = kind
        }
        self.reducedMotion = reducedMotion
        self.highlighted = highlighted
        pose()
    }
    private func pose() {
        let yaw: Float = reducedMotion ? 0.18 : 0.18 + sin(clock * 0.7) * (highlighted ? 0.19 : 0.10)
        root.orientation = simd_quatf(angle: -0.22, axis: [0, 0, 1]) * simd_quatf(angle: yaw, axis: [0, 1, 0])
    }
    func stop() {
        subscription?.cancel(); subscription = nil
        frameUpdates?.cancel(); frameUpdates = nil
    }
}

struct RacketPreview: View {
    let kind: RacketKind
    var reducedMotion = false
    var highlighted = false
    @State private var scene = RacketCardScene()
    var body: some View {
        RealityView { content in
            scene.attach(content, kind: kind, reducedMotion: reducedMotion, highlighted: highlighted)
        } update: { _ in
            scene.configure(kind: kind, reducedMotion: reducedMotion, highlighted: highlighted)
        }.realityViewLayoutBehavior(.fixedSize)
            .accessibilityLabel("Three dimensional \(kind.name) racket")
            .onDisappear { scene.stop() }
    }
}
