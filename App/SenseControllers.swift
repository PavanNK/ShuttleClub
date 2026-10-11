import ARKit
@preconcurrency import GameController
import CoreHaptics
import QuartzCore
import simd
import ShuttleCore

/// One ARKit session is shared with world alignment. The game uses the measured
/// grip for both the visible racket and collision; prediction remains optional.
@MainActor final class SenseControllers {
    // Apple's grip location follows OpenXR: -Z exits the curled fingers toward
    // the thumb, and +X is palm-normal. Our authored racket uses +Y and +Z.
    static let gripFromRacket = SenseGripFit.baseMount

    static func racketPose(fromGrip originFromGrip:simd_float4x4,fit:SenseGripFit = SenseGripFit())->simd_float4x4 {
        fit.mountedPose(fromGrip:originFromGrip)
    }

    struct Pose {
        let originFromGrip: simd_float4x4
        let leftHand: Bool
        let measured: simd_float4x4
        let rendered: simd_float4x4
        let headVelocity: V3
        let timestamp: Double
    }
    private var provider: AccessoryTrackingProvider?
    private var accessories: [Accessory] = []
    private var devices: [GCController] = []
    private var task: Task<Void,Never>?
    private var generation: UInt = 0
    private var selected: GCController?
    private var engine: CHHapticEngine?
    private var buttonEdges = ButtonEdges()
    private var needsButtonBaseline = true
    var status = "Pair PS VR2 Sense in Settings → Bluetooth."
    var configured = false
    var onServe: (() -> Void)?
    var onPause: (() -> Void)?
    var onLoss: (() -> Void)?
    private var previouslyTracked = false

