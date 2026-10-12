import SwiftUI
import RealityKit
import ARKit
import Observation
import QuartzCore
import simd
import ShuttleCore

enum GameMode: String, CaseIterable, Identifiable { case practice = "Practice", match = "Quick match", targets = "Target rush"; var id: Self { self } }
enum InputMode: String, CaseIterable, Identifiable {
    case hands = "Hand tracking", sense = "PS VR2 Sense"
    static var allCases: [InputMode] { [.hands,.sense] }
    var id: Self { self }
}
enum Difficulty: String, CaseIterable, Identifiable { case friendly = "Friendly", club = "Club", challenge = "Challenge"; var id: Self { self }
    var speed: Float { self == .friendly ? 2.8 : self == .club ? 3.5 : 4.6 }
    var reaction: Float { self == .friendly ? 0.20 : self == .club ? 0.14 : 0.09 }
    var error: Float { self == .friendly ? 0.05 : self == .club ? 0.025 : 0.008 }
    var returnTime: Float { self == .friendly ? 1.8 : self == .club ? 1.65 : 1.5 }
}

@MainActor @Observable
final class GameModel {
    var mode: GameMode = .practice
    var input: InputMode = .hands { didSet { controllerGripDefaults.set(input.rawValue,forKey:"ShuttleClub.input.v1") } }
    var racketKind = RacketKind(rawValue:UserDefaults.standard.string(forKey:"racket") ?? "") ?? .coral
    var showRackets = false
    var leftHand = false { didSet { controllerGripDefaults.set(leftHand,forKey:"ShuttleClub.racketHand.left.v1") } }
    var soundEnabled = true { didSet { syncAudio() } }
    var musicEnabled = true { didSet { syncAudio() } }
    var musicVolume:Float = 0.55 { didSet { syncAudio() } }
    var effectsVolume:Float = 0.65 { didSet { syncAudio() } }
    var hapticsEnabled = true
    var reducedMotion = false
    var showSettings = false
    var showCourtMenu = false
    var showPlaySetup = false
    var controllerReady = false
    private var rightControllerGripFit = SenseGripFit()
    private var leftControllerGripFit = SenseGripFit()
    var difficulty: Difficulty = .friendly
    var paused = false { didSet { syncAudio();if paused { nextServeCountdown=2;servePinch.reset() } } }
    var message = "Welcome to Shuttle Club."
    var trackingMessage = ""
    var handVisible = false
    private(set) var handRacketHeld = false
    private var rightHandGripFit = HandGripFit()
    private var leftHandGripFit = HandGripFit()
    private(set) var trackingActive = false
    var score = MatchScore()
    var targetPoints = 0
    var streak = 0
    var canServe = true
    var automaticServing = true
    private(set) var nextServeCountdown:Float = 2
    var rallyHits = 0
    var bestRally = 0
    private(set) var serveCountdown:Float = 0
    var isPreparingServe:Bool { serveCountdown > 0 }
    var rallyInProgress:Bool { isPreparingServe || flight != nil }
    private(set) var miloPhase:MiloAnimationPhase = .ready
    @ObservationIgnored var assets = SceneAssets()
    @ObservationIgnored private var subscription: EventSubscription?
    @ObservationIgnored private var frameUpdates:FrameUpdateGate?
    @ObservationIgnored private var session = ARKitSession()
    @ObservationIgnored private var hands = HandTrackingProvider()
    @ObservationIgnored private var world = WorldTrackingProvider()
    @ObservationIgnored private var sense = SenseControllers()
    @ObservationIgnored private let controllerGripDefaults:UserDefaults
    @ObservationIgnored private var lastControllerGrip:simd_float4x4?
    @ObservationIgnored private var controllerGripTimestamp:Double = 0
    @ObservationIgnored private var controllerGripLeft:Bool?
    @ObservationIgnored private var lastControllerInputTimestamp:Double?
    @ObservationIgnored private var servePinch = ServePinchGesture()
    @ObservationIgnored private var handGripTracker = HandGripTracker()
    @ObservationIgnored private var handGripGesture = HandGripGesture()
    @ObservationIgnored private var openWristFromGrip:simd_float4x4?
    @ObservationIgnored private var pendingHandHasTimestamp = false
    @ObservationIgnored private var lastHandInputTimestamp:Double?
    @ObservationIgnored private var pendingHandLeft:Bool?
    @ObservationIgnored private var heldHandLeft:Bool?
    @ObservationIgnored private var measuredRacket = matrix_identity_float4x4
    @ObservationIgnored private var previousMeasuredRacket = matrix_identity_float4x4
    @ObservationIgnored private var lastPoseTimestamp: Double = 0
    @ObservationIgnored private var trackingWasValid = false
    @ObservationIgnored private var trackingTask: Task<Void, Never>?
    @ObservationIgnored private var trackingGeneration:UInt = 0
    @ObservationIgnored private var flight: Flight?
    @ObservationIgnored private var lastHitter: Side = .milo
    @ObservationIgnored private var elapsed: Float = 0
    @ObservationIgnored private var sinceContact: Float = 10
    @ObservationIgnored private var oldHead = V3.zero
    @ObservationIgnored private var racketSpeed = V3.zero
    @ObservationIgnored private var racketAngularVelocity = V3.zero
    @ObservationIgnored private var poseValid = false
    @ObservationIgnored private var calibrated = false
    @ObservationIgnored private var trackingRunning = false
    @ObservationIgnored private var celebration: Float = 0
    @ObservationIgnored private var rallyCount = 0
    @ObservationIgnored private var pendingWrist: simd_float4x4?
    @ObservationIgnored private var wristTimestamp: CFTimeInterval = 0
    @ObservationIgnored private var demoClock: Float = 0
    @ObservationIgnored private var stepClock:Float=0
    @ObservationIgnored private var opponentTarget: V3?
    private struct MiloStroke {
        let point:V3
        let time:Float
        let stance:V3
        let face:simd_quatf
        let axis:V3
        let angularSpeed:Float
    }
    @ObservationIgnored private var miloStroke:MiloStroke?
    @ObservationIgnored private var miloStrikeBase=simd_quatf(angle:0,axis:[1,0,0])
    @ObservationIgnored private var miloRecoveryElapsed:Float = 10
    @ObservationIgnored private var miloFollowThrough:Float?
    @ObservationIgnored private var sceneActive=true
    @ObservationIgnored private var serveArmStart=simd_quatf(angle:0,axis:[1,0,0])
    @ObservationIgnored private var serveRacketStart=simd_quatf(angle:0,axis:[1,0,0])
    @ObservationIgnored private var serveFreeArmStart=simd_quatf(angle:0,axis:[1,0,0])
    private static let servePreparationDuration:Float = 0.65
    var shuttleState: Flight? { flight }
    init(gripDefaults:UserDefaults = .standard) {
        controllerGripDefaults=gripDefaults
        rightControllerGripFit=SenseGripFitStore.load(left:false,defaults:gripDefaults)
        leftControllerGripFit=SenseGripFitStore.load(left:true,defaults:gripDefaults)
        rightHandGripFit=HandGripFitStore.load(left:false,defaults:gripDefaults)
        leftHandGripFit=HandGripFitStore.load(left:true,defaults:gripDefaults)
        input=InputMode(rawValue:gripDefaults.string(forKey:"ShuttleClub.input.v1") ?? "") ?? .hands
        leftHand=gripDefaults.bool(forKey:"ShuttleClub.racketHand.left.v1")
    }
    var controllerGripFit:SenseGripFit { leftHand ? leftControllerGripFit:rightControllerGripFit }
    var canAdjustControllerGrip:Bool {
        input == .sense && (canServe || paused) && controllerReady && sceneActive &&
        lastControllerGrip != nil && controllerGripLeft == leftHand &&
        TrackingGate.accepts(age:CACurrentMediaTime()-controllerGripTimestamp,fullPosition:true,speed:0)
    }
    var controllerContactReady:Bool { input == .sense && poseValid }
    var controllerHeadVelocity:V3 { input == .sense ? racketSpeed:.zero }
    var handGripFit:HandGripFit { leftHand ? leftHandGripFit:rightHandGripFit }
    var handGripLocked:Bool { input == .hands && handGripGesture.isHeld && heldHandLeft == leftHand }
    var handAcquisitionReady:Bool {
        input == .hands && sceneActive && handVisible && pendingHandLeft == leftHand &&
        openWristFromGrip != nil && handGripGesture.isArmed &&
        TrackingGate.accepts(age:CACurrentMediaTime()-wristTimestamp,fullPosition:true,speed:0)
    }
    var canAdjustHandGrip:Bool {
        input == .hands && (canServe || paused) && sceneActive && handVisible && handRacketHeld && pendingWrist != nil && pendingHandLeft == leftHand &&
        TrackingGate.accepts(age:CACurrentMediaTime()-wristTimestamp,fullPosition:true,speed:0)
    }
    var racketReady:Bool { trackedRacketReady }
    var handHeadVelocity:V3 { input == .hands ? racketSpeed:.zero }
    struct ContactEvidence { let side:Side; let cork:V3; let stringPoint:V3; let racketPose:simd_float4x4;let headVelocity:V3;let contactVelocity:V3 }
    private(set) var lastContact: ContactEvidence?
    @ObservationIgnored private var previewContactAt: Float = 0
    @ObservationIgnored private var previewContactPosition=V3(0,1.6,-0.25)
    var collisionPreview: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--demo")
        #else
        false
        #endif
    }

    func syncAudio() {
        SoundBank.configure(musicEnabled:musicEnabled,musicVolume:musicVolume,
                            effectsVolume:soundEnabled ? effectsVolume:0,paused:paused)
    }
    func prepare() {
        endTracking()
        sceneActive=true
        trackingActive=true
        session = ARKitSession(); hands = HandTrackingProvider(); world = WorldTrackingProvider()
        assets = ClubScene.build()
        #if DEBUG
        // Move only the debug inspection scene back from the simulator camera.
        // All cork, racket and court coordinates relative to it are unchanged.
        if collisionPreview, ProcessInfo.processInfo.arguments.contains("--pause-at-contact") {
            assets.root.position.z -= 0.8
        }
        #endif
        selectRacket(racketKind)
        calibrated = false; trackingRunning = false; elapsed = 0; poseValid = false
        pendingWrist=nil; handVisible=false; controllerReady=false
        trackingMessage=input == .hands ? "Starting hand tracking…":"Connecting your Sense controller…"
        restart(); syncAudio()
        let generation=trackingGeneration
        trackingTask = Task { await startTracking(generation:generation) }
    }
    func subscribe(to content: RealityViewContent,onReady: @escaping @MainActor () -> Void = {}) {
        subscription?.cancel()
        frameUpdates?.cancel()
        let updates=FrameUpdateGate(onFrame:{ [weak self] delta in
            self?.update(Float(delta))
        },onReady:onReady)
        frameUpdates=updates
        subscription = content.subscribe(to: SceneEvents.Update.self) { event in
            updates.submit(delta:event.deltaTime)
        }
    }
    private func startTracking(generation:UInt) async {
        guard trackingActive,generation == trackingGeneration,!Task.isCancelled else { return }
        if collisionPreview { trackingMessage="Simulated hand poses · collision required"; return }
        // Snapshot these objects so a cancelled permission request cannot start
        // providers belonging to a later hand/input configuration.
        let selectedInput=input,selectedLeftHand=leftHand
        let activeSession=session,activeHands=hands,activeWorld=world
        var providers: [any DataProvider] = []
        if WorldTrackingProvider.isSupported { providers.append(activeWorld) }
        if selectedInput == .sense {
            sense.onServe = { [weak self] in
                guard let self,trackingActive,generation == trackingGeneration,input == .sense,leftHand == selectedLeftHand else { return }
                serve()
            }
            sense.onPause = { [weak self] in
                guard let self,trackingActive,generation == trackingGeneration,input == .sense,leftHand == selectedLeftHand else { return }
                handleControllerMenu()
            }
            sense.onLoss = { [weak self] in
                guard let self,trackingActive,generation == trackingGeneration,input == .sense,leftHand == selectedLeftHand else { return }
                pauseForTrackingLoss()
            }
            sense.start(session:activeSession,world:activeWorld)
            trackingRunning = true
            return
        }
        if selectedInput == .hands && HandTrackingProvider.isSupported {
            trackingMessage="Allow hand tracking when Vision Pro asks for permission."
            let permission = await activeSession.requestAuthorization(for: [.handTracking])
            guard trackingActive,generation == trackingGeneration,input == selectedInput,leftHand == selectedLeftHand,!Task.isCancelled else { return }
            if permission[.handTracking] == .allowed { providers.append(activeHands) }
            else { trackingMessage = "Allow Shuttle Club hand tracking in Settings, then choose Retry tracking."; return }
        } else if selectedInput == .hands { trackingMessage = "Hand tracking requires a physical Vision Pro.";return }
        guard trackingActive,generation == trackingGeneration,input == selectedInput,leftHand == selectedLeftHand,!Task.isCancelled,!providers.isEmpty else { return }
        do {
            try await activeSession.run(providers)
            guard trackingActive,generation == trackingGeneration,input == selectedInput,leftHand == selectedLeftHand,!Task.isCancelled else { return }
            trackingRunning = true
            if selectedInput == .hands {
                trackingMessage="Open your \(selectedLeftHand ? "left":"right") hand, then close it to grab your racket."
                for await update in activeHands.anchorUpdates {
                    guard trackingActive,generation == trackingGeneration,input == selectedInput,leftHand == selectedLeftHand,!Task.isCancelled else { break }
                    guard sceneActive else { handGripGesture.suspend();servePinch.reset();continue }
                    let anchor = update.anchor
                    if (anchor.chirality == .left) != selectedLeftHand {
                        guard update.event != .removed,anchor.isTracked,let skeleton=anchor.handSkeleton else {
                            servePinch.reset();continue
                        }
                        let thumb=skeleton.joint(.thumbTip),index=skeleton.joint(.indexFingerTip)
                        let distance:Float?=thumb.isTracked && index.isTracked ?
                            simd_distance(thumb.anchorFromJointTransform.columns.3.xyz,index.anchorFromJointTransform.columns.3.xyz):nil
                        receiveFreeHandPinch(distance:distance,timestamp:anchor.timestamp)
                        continue
                    }
                    guard update.event != .removed,anchor.isTracked else {
                        _=handGripGesture.update(curl:nil,timestamp:anchor.timestamp,now:CACurrentMediaTime())
                        receiveHandPose(nil); continue
                    }
                    let skeleton=anchor.handSkeleton
                    func measuredJoint(_ name:HandSkeleton.JointName)->HandRacketPose.Joint {
                        guard let joint=skeleton?.joint(name) else {
                            return .init(position:anchor.originFromAnchorTransform.columns.3.xyz,isTracked:false)
                        }
                        let transform=anchor.originFromAnchorTransform*joint.anchorFromJointTransform
                        return .init(position:transform.columns.3.xyz,isTracked:joint.isTracked)
                    }
                    let fingers:[(HandSkeleton.JointName,HandSkeleton.JointName)]=[
                        (.indexFingerKnuckle,.indexFingerTip),(.middleFingerKnuckle,.middleFingerTip),
                        (.ringFingerKnuckle,.ringFingerTip),(.littleFingerKnuckle,.littleFingerTip)]
                    let trackedFingers=fingers.compactMap { knuckle,tip -> (knuckle:V3,tip:V3)? in
                        let a=measuredJoint(knuckle),b=measuredJoint(tip)
                        return a.isTracked && b.isTracked ? (a.position,b.position):nil
                    }
                    let proximalFingers:[(HandSkeleton.JointName,HandSkeleton.JointName)]=[
                        (.indexFingerKnuckle,.indexFingerIntermediateBase),(.middleFingerKnuckle,.middleFingerIntermediateBase),
                        (.ringFingerKnuckle,.ringFingerIntermediateBase),(.littleFingerKnuckle,.littleFingerIntermediateBase)]
                    let trackedProximal=proximalFingers.compactMap { knuckle,intermediate -> (knuckle:V3,intermediate:V3)? in
                        let a=measuredJoint(knuckle),b=measuredJoint(intermediate)
                        return a.isTracked && b.isTracked ? (a.position,b.position):nil
                    }
                    // The tracked hand anchor is at the wrist. Retain that
                    // measured pose when finger joints become occluded.
                    let wrist=anchor.originFromAnchorTransform
                    let fallbackCurl=trackedFingers.count < 2 ?
                        HandGripGesture.proximalCurl(wrist:wrist.columns.3.xyz,trackedFingers:trackedProximal):nil
                    receiveHandInput(worldFromWrist:wrist,
                                     wristTracked:anchor.isTracked,indexKnuckle:measuredJoint(.indexFingerKnuckle),
                                     middleKnuckle:measuredJoint(.middleFingerKnuckle),littleKnuckle:measuredJoint(.littleFingerKnuckle),
                                     trackedFingers:trackedFingers,timestamp:anchor.timestamp,observedCurl:fallbackCurl)
                }
            }
        } catch {
            guard trackingActive,generation == trackingGeneration,input == selectedInput,leftHand == selectedLeftHand,!Task.isCancelled else { return }
            trackingMessage = "Tracking could not start. Check permissions, then choose Retry tracking."
        }
    }
    /// Commits a measured grip. Native anchors must pass the grab gesture first.
    /// Samples without an acquisition timestamp use the render interval for speed.
    func receiveHandPose(_ pose: simd_float4x4?, timestamp: Double? = nil,held:Bool=true) {
        guard sceneActive else { return }
        let valid=pose.flatMap { Self.usableControllerPose($0) ? $0:nil }
        pendingWrist=valid; wristTimestamp=timestamp ?? CACurrentMediaTime(); handVisible=valid != nil
        handRacketHeld=held && valid != nil;pendingHandHasTimestamp=timestamp != nil
        pendingHandLeft=valid == nil ? nil:leftHand
        if valid == nil {
            if !handGripGesture.isHeld { openWristFromGrip=nil }
            servePinch.reset();nextServeCountdown=2
            // Loss and recovery can arrive between render frames. Disarm at
            // the loss event so recovery always establishes a fresh baseline.
            pauseForTrackingLoss();trackingWasValid=false;assets.racket.isEnabled=false
            trackingMessage=handGripGesture.isHeld ? "Hand tracking lost. Bring your hand into view; your grip is kept.":"Show your racket hand with your palm open."
        }
    }
    func receiveHandInput(worldFromWrist:simd_float4x4,wristTracked:Bool,
                          indexKnuckle:HandRacketPose.Joint,middleKnuckle:HandRacketPose.Joint,littleKnuckle:HandRacketPose.Joint,
                          trackedFingers:[(knuckle:V3,tip:V3)],timestamp:Double,now:Double=CACurrentMediaTime(),observedCurl:Float?=nil) {
        guard input == .hands else { return }
        guard sceneActive else { handGripGesture.suspend();return }
        guard timestamp.isFinite,now.isFinite,now >= timestamp else {
            _=handGripGesture.update(curl:nil,timestamp:timestamp,now:now)
            receiveHandPose(nil,timestamp:timestamp,held:false);return
        }
        if let previous=lastHandInputTimestamp,timestamp <= previous {
            if timestamp < previous {
                _=handGripGesture.update(curl:nil,timestamp:timestamp,now:now)
                if !handGripGesture.isHeld { openWristFromGrip=nil }
            }
            return
        }
        lastHandInputTimestamp=timestamp
        let wristUsable=wristTracked && Self.usableControllerPose(worldFromWrist) &&
            TrackingGate.accepts(age:now-timestamp,fullPosition:true,speed:0)
        let curl=wristUsable ? (observedCurl ?? HandGripGesture.curl(wrist:worldFromWrist.columns.3.xyz,trackedFingers:trackedFingers)):nil
        guard wristUsable else {
            if !handGripGesture.isHeld { openWristFromGrip=nil }
            _=handGripGesture.update(curl:nil,timestamp:timestamp,now:now)
            receiveHandPose(nil,timestamp:timestamp,held:false);return
        }
        let preview=HandRacketPose.make(wrist:.init(position:worldFromWrist.columns.3.xyz,isTracked:true),
                                       indexKnuckle:indexKnuckle,middleKnuckle:middleKnuckle,littleKnuckle:littleKnuckle)
        // Cache the open palm frame, then attach it rigidly to the wrist when
        // the fist closes. Finger deformation never rotates a held racket.
        let completePalm=indexKnuckle.isTracked && middleKnuckle.isTracked && littleKnuckle.isTracked
        if !handGripGesture.isHeld,let preview,curl.map({$0 >= 1.65}) == true,
           completePalm || openWristFromGrip == nil {
            // An occluded side knuckle may provide an initial fallback, but
            // must not replace a complete palm frame with a different angle.
            openWristFromGrip=simd_inverse(worldFromWrist)*preview
        }
        // Closing fingers may occlude knuckles. Acquisition can use only a
        // measured wrist-local open-palm frame through a gradual closure.
        // Fresh wrist samples and the gesture's ordered dwell still gate it;
        // actual unheld tracking loss discards the acquisition mount.
        let candidateReady=openWristFromGrip != nil
        let releaseAllowed = !showCourtMenu && !showSettings && !showRackets && !showPlaySetup &&
            HandGripGesture.confidentOpenRelease(wrist:worldFromWrist.columns.3.xyz,trackedFingers:trackedFingers)
        let event=handGripGesture.update(curl:handGripGesture.isHeld || candidateReady ? curl:nil,timestamp:timestamp,now:now,
                                         releaseAllowed:releaseAllowed)
        if event == .grabbed {
            if let offset=openWristFromGrip {
                if !handGripTracker.capture(worldFromWrist:worldFromWrist,worldFromGrip:worldFromWrist*offset) { handGripGesture.reset() }
            } else { handGripGesture.reset() }
            lastPoseTimestamp=0;poseValid=false;racketSpeed = .zero;racketAngularVelocity = .zero;trackingWasValid=false
            nextServeCountdown=2;servePinch.reset()
            if handGripGesture.isHeld {
                heldHandLeft=leftHand
                message=paused ? "Racket grabbed. Resume when you're ready.":"Racket grabbed. Ready to rally."
                if soundEnabled { SoundBank.play(.select,strength:0.35,at:assets.racket) }
            }
        } else if event == .released {
            heldHandLeft=nil
            if let preview,completePalm || openWristFromGrip == nil {
                openWristFromGrip=simd_inverse(worldFromWrist)*preview
            }
            handGripTracker.reset();lastPoseTimestamp=0;poseValid=false;racketSpeed = .zero;racketAngularVelocity = .zero
            trackingWasValid=false;nextServeCountdown=2;servePinch.reset()
            if rallyInProgress { paused=true;message="Racket released. Grab it again, then Resume." }
            else { message="Racket released. Close your hand to grab again." }
            if soundEnabled { SoundBank.play(.menu,strength:0.3,at:assets.racket) }
        }
        let grip:simd_float4x4?
        if handGripGesture.isHeld {
            grip=handGripTracker.update(worldFromWrist:worldFromWrist,isTracked:true,indexKnuckle:indexKnuckle,
                                        middleKnuckle:middleKnuckle,littleKnuckle:littleKnuckle)
            trackingMessage="Racket held. Open your hand fully for a moment to release."
        } else {
            grip=openWristFromGrip.map { worldFromWrist*$0 } ?? preview
            if candidateReady,handGripGesture.isArmed {
                trackingMessage="Close your hand to grab. Once held, relax your fingers."
            } else if candidateReady {
                trackingMessage="Open your hand first, then close it to grab. Keep the bases of your fingers in view."
            } else {
                trackingMessage="Show your open palm and knuckles to place the racket."
            }
        }
        receiveHandPose(grip,timestamp:timestamp,held:handGripGesture.isHeld)
    }
    private var trackedRacketReady:Bool {
        guard sceneActive else { return false }
        if input == .sense {
            return controllerReady && controllerGripLeft == leftHand && lastControllerGrip != nil &&
                TrackingGate.accepts(age:CACurrentMediaTime()-controllerGripTimestamp,fullPosition:true,speed:0)
        }
        return handVisible && handRacketHeld && pendingHandLeft == leftHand &&
            TrackingGate.accepts(age:CACurrentMediaTime()-wristTimestamp,fullPosition:true,speed:0)
    }
    /// Only the opposite, tracked hand can request a serve. Its open/close
    /// sequence is discarded throughout play, pauses and open setup panels.
    func receiveFreeHandPinch(distance:Float?,timestamp:Double,now:Double = CACurrentMediaTime()) {
        guard input == .hands,canServe,!paused,sceneActive,trackedRacketReady,
              !showCourtMenu,!showSettings,!showRackets,!showPlaySetup else { servePinch.reset();return }
        if servePinch.update(distance:distance,timestamp:timestamp,now:now) { serve() }
    }
    private func discardTrackingSamples() {
        servePinch.reset()
        nextServeCountdown=2
        pendingWrist=nil;wristTimestamp=0;handVisible=false;handRacketHeld=false;controllerReady=false
        handGripTracker.reset();handGripGesture.reset();openWristFromGrip=nil;pendingHandHasTimestamp=false
        lastHandInputTimestamp=nil;pendingHandLeft=nil;heldHandLeft=nil
        lastPoseTimestamp=0;trackingWasValid=false;poseValid=false;racketSpeed = .zero;racketAngularVelocity = .zero;oldHead = .zero
        measuredRacket=matrix_identity_float4x4;previousMeasuredRacket=matrix_identity_float4x4
        lastControllerGrip=nil;controllerGripTimestamp=0;controllerGripLeft=nil
        lastControllerInputTimestamp=nil
        assets.racket.isEnabled=false
    }
    private func endTracking() {
        trackingGeneration &+= 1
        trackingTask?.cancel();trackingTask=nil;sense.stop();session.stop()
        trackingRunning=false;discardTrackingSamples()
    }
    /// Call after changing input or racket hand, or from a Retry tracking button.
    /// Lobby changes clear old samples without starting an ARKit session.
    func reconfigureTracking() {
        if rallyInProgress { paused=true;message="Tracking setup changed. Show your selected racket hand or controller, then Resume." }
        endTracking()
        guard trackingActive else { trackingMessage="";return }
        session=ARKitSession();hands=HandTrackingProvider();world=WorldTrackingProvider()
        trackingMessage=input == .hands ? "Starting hand tracking…":"Connecting your Sense controller…"
        let generation=trackingGeneration
        trackingTask=Task { await startTracking(generation:generation) }
    }
    func stop() {
        subscription?.cancel(); subscription = nil
        frameUpdates?.cancel();frameUpdates=nil
        trackingActive=false;endTracking();flight=nil;serveCountdown=0;canServe=true;showPlaySetup=false
        miloStroke=nil;miloFollowThrough=nil;miloPhase = .ready;assets.movement=0
        paused=false
    }
    /// A controller button cannot resume a rally behind an open court panel.
    /// The callback checks its current tracking generation and input first.
    func handleControllerMenu() {
        guard !showCourtMenu,!showSettings,!showRackets,!showPlaySetup else { return }
        guard sceneActive,!paused || trackedRacketReady else { return }
        paused.toggle()
    }
    /// Return from tracking setup to the actual court, including when setup
    /// was reached through another panel. Paused rallies still need Resume.
    func finishTrackingSetup() {
        showPlaySetup=false;showCourtMenu=false;showSettings=false;showRackets=false
        nextServeCountdown=2;servePinch.reset();handGripGesture.suspend()
        if paused {
            message=racketReady ? "Racket ready. Resume when you're comfortable.":"Show your selected racket hand, then Resume."
        } else if racketReady {
            message="Racket ready. Milo will serve after two ready seconds."
        } else {
            message=input == .hands ? "Open your \(leftHand ? "left":"right") hand, then close it to grab.":"Connect your selected controller to start."
        }
    }
    func sceneActivityChanged(active:Bool) {
        // Permission sheets can make an idle court inactive. There is no rally
        // to pause then, and a disabled Serve button would prevent starting it.
        sceneActive=active
        if !active {
            servePinch.reset();nextServeCountdown=2;handGripGesture.suspend()
            pendingWrist=nil;wristTimestamp=0;pendingHandLeft=nil;handVisible=false;handRacketHeld=false
            openWristFromGrip=nil
            lastControllerGrip=nil;controllerGripTimestamp=0;controllerGripLeft=nil;controllerReady=false
            lastPoseTimestamp=0;poseValid=false;racketSpeed = .zero;racketAngularVelocity = .zero;trackingWasValid=false
            assets.racket.isEnabled=false
        }
        guard !active,rallyInProgress else { return }
        paused=true
        message="Rally paused. Bring your racket into view, then tap Resume."
    }
    func recenter() { guard canServe else { return }; calibrated = false; calibrate(); lastPoseTimestamp=0; poseValid=false }
    func setGrip() {
        if input == .sense {
            guard canAdjustControllerGrip,let grip=lastControllerGrip else { return }
            let worldOrientation=simd_quatf(assets.root.transformMatrix(relativeTo:nil))
            var fit=controllerGripFit
            fit.pitchDegrees=0;fit.yawDegrees=0;fit.rollDegrees=0
            setControllerGripFit(fit.aligned(fromGrip:grip,desiredOrientation:worldOrientation))
            message="Controller racket angle aligned. Your fit is saved for this hand."
            return
        }
        guard canAdjustHandGrip,let wrist=pendingWrist else { return }
        let raw=simd_inverse(assets.root.transformMatrix(relativeTo:nil)) * wrist
        let gripOrientation=simd_quatf(raw)
        let desiredRacketOrientation=simd_quatf(angle:0,axis:[0,0,1])
        // Calibrate orientation in the measured grip frame, preserving its
        // palm position. The correction is applied after the grip transform.
        let fit=HandGripFit(calibratedOrientation:(gripOrientation.inverse*desiredRacketOrientation).vector).normalized()
        setHandGripFit(fit)
        message="Racket aligned from your comfortable grip. Saved for this hand."
    }
    func setHandGripFit(_ requested:HandGripFit) {
        guard canAdjustHandGrip,let wrist=pendingWrist else { return }
        guard HandGripFitStore.save(requested,left:leftHand,defaults:controllerGripDefaults) else { return }
        let fit=requested.normalized()
        if leftHand { leftHandGripFit=fit } else { rightHandGripFit=fit }
        let pose=simd_inverse(assets.root.transformMatrix(relativeTo:nil))*wrist*fit.offset
        measuredRacket=pose;previousMeasuredRacket=pose;assets.racket.transform=Transform(matrix:pose)
        lastPoseTimestamp=0;poseValid=false;racketSpeed = .zero;racketAngularVelocity = .zero;oldHead=(pose*SIMD4<Float>(0,0.37,0,1)).xyz
        nextServeCountdown=2;servePinch.reset()
    }
    func resetHandGrip() {
        guard canAdjustHandGrip else { return }
        setHandGripFit(HandGripFit())
        message="Hand racket alignment reset for this hand."
    }
    func setControllerGripFit(_ requested:SenseGripFit) {
        guard canAdjustControllerGrip,let grip=lastControllerGrip else { return }
        let fit=requested.normalized()
        if leftHand { leftControllerGripFit=fit } else { rightControllerGripFit=fit }
        SenseGripFitStore.save(fit,left:leftHand,defaults:controllerGripDefaults)
        // An adjustment is a new attachment, not a swing. Commit its current
        // measured pose and discard motion history before accepting contacts.
        let pose=simd_inverse(assets.root.transformMatrix(relativeTo:nil)) * fit.mountedPose(fromGrip:grip)
        measuredRacket=pose;previousMeasuredRacket=pose
        assets.racket.transform=Transform(matrix:pose)
        lastPoseTimestamp=0;poseValid=false;racketSpeed = .zero;racketAngularVelocity = .zero
        oldHead=(pose * SIMD4<Float>(0,0.37,0,1)).xyz
        nextServeCountdown=2;servePinch.reset()
    }
    func resetControllerGrip() {
        guard canAdjustControllerGrip else { return }
        setControllerGripFit(SenseGripFit())
        message="Controller racket fit reset for this hand."
    }
    private func calibrate() {
        guard !calibrated else { return }
        if trackingRunning, let device = world.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()), device.isTracked {
            let m = device.originFromAnchorTransform
            let yaw = atan2(m.columns.2.x, m.columns.2.z)
            assets.root.position = [m.columns.3.x, m.columns.3.y - 1.65, m.columns.3.z]
            assets.root.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0]); calibrated = true
        }
        #if targetEnvironment(simulator)
        calibrated = true
        #endif
    }
    func restart() {
        flight = nil;serveCountdown=0;nextServeCountdown=2;servePinch.reset();score = MatchScore(); targetPoints = 0; streak = 0; rallyCount = 0; rallyHits = 0; bestRally = 0
        canServe = true; paused = false; celebration = 0; showCourtMenu=false;showPlaySetup=false
        lastPoseTimestamp=0; trackingWasValid=false; poseValid=false; racketSpeed = .zero;racketAngularVelocity = .zero
        lastContact=nil;lastHitter = .milo;opponentTarget=nil;sinceContact=10;assets.movement=0;assets.robotReaction=0
        miloStroke=nil;miloFollowThrough=nil;miloRecoveryElapsed=10;miloPhase = .ready
        assets.robotArm.orientation=simd_quatf(angle:0,axis:[1,0,0]);assets.robotRacket.orientation=simd_quatf(angle:0,axis:[1,0,0])
        assets.targets.isEnabled = mode == .targets
        assets.shuttle.position = [0, 1.9, -9.4]; assets.milo.position = [0.4, 0, -8]
        message = "Show your racket. Milo will serve when you're ready."; assets.confetti.isEnabled = false
    }
    func serve() {
        guard canServe,!paused,sceneActive,mode != .match || score.winner == nil,trackedRacketReady,
              !showCourtMenu,!showSettings,!showRackets,!showPlaySetup else { return }
        rallyCount += 1
        nextServeCountdown=2
        rallyHits = 0;lastContact=nil;opponentTarget=nil;servePinch.reset()
        miloStroke=nil;miloFollowThrough=nil;miloPhase = .preparingServe
        serveArmStart=assets.robotArm.orientation;serveRacketStart=assets.robotRacket.orientation;serveFreeArmStart=assets.robotFreeArm.orientation
        serveCountdown=Self.servePreparationDuration
        lastHitter = .milo;sinceContact=0;canServe=false;assets.movement=0
        message="Milo is winding up…"
        assets.shuttle.isEnabled=true;placeShuttleAtServeStrings()
    }
    private func placeShuttleAtServeStrings() {
        assets.shuttle.position=assets.robotRacket.convert(position:[0,0.37,0],to:assets.root)
        let normal=assets.robotRacket.transformMatrix(relativeTo:assets.root).columns.2.xyz
        if simd_length(normal)>0.001 { assets.shuttle.orientation=simd_quatf(from:[0,1,0],to:-simd_normalize(normal)) }
    }
    private func updateServePreparation(_ dt:Float) {
        serveCountdown=max(0,serveCountdown-dt)
        let progress=1-serveCountdown/Self.servePreparationDuration
        if !reducedMotion {
            func ease(_ value:Float)->Float { let x=min(1,max(0,value));return x*x*(3-2*x) }
            let windup=simd_quatf(angle:-0.60,axis:[1,0,0])*simd_quatf(angle:0.22,axis:[0,0,1])
            let release=simd_quatf(angle:0.10,axis:[1,0,0])*simd_quatf(angle:0.05,axis:[0,0,1])
            assets.robotArm.orientation=progress < 0.65 ?
                simd_slerp(serveArmStart,windup,ease(progress/0.65)):
                simd_slerp(windup,release,ease((progress-0.65)/0.35))
            // The racket stays attached to Milo's visible wrist throughout.
            assets.robotRacket.orientation=simd_slerp(serveRacketStart,simd_quatf(angle:0,axis:[1,0,0]),ease(progress))
            assets.robotFreeArm.orientation=serveFreeArmStart*simd_quatf(angle:sin(progress * .pi)*0.18,axis:[0,0,1])
        } else {
            assets.robotArm.orientation=serveArmStart;assets.robotRacket.orientation=serveRacketStart
        }
        placeShuttleAtServeStrings()
        if serveCountdown > 0 { message=progress < 0.55 ? "Milo is winding up…":"Here it comes!";return }
        let target = V3(sin(Float(rallyCount) * 1.7) * 0.35, 1.6, -0.25)
        let origin=assets.robotRacket.convert(position:[0,0.37,0],to:assets.root)
        // Launch from the actual release pose, after preparation has completed.
        flight = Flight.clearanceShot(from:origin,to:target,duration:1.65)
        configurePreviewSwing()
        sinceContact=0
        message = input == .hands ? "Return the shuttle with your racket." : "Wait for the shuttle."
        if let flight { assets.shuttle.orientation=simd_quatf(from:[0,1,0],to:-simd_normalize(flight.velocity)) }
        if soundEnabled { SoundBank.play(.serve,at:assets.milo) }
        beginMiloRecovery(followThrough:false)
    }
    private func recordReturn(message: String) {
        miloStroke=mode == .targets ? nil : flight.flatMap(makeMiloStroke)
        opponentTarget=miloStroke?.stance
        if opponentTarget == nil,mode != .targets,let flight {
            let attempt=flight.advanced(0.8).position
            opponentTarget=V3(min(2.4,max(-2.4,attempt.x)),0,min(-5.65,max(-11.1,attempt.z)))
        }
        miloFollowThrough=nil;miloPhase = mode == .targets ? .ready:.anticipating
        lastHitter = .player; sinceContact = 0
        rallyHits += 1; bestRally = max(bestRally,rallyHits)
        self.message=message
        if soundEnabled { SoundBank.play(rallyHits%2 == 0 ? .hit:.hitAlt,strength:min(1,simd_length(flight?.velocity ?? .zero)/15),at:assets.shuttle) }
    }
    func selectRacket(_ kind:RacketKind) {
        guard !rallyInProgress else { return }
        if kind != racketKind,soundEnabled { SoundBank.play(.select) }
        racketKind=kind; UserDefaults.standard.set(kind.rawValue,forKey:"racket")
        assets.racket.children.forEach { $0.removeFromParent() }
        assets.racket.addChild(ClubScene.makeRacket(kind))
    }
    private func pauseForTrackingLoss() {
        servePinch.reset()
        poseValid=false; racketSpeed = .zero;racketAngularVelocity = .zero; lastPoseTimestamp=0
        if rallyInProgress { paused=true; message="Tracking paused. Bring your racket into view, then Resume." }
    }
    private func point(_ winner: Side, landing: V3, reason: String) {
        flight = nil;canServe=true;nextServeCountdown=2
        beginMiloRecovery(followThrough:false)
        assets.robotReaction = winner == .milo ? 1:0.3
        if reason.contains("Net"),soundEnabled { SoundBank.play(.net,at:assets.shuttle) }
        #if DEBUG
        print("RALLY FINISHED: \(winner), landing \(landing), \(reason)")
        #endif
        if mode == .targets {
            if winner == .player, let target = assets.targetLocations.first(where: { simd_distance(SIMD2($0.position.x, $0.position.z), SIMD2(landing.x, landing.z)) < $0.radius }) {
                streak += 1; targetPoints += target.value * min(streak, 3)
                message = "Sweet spot! +\(target.value * min(streak, 3))"; celebrate(at: landing)
            } else { streak = 0; message = "\(reason) Try another target." }
        } else {
            score.award(winner)
            if mode == .match, let winner = score.winner { message = winner == .player ? "You win! High five!" : "Milo wins this match."; canServe = false }
            else { message = winner == .player ? "Your point! \(reason)" : "Milo's point. \(reason)" }
            if winner == .player { celebrate(at: landing) } else { if soundEnabled { SoundBank.play(.miss) } }
        }
    }
    private func celebrate(at position: V3) { celebration = 1.2; assets.confetti.position = position; assets.confetti.isEnabled = true; if soundEnabled { SoundBank.play(mode == .targets ? .target:.win) } }

    private func updateAutomaticServe(_ dt:Float) {
        guard automaticServing,canServe,!paused,sceneActive,trackedRacketReady,
              !showCourtMenu,!showSettings,!showRackets,!showPlaySetup,
              mode != .match || score.winner == nil else { nextServeCountdown=2;return }
        nextServeCountdown=max(0,nextServeCountdown-dt)
        if nextServeCountdown == 0 { serve() }
    }

    func update(_ delta: Float) {
        guard delta.isFinite else { return }
        #if DEBUG
        if collisionPreview, paused, lastContact?.side == .player,
           ProcessInfo.processInfo.arguments.contains("--pause-at-contact") { return }
        #endif
        guard delta <= 0.1 else {
            pauseForTrackingLoss();trackingWasValid=false
            nextServeCountdown=2
            if rallyInProgress { message="Rally paused after an interruption. Bring your racket into view, then Resume." }
            return
        }
        let dt=max(0,delta)
        let previousRobotRacket=assets.robotRacket.transformMatrix(relativeTo:assets.root)
        previousMeasuredRacket = measuredRacket
        calibrate()
        if !collisionPreview, trackingRunning, calibrated, world.state == .running,
           world.queryDeviceAnchor(atTimestamp:CACurrentMediaTime())?.isTracked != true {
            pauseForTrackingLoss(); trackingMessage="Headset tracking lost. Wait for tracking to recover, then Resume."
            assets.racket.isEnabled=false; return
        }
        #if DEBUG
        if collisionPreview { updatePreviewHand(dt) }
        #endif
        updateRacket(dt)
        if !canServe || paused || !trackedRacketReady { servePinch.reset() }
        if rallyInProgress && !trackedRacketReady { pauseForTrackingLoss() }
        updateAutomaticServe(dt)
        guard !paused else { return }
        elapsed += dt;sinceContact += dt
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--demo") {
            demoClock += dt
            if canServe && demoClock > 2 { demoClock = 0; serve() }
        }
        #endif
        if isPreparingServe {
            updateServePreparation(dt)
            assets.animateMilo(time:elapsed,active:true,dt:dt,reducedMotion:reducedMotion,phase:miloPhase,lookTarget:assets.shuttle.position)
            return
        }
        if flight != nil,lastHitter == .player,mode != .targets { updateMiloResponse(dt) }
        else { updateMiloRecovery(dt) }
        if assets.movement > 0.5 {
            stepClock += dt
            if stepClock > 0.26 { stepClock=0; if soundEnabled { SoundBank.play(.step,strength:0.65,at:assets.milo) } }
        } else { stepClock=0 }
        if celebration > 0 {
            celebration -= dt; assets.animateConfetti(age: 1.2 - celebration)
            if celebration <= 0 { assets.confetti.isEnabled = false }
        }
        assets.animateMilo(time:elapsed,active:rallyInProgress,dt:dt,reducedMotion:reducedMotion,
                           phase:miloPhase,lookTarget:flight?.position)
        guard var ball = flight else { return }
        let previousBall=ball
        let before = ball.position; ball.step(dt)
        let fault=RallyEvents.first(from:before,to:ball.position)
        flight = ball; assets.shuttle.position = ball.position
        if simd_length(ball.velocity) > 0.1 { assets.shuttle.orientation = simd_quatf(from: [0, 1, 0], to: -simd_normalize(ball.velocity)) }
        if lastHitter == .milo, poseValid, sinceContact > 0.18,
           let returned=contactReturn(previousBall:previousBall,currentBall:ball,oldPose:previousMeasuredRacket,
                                      newPose:measuredRacket,headVelocity:racketSpeed,angularVelocity:racketAngularVelocity,kind:racketKind,dt:dt,side:.player,
                                      beforeFault:fault?.fraction) {
            flight=returned; recordReturn(message:paused ? "Paused at actual string contact" : "Racket contact!")
            resolveContactFlight(returned,hitter:.player)
            if input == .sense && hapticsEnabled { sense.impact(strength:simd_length(returned.velocity-ball.velocity)/35) }
            return
        }
        if lastHitter == .player && mode != .targets {
            let robotPose=assets.robotRacket.transformMatrix(relativeTo:assets.root)
            let oldHead=(previousRobotRacket * SIMD4<Float>(0,0.37,0,1)).xyz
            let newHead=(robotPose * SIMD4<Float>(0,0.37,0,1)).xyz
            let headVelocity=(newHead-oldHead)/max(0.005,dt)
            let angularVelocity=RacketMotion.angularVelocity(from:previousRobotRacket,to:robotPose,duration:dt)
            if sinceContact > 0.18,let returned=contactReturn(previousBall:previousBall,currentBall:ball,
                oldPose:previousRobotRacket,newPose:robotPose,headVelocity:headVelocity,angularVelocity:angularVelocity,kind:.coral,dt:dt,side:.milo,
                beforeFault:fault?.fraction) {
                beginMiloRecovery(followThrough:true)
                flight=returned; lastHitter = .milo; sinceContact=0; message="Milo made contact. Your turn!"
                resolveContactFlight(returned,hitter:.milo)
                rallyHits += 1; bestRally=max(bestRally,rallyHits)
                configurePreviewSwing()
                if soundEnabled { SoundBank.play(rallyHits%2 == 0 ? .hit:.hitAlt,strength:min(1,simd_length(flight?.velocity ?? .zero)/15),at:assets.shuttle) }
                return
            }
        }
        if let fault { resolveFault(fault,hitter:lastHitter) }
    }
    private func updateRacket(_ dt: Float) {
        guard sceneActive else { assets.racket.isEnabled=false;poseValid=false;racketSpeed = .zero;racketAngularVelocity = .zero;return }
        if input == .sense {
            receiveControllerPose(sense.pose(left:leftHand,fit:controllerGripFit));trackingMessage=sense.status
            // Read the button edge only after this sample makes Serve ready.
            sense.dispatchButtonActions()
        } else if input == .hands, pendingHandLeft == leftHand,let wrist=pendingWrist,
                  TrackingGate.accepts(age:CACurrentMediaTime()-wristTimestamp,fullPosition:true,speed:0) {
            let local=simd_inverse(assets.root.transformMatrix(relativeTo:nil)) * wrist * handGripFit.offset
            let head=(local * SIMD4<Float>(0,0.37,0,1)).xyz
            // Derive speed only from new measured anchors, never from repeated render frames.
            var sampleVelocity=V3.zero
            var sampleAngularVelocity=V3.zero
            if wristTimestamp > lastPoseTimestamp {
                let sampleInterval=pendingHandHasTimestamp ? Float(max(0.005,wristTimestamp-lastPoseTimestamp)):max(0.005,dt)
                let raw=(head-oldHead)/sampleInterval
                poseValid=handRacketHeld && lastPoseTimestamp > 0 &&
                    (pendingHandHasTimestamp || dt > 0) && simd_length(raw) < 35
                if poseValid {
                    sampleVelocity=raw
                    sampleAngularVelocity=RacketMotion.angularVelocity(from:measuredRacket,to:local,duration:sampleInterval)
                }
                lastPoseTimestamp=wristTimestamp; oldHead=head
            }
            if !trackingWasValid { previousMeasuredRacket=local }
            // Native speed uses the anchor's acquisition interval rather than
            // the render rate. Reused anchors contribute no new swing speed.
            let previousHead=(previousMeasuredRacket * SIMD4<Float>(0,0.37,0,1)).xyz
            racketSpeed=pendingHandHasTimestamp ? sampleVelocity : (poseValid && dt > 0 ? (head-previousHead)/dt:.zero)
            racketAngularVelocity=pendingHandHasTimestamp ? sampleAngularVelocity : (poseValid && dt > 0 ? RacketMotion.angularVelocity(from:previousMeasuredRacket,to:local,duration:dt):.zero)
            if !handRacketHeld { poseValid=false;racketSpeed = .zero;racketAngularVelocity = .zero }
            if simd_length(racketSpeed) >= 45 { poseValid=false;racketSpeed = .zero;racketAngularVelocity = .zero }
            measuredRacket=local; assets.racket.transform=Transform(matrix:local); assets.racket.isEnabled=true
            assets.racket.components.set(OpacityComponent(opacity:handRacketHeld ? 1:0.35))
            trackingWasValid=true
        } else {
            if input == .hands {
                handVisible=false
                if trackingWasValid || pendingWrist != nil || handGripGesture.isHeld {
                    trackingMessage=handGripGesture.isHeld ? "Hand tracking lost. Bring your hand into view; your grip is kept.":"Show your racket hand with your palm open."
                }
                if trackingWasValid { pauseForTrackingLoss() }; trackingWasValid=false
            }
            poseValid=false; assets.racket.isEnabled=false
            lastPoseTimestamp=0;racketSpeed = .zero;racketAngularVelocity = .zero
        }
    }
    /// Commits one measured accessory sample through the same display/contact
    /// path. A side change or stale sample cannot arm calibration or a hit.
    func receiveControllerPose(_ pose:SenseControllers.Pose?) {
        guard input == .sense,sceneActive else { return }
        guard let pose,pose.leftHand == leftHand,
              Self.usableControllerPose(pose.originFromGrip),Self.usableControllerPose(pose.measured),
              TrackingGate.accepts(age:CACurrentMediaTime()-pose.timestamp,fullPosition:true,speed:simd_length(pose.headVelocity)) else {
            controllerReady=false;poseValid=false;assets.racket.isEnabled=false
            pauseForTrackingLoss();racketAngularVelocity = .zero
            lastControllerGrip=nil;controllerGripTimestamp=0;controllerGripLeft=nil
            return
        }
        // Keep the high-water mark through loss, refits and foregrounding.
        // A cached or reordered packet cannot move the racket or re-arm it.
        if let previous=lastControllerInputTimestamp,pose.timestamp <= previous {
            racketSpeed = .zero;racketAngularVelocity = .zero
            return
        }
        lastControllerInputTimestamp=pose.timestamp
        controllerReady=true
        assets.racket.components.set(OpacityComponent(opacity:1))
        lastControllerGrip=pose.originFromGrip;controllerGripTimestamp=pose.timestamp;controllerGripLeft=pose.leftHand
        let inverse=simd_inverse(assets.root.transformMatrix(relativeTo:nil))
        let local=inverse * pose.measured
        racketAngularVelocity=lastPoseTimestamp > 0 ? RacketMotion.angularVelocity(from:measuredRacket,to:local,duration:Float(pose.timestamp-lastPoseTimestamp)):.zero
        measuredRacket=local
        assets.racket.transform=Transform(matrix:measuredRacket);assets.racket.isEnabled=true
        racketSpeed=(inverse * SIMD4(pose.headVelocity,0)).xyz
        poseValid=TrackingGate.accepts(age:CACurrentMediaTime()-pose.timestamp,fullPosition:true,speed:simd_length(racketSpeed))
        if lastPoseTimestamp == 0 { previousMeasuredRacket=measuredRacket;poseValid=false;racketSpeed = .zero;racketAngularVelocity = .zero }
        lastPoseTimestamp=pose.timestamp
    }
    private static func usableControllerPose(_ pose:simd_float4x4)->Bool {
        let columns=[pose.columns.0,pose.columns.1,pose.columns.2,pose.columns.3]
        guard columns.allSatisfy({$0.x.isFinite && $0.y.isFinite && $0.z.isFinite && $0.w.isFinite}),
              abs(pose.columns.0.w)<0.0001,abs(pose.columns.1.w)<0.0001,
              abs(pose.columns.2.w)<0.0001,abs(pose.columns.3.w-1)<0.0001 else { return false }
        let basis=simd_float3x3(columns:(pose.columns.0.xyz,pose.columns.1.xyz,pose.columns.2.xyz))
        return abs(simd_determinant(basis)-1)<0.01 &&
            [basis.columns.0,basis.columns.1,basis.columns.2].allSatisfy({abs(simd_length_squared($0)-1)<0.01}) &&
            abs(simd_dot(basis.columns.0,basis.columns.1))<0.01 &&
            abs(simd_dot(basis.columns.1,basis.columns.2))<0.01 &&
            abs(simd_dot(basis.columns.2,basis.columns.0))<0.01
    }
    private func contactReturn(previousBall:Flight,currentBall:Flight,oldPose:simd_float4x4,
                               newPose:simd_float4x4,headVelocity:V3,angularVelocity:V3,kind:RacketKind,dt:Float,side:Side,
                               beforeFault:Float? = nil) -> Flight? {
        guard let hit=RacketSweep.intersection(from:previousBall.position,to:currentBall.position,
                oldPose:oldPose,newPose:newPose,radiusX:kind.radiusX-0.007,
                radiusY:kind.radiusY-0.007,corkRadius:0.04) else { return nil }
        if let beforeFault,hit.fraction >= beforeFault { return nil }
        let pose=Transform(matrix:hit.pose),cork=hit.cork
        let incoming=previousBall.advanced(dt*hit.fraction).velocity
        let contactVelocity=RacketMotion.pointVelocity(headVelocity:headVelocity,angularVelocity:angularVelocity,
                                                       pose:hit.pose,contact:hit.point)
        guard contactVelocity.isFiniteVector,simd_length(contactVelocity)<45 else { return nil }
        guard let velocity=RacketImpact.rebound(incoming:incoming,headVelocity:contactVelocity,
                  normal:hit.pose.columns.2.xyz,contact:hit.point,racket:kind) else { return nil }
        let point=hit.stringPoint
        lastContact=ContactEvidence(side:side,cork:cork,stringPoint:point,racketPose:hit.pose,headVelocity:headVelocity,contactVelocity:contactVelocity)
        var result=Flight(position:cork,velocity:velocity)
        #if DEBUG
        print("STRING CONTACT: \(side), cork \(cork), strings \(point), fraction \(hit.fraction)")
        print("IMPACT MOTION: time \(elapsed), incoming \(incoming), outgoing \(velocity), centre \(headVelocity), strings \(contactVelocity)")
        if ProcessInfo.processInfo.arguments.contains("--pause-at-contact"), side == .player {
            paused=true; assets.racket.transform=pose; assets.shuttle.position=cork
            message="Paused at actual string contact"
            return result
        }
        #endif
        result.step(dt*(1-hit.fraction)); assets.shuttle.position=result.position
        return result
    }
    private func resolveContactFlight(_ returned:Flight,hitter:Side) {
        guard let contact=lastContact else { return }
        if let fault=RallyEvents.first(from:contact.cork,to:returned.position) { resolveFault(fault,hitter:hitter) }
    }
    private func resolveFault(_ event:RallyEvents.Event,hitter:Side) {
        assets.shuttle.position=event.position
        switch event.kind {
        case .net:point(hitter.other,landing:event.position,reason:"Net fault.")
        case .floor:point(Court.winner(landing:event.position,lastHitter:hitter),landing:event.position,reason:Court.contains(event.position) ? "":"Out.")
        case .out:point(hitter.other,landing:event.position,reason:"Out.")
        }
    }
    private func miloStance(for target:V3,face:simd_quatf) -> V3 {
        let scale=assets.milo.scale.x
        let wrist=target-face.act(V3(0,0.37,0))*scale
        let shoulder=assets.robotArm.position*scale
        let reach=simd_length(assets.robotRacket.position)*scale
        let height=shoulder.y+assets.robotBody.position.y*scale
        let vertical=wrist.y-height
        let horizontal=sqrt(max(0,reach*reach-vertical*vertical))
        // Place the shoulder behind the desired wrist, within the actual arm's
        // reach. Court movement stays speed-limited; an unreachable shot misses.
        return V3(min(2.4,max(-2.4,wrist.x-shoulder.x)),0,
                  min(-5.65,max(-11.1,wrist.z-horizontal-shoulder.z)))
    }
    private func makeMiloStroke(_ incoming:Flight)->MiloStroke? {
        var probe=incoming
        var fallback:MiloStroke?
        var nextAttempt:Float=0
        for index in 1...480 {
            probe.step(1/240)
            if probe.position.y < 0.65,probe.velocity.y < 0 { break }
            let time=Float(index)/240
            guard probe.position.z < Court.netZ-0.45,probe.position.z > -11.7,
                  probe.velocity.y < 0,probe.position.y <= 1.95,time > difficulty.reaction+0.14,
                  time >= nextAttempt else { continue }
            // A bounded 40 Hz planning search runs once per incoming shot.
            // Choose by the final face, reach and impulse, not body proximity.
            nextAttempt=time+0.025
            guard let stroke=planMiloStroke(sample:probe,time:time) else { continue }
            fallback=stroke
            if simd_distance(stroke.stance,assets.milo.position) <= difficulty.speed*(time-difficulty.reaction-0.10) {
                return stroke
            }
        }
        // An unreachable shot may be attempted, but movement never teleports
        // and only a real string collision can turn that attempt into a return.
        return fallback
    }
    private func planMiloStroke(sample:Flight,time:Float)->MiloStroke? {
        let shot=Flight.clearanceShot(from:sample.position,to:[0,1.6,-0.25],duration:difficulty.returnTime)
        let change=shot.velocity-sample.velocity
        guard simd_length(change)>0.1 else { return nil }
        let scale=assets.milo.scale.x,reach=simd_length(assets.robotRacket.position)*scale
        let error=V3(sin(Float(rallyHits+rallyCount)*2.39996)*difficulty.error,0,0)
        var normal=simd_normalize(change)
        var result:MiloStroke?
        for _ in 0..<3 {
            // At the intended impact the cork is one radius in front of the
            // strings. A centre-crossing plan would collide before its aim time.
            let target=sample.position-normal*0.04+error
            let face=miloFace(normal:normal,height:target.y)
            let stance=miloStance(for:target,face:face)
            let shoulder=stance+(assets.robotArm.position+assets.robotBody.position)*scale
            let wrist=target-face.act(V3(0,0.37,0))*scale
            let radial=wrist-shoulder
            guard abs(simd_length(radial)-reach)<0.015 else { return nil }
            let tangent=simd_cross(radial,normal),gain=simd_length(tangent)
            guard gain>0.02 else { return nil }
            let axis=simd_normalize(tangent),velocityPerRadian=simd_cross(axis,radial)
            let localError=face.inverse.act(-error)/scale
            let eccentricity=min(1,pow(localError.x/RacketKind.coral.radiusX,2)+pow(localError.y/RacketKind.coral.radiusY,2))
            let bounce=RacketKind.coral.restitution*(1-0.35*eccentricity)
            let transfer=(1+bounce)/(1+RacketImpact.shuttleMass/RacketKind.coral.effectiveMass)
            let speed=(simd_dot(change,normal)/transfer+simd_dot(sample.velocity,normal))/gain
            guard speed.isFinite,speed>0.1 else { return nil }
            result=MiloStroke(point:target,time:time,stance:stance,face:face,axis:axis,angularSpeed:speed)
            // Include the same tangential transfer used by the real solver.
            // This adjusts the planned face; the actual rebound is untouched.
            let relative=velocityPerRadian*speed-sample.velocity
            let tangentImpulse=(relative-normal*simd_dot(relative,normal))*0.06
            normal=simd_normalize(change-tangentImpulse)
        }
        guard let result,result.angularSpeed <= 18 else { return nil }
        return result
    }
    private func miloFace(normal:V3,height:Float)->simd_quatf {
        let face=simd_quatf(from:[0,0,1],to:simd_normalize(normal))
        let scale=assets.milo.scale.x,headLength=0.37*scale
        let reach=simd_length(assets.robotRacket.position)*scale
        let shoulderHeight=(assets.robotArm.position.y+assets.robotBody.position.y)*scale
        let yzLength=max(0.001,sqrt(normal.y*normal.y+normal.z*normal.z))
        let desiredWristHeight=shoulderHeight-reach*normal.z/yzLength
        let x=face.act(V3(1,0,0)).y,y=face.act(V3(0,1,0)).y
        let verticalRange=sqrt(x*x+y*y)
        guard verticalRange>0.001 else { return face }
        let heightFraction=min(1,max(-1,(height-desiredWristHeight)/(headLength*verticalRange)))
        let phase=atan2(x,y),roll=acos(heightFraction)-phase
        // Roll within the bed to keep a useful shoulder lever. The string
        // normal stays unchanged; high, weak-leverage shots are rejected later.
        return face*simd_quatf(angle:roll,axis:[0,0,1])
    }
    private func moveMilo(to destination:V3,speed:Float,dt:Float) {
        let difference=destination-assets.milo.position,distance=simd_length(difference)
        let travel=min(distance,max(0,speed*dt))
        if distance>0.001 { assets.milo.position += difference/distance*travel }
        assets.movement=dt>0 ? travel/dt:0
    }
    private func strokeAxisInParent(_ axis:V3)->V3 {
        let parent=assets.robotArm.parent?.transformMatrix(relativeTo:assets.root) ?? matrix_identity_float4x4
        return simd_normalize((simd_inverse(parent)*SIMD4(axis,0)).xyz)
    }
    private func updateMiloResponse(_ dt:Float) {
        if miloStroke == nil,opponentTarget == nil { updateMiloRecovery(dt);return }
        miloPhase = .anticipating;assets.movement=0
        guard sinceContact >= difficulty.reaction else { return }
        if let opponentTarget { moveMilo(to:opponentTarget,speed:difficulty.speed,dt:dt) }
        guard let stroke=miloStroke else { return }
        let headOffset=stroke.face.act(V3(0,0.37,0))*assets.milo.scale.x
        let wristTarget=stroke.point-headOffset
        let localTarget=assets.robotArm.parent?.convert(position:wristTarget,from:assets.root) ?? wristTarget
        let direction=localTarget-assets.robotArm.position
        guard simd_length(direction) > 0.01 else { return }
        miloStrikeBase=simd_quatf(from:simd_normalize(assets.robotRacket.position),to:simd_normalize(direction))
        let offset=sinceContact-stroke.time
        let angle=stroke.angularSpeed*min(0.10,max(-0.10,offset))
        let aim=simd_quatf(angle:angle,axis:strokeAxisInParent(stroke.axis))*miloStrikeBase
        if offset < -0.10 { assets.robotArm.orientation=simd_slerp(assets.robotArm.orientation,aim,min(1,dt*14)) }
        else { miloPhase = .striking;assets.robotArm.orientation=aim }
        assets.robotRacket.setOrientation(stroke.face,relativeTo:assets.root)
        if offset > 0.16 { beginMiloRecovery(followThrough:false) }
    }
    private func beginMiloRecovery(followThrough:Bool) {
        miloFollowThrough=followThrough ? miloStroke.map { sinceContact-$0.time }:nil
        if !followThrough { miloStroke=nil }
        opponentTarget=nil;miloRecoveryElapsed=0;miloPhase = followThrough ? .striking:.recovering
    }
    private func updateMiloRecovery(_ dt:Float) {
        miloRecoveryElapsed += dt
        if let offset=miloFollowThrough,let stroke=miloStroke,miloRecoveryElapsed<0.11 {
            let angle=stroke.angularSpeed*min(0.11,offset+miloRecoveryElapsed)
            assets.robotArm.orientation=simd_quatf(angle:angle,axis:strokeAxisInParent(stroke.axis))*miloStrikeBase
            assets.robotRacket.setOrientation(stroke.face,relativeTo:assets.root)
            miloPhase = .striking;assets.movement=0;return
        }
        miloFollowThrough=nil;miloStroke=nil
        moveMilo(to:[0.4,0,-8],speed:difficulty.speed*0.7,dt:dt)
        let neutral=simd_quatf(angle:0,axis:[1,0,0])
        assets.robotArm.orientation=simd_slerp(assets.robotArm.orientation,neutral,min(1,dt*8))
        assets.robotRacket.orientation=simd_slerp(assets.robotRacket.orientation,neutral,min(1,dt*8))
        let settled=assets.movement<0.02 && abs(simd_dot(assets.robotArm.orientation.vector,neutral.vector))>0.9995
        miloPhase=settled ? .ready:.recovering
        if flight == nil,assets.robotReaction>0.3 { miloPhase = .celebrating }
    }
    private func configurePreviewSwing() {
        guard collisionPreview, let flight else { return }
        var probe=flight
        for index in 0..<600 {
            if probe.position.z >= -0.25 {
                previewContactAt=elapsed+Float(index)/240; previewContactPosition=probe.position; return
            }
            probe.step(1/240)
            if probe.position.y < 0.1 { break }
        }
    }
    #if DEBUG
    static func previewHandPose(contact:V3,contactAt:Float,elapsed:Float,delta:Float,miss:Float=0)->simd_float4x4 {
        // The measured pose belongs to the same interval endpoint as the
        // shuttle. Sampling its start would distort speed on variable frames.
        let time=min(0.14,max(-0.09,elapsed+delta-contactAt))
        let centre=contact+V3(miss,3.3*time,-4.4*time)
        let rotation=simd_quatf(angle:0.6,axis:[1,0,0])
        var pose=simd_float4x4(rotation)
        pose.columns.3=SIMD4(centre-rotation.act(V3(0,0.37,0)),1)
        return pose
    }
    private func updatePreviewHand(_ dt:Float) {
        guard collisionPreview else { return }
        let miss:Float=ProcessInfo.processInfo.arguments.contains("--demo-miss") ? 0.8 : 0
        let pose=Self.previewHandPose(contact:previewContactPosition,contactAt:previewContactAt,
                                      elapsed:elapsed,delta:dt,miss:miss)
        receiveHandPose(assets.root.transformMatrix(relativeTo:nil)*pose)
    }
    #endif

}

extension SIMD4 where Scalar == Float { var xyz: SIMD3<Float> { [x,y,z] } }
