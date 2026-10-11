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

    /// Invalid measured motion is tracking loss, rather than a stationary
    /// racket. Check raw angular velocity before the fit helper's safe fallback.
    static func validatedHeadVelocity(worldFromAnchor:simd_float4x4,mountedPose:simd_float4x4,
                                      linear:V3,angular:V3,fullPosition:Bool,age:Double)->V3? {
        guard linear.isFiniteVector,angular.isFiniteVector,simd_length(angular).isFinite,
              TrackingGate.accepts(age:age,fullPosition:fullPosition,speed:simd_length(linear)) else { return nil }
        let velocity=SenseGripFit.headVelocity(worldFromAnchor:worldFromAnchor,mountedPose:mountedPose,
                                               linear:linear,angular:angular)
        return velocity.isFiniteVector && TrackingGate.accepts(age:age,fullPosition:fullPosition,
                                                               speed:simd_length(velocity)) ? velocity:nil
    }

    /// Bound automatic recovery for one connected-device snapshot. A failed
    /// session start can stop the shared world provider, which cannot be rerun.
    struct RefreshGate {
        private(set) var requiresRetry = false
        private var recoveredStop = false

        mutating func shouldRefresh(connectionChanged:Bool,configured:Bool,
                                    providerStopped:Bool,worldStopped:Bool)->Bool {
            if worldStopped { requiresRetry=true;return false }
            if connectionChanged {
                requiresRetry=false;recoveredStop=false
                return true
            }
            guard !requiresRetry else { return false }
            if providerStopped {
                guard !recoveredStop else { requiresRetry=true;return false }
                recoveredStop=true
                return true
            }
            return !configured
        }

        mutating func failed() { requiresRetry=true }
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
            var refreshGate=RefreshGate()
            while !Task.isCancelled, generation == run {
                let connected=GCController.controllers().filter { $0.productCategory == GCProductCategorySpatialController }
                let identifiers=Set(connected.map(ObjectIdentifier.init))
                if refreshGate.shouldRefresh(connectionChanged:identifiers != known,configured:configured,
                    providerStopped:provider?.state == .stopped,worldStopped:world.state == .stopped) {
                    known=identifiers
                    configured=false;selected=nil
                    engine?.stop(completionHandler:nil); engine=nil; buttonEdges=ButtonEdges(); needsButtonBaseline=true
                    lose("Updating controller tracking…")
                    do {
                        var loaded:[Accessory]=[]
                        for device in connected {
                            loaded.append(try await Accessory(device:device))
                            guard !Task.isCancelled, generation == run else { return }
                        }
                        guard !Task.isCancelled, generation == run else { return }
                        // A connection can change while Accessory construction
                        // suspends. Do not publish or run that outdated snapshot.
                        let current=GCController.controllers().filter { $0.productCategory == GCProductCategorySpatialController }
                        if Set(current.map(ObjectIdentifier.init)) != identifiers { continue }
                        guard world.state != .stopped else {
                            refreshGate.failed()
                            status="Tracking stopped. Choose Retry tracking to reconnect."
                            continue
                        }
                        let nextProvider:AccessoryTrackingProvider
                        if let provider, provider.state == .running || provider.state == .paused,
                           #available(visionOS 27.0, *) {
                            try await provider.updateAccessories(loaded)
                            nextProvider=provider
                        } else {
                            let next=AccessoryTrackingProvider(accessories:loaded)
                            try await session.run([world,next])
                            nextProvider=next
                        }
                        guard !Task.isCancelled, generation == run else { return }
                        provider=nextProvider
                        let latest=GCController.controllers().filter { $0.productCategory == GCProductCategorySpatialController }
                        if Set(latest.map(ObjectIdentifier.init)) != identifiers { continue }
                        // Publish one matching device/accessory snapshot only
                        // after ARKit's atomic update or session start succeeds.
                        devices=connected;accessories=loaded
                        configured=true
                        status=connected.isEmpty ? "Pair PS VR2 Sense in Settings → Bluetooth." : "Hold your selected controller where Vision Pro can see it."
                    } catch {
                        guard !Task.isCancelled, generation == run else { return }
                        refreshGate.failed()
                        configured=false
                        status="Controller tracking could not start. Check pairing and permission, then Retry tracking."
                    }
                } else if refreshGate.requiresRetry {
                    configured=false
                    lose("Tracking stopped. Choose Retry tracking to reconnect.")
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
        guard configured,let provider else { return nil }
        guard provider.state == .running else {
            lose(provider.state == .stopped ? "Tracking stopped. Choose Retry tracking to reconnect." : "Controller tracking paused. Wait for tracking, then Resume.")
            return nil
        }
        let chirality: Accessory.Chirality = left ? .left : .right
        let anchor=provider.latestAnchors.first { $0.accessory.inherentChirality == chirality }
        guard let anchor else { lose("Connect the \(left ? "left" : "right") Sense controller."); return nil }
        let sampleAge=CACurrentMediaTime()-anchor.timestamp
        guard anchor.velocity.isFiniteVector,anchor.angularVelocity.isFiniteVector,
              simd_length(anchor.angularVelocity).isFinite,
              TrackingGate.accepts(age:sampleAge,
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
        guard let velocityWorld=Self.validatedHeadVelocity(worldFromAnchor:origin,mountedPose:measured,
            linear:anchor.velocity,angular:anchor.angularVelocity,
            fullPosition:anchor.trackingState == .positionOrientationTracked,age:sampleAge) else {
            lose("Controller motion is unreliable. Bring it into view, then Resume.")
            return nil
        }
        guard let index=accessories.firstIndex(where:{ $0.id == anchor.accessory.id }),
              devices.indices.contains(index) else {
            lose("Controller connection changed. Wait for tracking to reconnect.")
            return nil
        }
        let controller=devices[index]
        if selected !== controller {
            engine?.stop(completionHandler:nil)
            selected=controller; engine=controller.haptics?.createEngine(withLocality:.default)
            engine?.start(completionHandler:{ _ in })
            buttonEdges=ButtonEdges(); needsButtonBaseline=true
        }
        previouslyTracked=true; status="Sense ready · Milo serves automatically · Trigger: start sooner · Menu: pause"
        return Pose(originFromGrip:measuredGrip,leftHand:left,measured:measured,rendered:rendered,headVelocity:velocityWorld,timestamp:anchor.timestamp)
    }
    /// Dispatch after the game has committed this frame's measured pose and
    /// controller readiness, so a newly tracked controller can actually serve.
    func dispatchButtonActions() {
        guard configured,previouslyTracked, let selected else { return }
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
