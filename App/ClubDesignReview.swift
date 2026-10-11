import SwiftUI
import RealityKit
import simd

/// Native design review uses the actual club, authored meshes and SwiftUI.
/// It does not run a rally or change the installed home-screen selection.
@MainActor @Observable final class ClubDesignReviewScene {
    let assets = ClubScene.build()
    let robot: Entity
    private let refined: Bool
    var subscription: EventSubscription?
    private var reportedReady = false

    init(style: MiloDesignStyle) {
        robot = MiloDesignOptions.make(style)
        refined = style.rawValue == "refined"
    }

    func attach(_ content: RealityViewContent, attachments: RealityViewAttachments,
                onReady: @escaping @MainActor () -> Void) {
        let root = assets.root
        assets.milo.isEnabled = false
        assets.racket.isEnabled = false
        assets.shuttle.isEnabled = false
        assets.targets.isEnabled = false
        // Keep the review's daylight warm without burning out the ivory shell.
        // The larger bias prevents concentric self-shadow bands on curved armour.
        for light in root.children.compactMap({ $0 as? DirectionalLight }) {
            if light.name == "soft front bounce" {
                light.light.intensity = 5500
            } else {
                light.light.intensity = 16000
                light.shadow = .init(shadowProjection: .automatic(maximumDistance: 18), depthBias: 0.025)
            }
        }
        robot.position = refined ? [0.94, 0, -4.55] : [1.30, 0, -3.8]
        robot.scale = refined ? [1.05, 1.05, 1.05] : [1.15, 1.15, 1.15]
        robot.orientation = simd_quatf(angle: -0.10, axis: [0, 1, 0])
        root.addChild(robot)
        ClubScene.addContactShadow(robot, size: [0.86, 0.58], at: [0, 0.005, 0.08], opacity: 0.32)
        func enableShadows(_ entity: Entity) {
            if entity.components[ModelComponent.self] != nil,
               entity.name != "soft contact shadow" {
                entity.components.set(DynamicLightShadowComponent(castsShadow: true))
            }
            for child in entity.children { enableShadows(child) }
        }
        enableShadows(robot)
        if let menu = attachments.entity(for: "menu") {
            menu.position = refined ? [-0.30, 0.74, -2.8] : [-1.03, 1.86, -3.8]
            menu.scale = refined ? [2.7, 2.7, 2.7] : [3.55, 3.55, 3.55]
            root.addChild(menu)
        }
        if let title = attachments.entity(for: "title") {
            title.position = [-0.65, 2.57, -4.2]
            title.scale = [3.1, 3.1, 3.1]
            root.addChild(title)
        }
        content.add(root)
        subscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !reportedReady else { return }
                reportedReady = true
                onReady()
            }
        }
    }
}

struct ClubDesignReview: View {
    let style: MiloDesignStyle
    var onReady: @MainActor () -> Void = {}
    @State private var scene: ClubDesignReviewScene

    init(style: MiloDesignStyle, onReady: @escaping @MainActor () -> Void = {}) {
        self.style = style
        self.onReady = onReady
        _scene = State(initialValue: ClubDesignReviewScene(style: style))
    }

    var body: some View {
        RealityView { content, attachments in
            scene.attach(content, attachments: attachments, onReady: onReady)
        } attachments: {
            Attachment(id: "menu") {
                if style.rawValue == "refined" { ClubHeroMenu() }
                else { ClubMenuOption(style: ClubMenuDesignStyle(rawValue: style.rawValue) ?? .sunny) }
            }
            if style.rawValue == "refined" {
                Attachment(id: "title") { ClubHeroWordmark() }
            }
        }
        .onDisappear { scene.subscription?.cancel() }
    }
}