    func start(session: ARKitSession, world: WorldTrackingProvider) {
        stop()
        #if targetEnvironment(simulator)
        status = "PS VR2 Sense tracking requires a physical Vision Pro."
        return
        #else
        guard AccessoryTrackingProvider.isSupported else { status="Accessory tracking is unavailable."; return }
        let run = generation
        status = "Allow accessory tracking when Vision Pro asks."
        task = Task { [weak self] in
            let permissions=await session.requestAuthorization(for:[.accessoryTracking])
            guard !Task.isCancelled, let self, generation == run else { return }
            guard permissions[.accessoryTracking] == .allowed else { status="Allow accessory tracking in Settings to use Sense controllers, then Retry tracking."; return }
            var known: Set<ObjectIdentifier> = []
            while !Task.isCancelled, generation == run {
                let connected=GCController.controllers().filter { $0.productCategory == GCProductCategorySpatialController }
                let identifiers=Set(connected.map(ObjectIdentifier.init))
                if identifiers != known || !configured {
                    known=identifiers
                    devices=connected; selected=nil
                    engine?.stop(completionHandler:nil); engine=nil; buttonEdges=ButtonEdges(); needsButtonBaseline=true
                    if previouslyTracked { onLoss?() }; previouslyTracked=false
                    do {
                        var loaded:[Accessory]=[]
                        for device in connected {
                            loaded.append(try await Accessory(device:device))
                            guard !Task.isCancelled, generation == run else { return }
                        }
                        guard !Task.isCancelled, generation == run else { return }
                        accessories=loaded
                        if let provider, provider.state == .running || provider.state == .paused,
                           #available(visionOS 27.0, *) {
                            try await provider.updateAccessories(loaded)
                        } else {
                            let next=AccessoryTrackingProvider(accessories:loaded); provider=next
                            try await session.run([world,next])
                        }
                        guard !Task.isCancelled, generation == run else { return }
                        configured=true
                        status=connected.isEmpty ? "Pair PS VR2 Sense in Settings → Bluetooth." : "Hold your selected controller where Vision Pro can see it."
                    } catch {
                        guard !Task.isCancelled, generation == run else { return }
                        configured=false
                        status="Controller tracking could not start. Check pairing and permission, then Retry tracking."
                    }
                }
                try? await Task.sleep(for:.milliseconds(500))
            }
        }
        #endif
    }
    func stop() {
        generation &+= 1
        task?.cancel(); task=nil; provider=nil; accessories=[]; devices=[]; selected=nil
        engine?.stop(completionHandler:nil); engine=nil; configured=false; previouslyTracked=false; buttonEdges=ButtonEdges(); needsButtonBaseline=true
    }
    func pose(left: Bool,fit:SenseGripFit = SenseGripFit()) -> Pose? {
        guard let provider else { return nil }
        let chirality: Accessory.Chirality = left ? .left : .right
        let anchor=provider.latestAnchors.first { $0.accessory.inherentChirality == chirality }
        guard let anchor else { lose("Connect the \(left ? "left" : "right") Sense controller."); return nil }
        guard TrackingGate.accepts(age:CACurrentMediaTime()-anchor.timestamp,
                                   fullPosition:anchor.trackingState == .positionOrientationTracked,
                                   speed:simd_length(anchor.velocity)) else {
            lose(anchor.trackingState == .positionOrientationTrackedLowAccuracy ? "Tracking is weak. Bring the controller into view." : "Controller tracking lost. Bring it into view, then Resume.")
            return nil
        }
        guard anchor.accessory.locations.contains(.grip) else { lose("This controller has no grip tracking location."); return nil }
        // Use the same passthrough alignment convention as hand anchors, so the
        // virtual handle can sit over the physical controller grip.
        let measuredGrip=anchor.coordinateSpace(for:.grip,correction:.rendered).ancestorFromSpaceTransformFloat().matrix
        let measured=Self.racketPose(fromGrip:measuredGrip,fit:fit)
        let predicted=provider.predictAnchor(for:anchor,at:CACurrentMediaTime()+0.012)
        let renderedGrip=predicted?.coordinateSpace(for:.grip,correction:.rendered).ancestorFromSpaceTransformFloat().matrix ?? measuredGrip
        let rendered=Self.racketPose(fromGrip:renderedGrip,fit:fit)
        // Anchor velocities are in its local coordinate system; include the lever
        // arm to the string-bed centre before converting into world coordinates.
        let origin=anchor.coordinateSpace(correction:.rendered).ancestorFromSpaceTransformFloat().matrix
        let velocityWorld=SenseGripFit.headVelocity(worldFromAnchor:origin,mountedPose:measured,
                                                   linear:anchor.velocity,angular:anchor.angularVelocity)
        let index=accessories.firstIndex { $0.id == anchor.accessory.id }
        if let index, devices.indices.contains(index) {
            let controller=devices[index]
            if selected !== controller {
                engine?.stop(completionHandler:nil)
                selected=controller; engine=controller.haptics?.createEngine(withLocality:.default)
                engine?.start(completionHandler:{ _ in })
                buttonEdges=ButtonEdges(); needsButtonBaseline=true
            }
        }
        previouslyTracked=true; status="Sense ready · Milo serves automatically · Trigger: start sooner · Menu: pause"
        return Pose(originFromGrip:measuredGrip,leftHand:left,measured:measured,rendered:rendered,headVelocity:velocityWorld,timestamp:anchor.timestamp)
    }
    /// Dispatch after the game has committed this frame's measured pose and
    /// controller readiness, so a newly tracked controller can actually serve.
    func dispatchButtonActions() {
        guard previouslyTracked, let selected else { return }
        let input=selected.input
        let trigger=input.buttons[.trigger]?.pressedInput.isPressed ?? false
        let menu=input.buttons[.menu]?.pressedInput.isPressed ?? false
        let edges=buttonEdges.update(trigger:trigger,menu:menu)
        // A button held while disconnected or outside tracking must not become
        // a new Serve/Resume when the controller reappears.
        if needsButtonBaseline { needsButtonBaseline=false; return }
        if edges.pause { onPause?() }
        else if edges.serve { onServe?() }
    }
    private func lose(_ message: String) {
        status=message; buttonEdges=ButtonEdges(); needsButtonBaseline=true
        if previouslyTracked { onLoss?() }; previouslyTracked=false
    }
    func impact(strength: Float) {
        guard let selected else { return }
        do {
            if engine == nil { engine=selected.haptics?.createEngine(withLocality:.default); try engine?.start() }
            guard let engine else { return }
            let pulse=CHHapticEvent(eventType:.hapticTransient,parameters:[
                .init(parameterID:.hapticIntensity,value:min(0.8,max(0.15,strength))),
                .init(parameterID:.hapticSharpness,value:0.8)],relativeTime:0)
            let pattern=try CHHapticPattern(events:[pulse],parameters:[])
            try engine.makePlayer(with:pattern).start(atTime:CHHapticTimeImmediate)
        } catch { engine=nil }
    }
}
