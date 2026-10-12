import Testing
import QuartzCore
import simd
import ShuttleCore
import RealityKit
@testable import ShuttleClub

@MainActor @Suite(.serialized)
struct GameLoopTests {
    func wrist(at centre:V3,angle:Float=0) -> simd_float4x4 {
        let q=simd_quatf(angle:angle,axis:[1,0,0]); var pose=simd_float4x4(q)
        pose.columns.3=SIMD4(centre-q.act([0,0.37,0]),1); return pose
    }
    func game(_ mode:GameMode = .practice) -> GameModel {
        let defaults=UserDefaults(suiteName:"ShuttleClub.GameLoopTests")!
        defaults.removePersistentDomain(forName:"ShuttleClub.GameLoopTests")
        let g=GameModel(gripDefaults:defaults);g.automaticServing=false; g.mode=mode; g.input = .hands; g.leftHand=false;g.musicEnabled=false; g.soundEnabled=false; g.racketKind = .coral
        ClubScene.robot(g.assets); g.assets.root.addChild(g.assets.milo); g.assets.milo.scale=[1.35,1.35,1.35]
        g.assets.root.addChild(g.assets.racket); g.assets.root.addChild(g.assets.shuttle)
        g.restart(); g.receiveHandPose(wrist(at:[2,1.6,-0.25])); return g
    }
    func finishIncoming(_ g:GameModel) {
        advanceServe(g)
        for _ in 0..<800 { g.receiveHandPose(wrist(at:[2,1.6,-0.25])); g.update(1/120); if g.shuttleState == nil { return } }
    }
    func advanceServe(_ g:GameModel) {
        for _ in 0..<160 {
            guard g.isPreparingServe,!g.paused else { return }
            g.receiveHandPose(wrist(at:[2,1.6,-0.25]));g.update(1/120)
        }
    }
    func beginIncoming(_ g:GameModel) {
        g.receiveHandPose(wrist(at:[2,1.6,-0.25]));g.serve();advanceServe(g)
    }
    func swingIntoServe(_ g:GameModel,miss:Float=0,dt:Float=1/120,strength:Float=1) {
        advanceServe(g)
        guard let flight=g.shuttleState else { return }
        var probe=flight; var time:Float=0
        for _ in 0..<600 { if probe.position.z >= -0.25 { break }; probe.step(1/240); time += 1/240 }
        let contact=probe.position
        for index in 0..<600 {
            // This pose is the interval endpoint rendered after update(dt),
            // matching the ball endpoint rather than lagging a frame behind.
            let u=min(0.12,max(-0.12,Float(index+1)*dt-time))
            // A measured 5 m/s clear, rather than relying on wall-clock
            // fixture timing to inflate a slower 3 m/s net shot.
            g.receiveHandPose(wrist(at:contact+[miss,3*u*strength,-4*u*strength],angle:0.6)); g.update(dt)
            if g.lastContact?.side == .player || g.shuttleState == nil { return }
        }
    }
    @Test func missedServeAwardsOnePointAndCanRestart() {
        let g=game(); g.serve(); #expect(!g.canServe); finishIncoming(g)
        #expect(g.score.milo == 1); #expect(g.score.player == 0); #expect(g.canServe); #expect(g.lastContact == nil)
        g.restart(); #expect(g.score.milo == 0); #expect(g.canServe)
    }
    @Test func pauseFreezesShuttleAndResumeContinues() {
        let g=game();beginIncoming(g);g.update(0.03);let before=g.shuttleState!.position;g.paused=true
        for _ in 0..<100 { g.update(0.03) }
        #expect(g.shuttleState!.position == before); g.paused=false; g.update(0.03)
        #expect(simd_distance(g.shuttleState!.position,before)>0.01)
    }
    @Test func controllerMenuCannotResumeShuttleBehindAnyCourtPanel() throws {
        let openPanels:[(GameModel)->Void]=[
            { $0.showCourtMenu=true },{ $0.showSettings=true },
            { $0.showRackets=true },{ $0.showPlaySetup=true }]
        for open in openPanels {
            let g=game();beginIncoming(g);g.paused=true;open(g)
            let before=try #require(g.shuttleState).position
            g.handleControllerMenu()
            g.receiveHandPose(wrist(at:[2,1.6,-0.25]));g.update(0.03)
            let after=try #require(g.shuttleState).position
            #expect(g.paused)
            #expect(after == before)
            #expect(g.lastContact == nil && g.score.player == 0 && g.score.milo == 0)
        }
    }
    @Test func controllerMenuNormallyPausesAndResumesTrackedFlight() throws {
        let g=game();beginIncoming(g)
        let before=try #require(g.shuttleState).position
        g.handleControllerMenu()
        g.receiveHandPose(wrist(at:[2,1.6,-0.25]));g.update(0.03)
        let frozen=try #require(g.shuttleState).position
        #expect(g.paused)
        #expect(frozen == before)
        g.handleControllerMenu()
        g.receiveHandPose(wrist(at:[2,1.6,-0.25]));g.update(0.03)
        let resumed=try #require(g.shuttleState).position
        #expect(!g.paused)
        #expect(simd_distance(resumed,before)>0.01)
    }
    @Test func stoppingPausedFlightClearsRallyAndAllowsAFreshServe() throws {
        let g=game();beginIncoming(g);g.paused=true
        let active=try #require(g.shuttleState)
        #expect(active.position.y > 0)
        g.stop()
        g.update(0.03)
        #expect(!g.paused && !g.rallyInProgress && g.shuttleState == nil)
        #expect(!g.handVisible && !g.controllerReady)
        g.serve();#expect(!g.isPreparingServe)
        g.receiveHandPose(wrist(at:[2,1.6,-0.25]));g.serve()
        #expect(g.isPreparingServe && g.shuttleState == nil)
    }
    @Test func permissionInterruptionDoesNotDisableAnIdleServe() {
        let g=game();g.sceneActivityChanged(active:false)
        #expect(g.canServe);#expect(!g.paused)
        g.sceneActivityChanged(active:true);g.receiveHandPose(wrist(at:[2,1.6,-0.25]));g.serve()
        #expect(g.isPreparingServe);#expect(g.shuttleState == nil);#expect(!g.canServe)
    }
    @Test func serveWindupKeepsCorkAtVisibleStringsAndLaunchesFromReleasePose() throws {
        let g=game();let initialArm=g.assets.robotArm.orientation
        g.serve();#expect(g.isPreparingServe);#expect(g.rallyInProgress);#expect(g.shuttleState == nil)
        #expect(abs(g.serveCountdown-0.65)<0.0001)
        let requested=g.serveCountdown;g.serve();#expect(g.serveCountdown == requested)
        for _ in 0..<25 {
            g.receiveHandPose(wrist(at:[2,1.6,-0.25]));g.update(1/120)
            let strings=g.assets.robotRacket.convert(position:[0,0.37,0],to:g.assets.root)
            #expect(simd_distance(g.assets.shuttle.position,strings)<0.0001)
            #expect(g.shuttleState == nil);#expect(g.lastContact == nil);#expect(g.rallyHits == 0)
        }
        #expect(g.serveCountdown>0.4);#expect(g.serveCountdown<requested)
        #expect(abs(simd_dot(initialArm.vector,g.assets.robotArm.orientation.vector))<0.999)
        advanceServe(g)
        let launched=try #require(g.shuttleState)
        let releaseStrings=g.assets.robotRacket.convert(position:[0,0.37,0],to:g.assets.root)
        #expect(!g.isPreparingServe);#expect(!g.canServe)
        #expect(simd_distance(launched.position,releaseStrings)<0.0001)
        #expect(simd_distance(g.assets.shuttle.position,releaseStrings)<0.0001)
        #expect(launched.velocity.z>0);#expect(g.lastContact == nil)
    }
    @Test func pauseAndTrackingLossFreezeServePreparationUntilExplicitResume() {
        let g=game();g.serve();g.update(0.05)
        let countdown=g.serveCountdown,position=g.assets.shuttle.position
        let arm=g.assets.robotArm.orientation
        g.paused=true
        for _ in 0..<30 { g.receiveHandPose(wrist(at:[2,1.6,-0.25]));g.update(0.03) }
        #expect(g.serveCountdown == countdown);#expect(g.assets.shuttle.position == position)
        #expect(g.assets.robotArm.orientation.vector == arm.vector);#expect(g.shuttleState == nil)
        g.paused=false;g.receiveHandPose(wrist(at:[2,1.6,-0.25]));g.update(0.03)
        #expect(g.serveCountdown<countdown)
        let interrupted=g.serveCountdown
        g.receiveHandPose(nil);g.update(0.03)
        #expect(g.paused);#expect(g.serveCountdown == interrupted)
        g.receiveHandPose(wrist(at:[2,1.6,-0.25]));g.update(0.03)
        #expect(g.paused);#expect(g.serveCountdown == interrupted)
        g.paused=false;advanceServe(g);#expect(g.shuttleState != nil);#expect(g.lastContact == nil)
    }
    @Test func preparationCannotResumeWithSamplesFromPreviousRacketHand() {
        let g=game();g.serve();g.update(0.05);let countdown=g.serveCountdown
        g.leftHand=true;g.reconfigureTracking()
        #expect(g.paused);#expect(!g.handVisible)
        // Even an attempted Resume cannot use the invalidated old-hand sample.
        g.paused=false;g.update(0.03)
        #expect(g.paused);#expect(g.serveCountdown == countdown);#expect(g.shuttleState == nil)
        g.receiveHandPose(wrist(at:[2,1.6,-0.25]));g.update(0.03)
        #expect(g.paused);#expect(g.serveCountdown == countdown)
        g.paused=false;advanceServe(g)
        #expect(g.shuttleState != nil);#expect(g.rallyHits == 0);#expect(g.lastContact == nil)
    }
    @Test func inactivityAndRestartCannotLeakAPendingServe() {
        let g=game();g.serve();g.update(0.05);let countdown=g.serveCountdown
        g.sceneActivityChanged(active:false);g.sceneActivityChanged(active:true)
        g.receiveHandPose(wrist(at:[2,1.6,-0.25]));g.update(0.05)
        #expect(g.paused);#expect(g.serveCountdown == countdown);#expect(g.shuttleState == nil)
        g.restart();#expect(!g.paused);#expect(g.canServe);#expect(!g.rallyInProgress)
        for _ in 0..<30 { g.receiveHandPose(wrist(at:[2,1.6,-0.25]));g.update(0.05) }
        #expect(g.shuttleState == nil);#expect(!g.isPreparingServe)
        g.serve();#expect(g.isPreparingServe);g.stop()
        #expect(!g.rallyInProgress);#expect(g.canServe)
    }
    func deliberateFreeHandPinch(_ g:GameModel,start:Double=100) {
        let samples:[(Double,Float)]=[(0,0.05),(0.02,0.01),(0.07,0.01),(0.12,0.01),(0.17,0.01)]
        for (offset,distance) in samples {
            g.receiveHandPose(wrist(at:[2,1.6,-0.25]))
            g.receiveFreeHandPinch(distance:distance,timestamp:start+offset,now:start+offset)
        }
    }
    @Test func deliberateFreeHandPinchStartsOneServeAndHeldPinchCannotReplayPoint() {
        let g=game();deliberateFreeHandPinch(g)
        #expect(g.isPreparingServe);#expect(!g.canServe)
        let countdown=g.serveCountdown
        g.receiveFreeHandPinch(distance:0.01,timestamp:100.22,now:100.22)
        #expect(g.serveCountdown == countdown)
        finishIncoming(g);#expect(g.canServe);#expect(g.score.milo == 1)
        for offset in [0.0,0.05,0.1,0.15] {
            g.receiveHandPose(wrist(at:[2,1.6,-0.25]))
            g.receiveFreeHandPinch(distance:0.01,timestamp:102+offset,now:102+offset)
        }
        #expect(!g.isPreparingServe);#expect(g.shuttleState == nil)
        deliberateFreeHandPinch(g,start:103);#expect(g.isPreparingServe)
    }
    @Test func freeHandPinchNeedsRacketTrackingAndMustRearmAfterSetup() {
        let g=game();g.receiveHandPose(nil)
        for (offset,distance):(Double,Float) in [(0,0.05),(0.02,0.01),(0.07,0.01),(0.12,0.01),(0.17,0.01)] {
            g.receiveFreeHandPinch(distance:distance,timestamp:100+offset,now:100+offset)
        }
        #expect(!g.isPreparingServe)
        g.showPlaySetup=true;deliberateFreeHandPinch(g,start:101)
        #expect(!g.isPreparingServe);g.showPlaySetup=false
        for offset in [0.0,0.05,0.1,0.15] {
            g.receiveHandPose(wrist(at:[2,1.6,-0.25]))
            g.receiveFreeHandPinch(distance:0.01,timestamp:102+offset,now:102+offset)
        }
        #expect(!g.isPreparingServe)
        deliberateFreeHandPinch(g,start:103);#expect(g.isPreparingServe)
    }
    @Test func pinchCannotCarryAnInactiveOpenHandIntoForegroundServe() {
        let g=game();g.sceneActivityChanged(active:false)
        g.receiveFreeHandPinch(distance:0.05,timestamp:100,now:100)
        g.receiveFreeHandPinch(distance:0.01,timestamp:100.05,now:100.05)
        g.sceneActivityChanged(active:true)
        for offset in [0.1,0.15,0.2,0.25] {
            g.receiveHandPose(wrist(at:[2,1.6,-0.25]))
            g.receiveFreeHandPinch(distance:0.01,timestamp:100+offset,now:100+offset)
        }
        #expect(!g.isPreparingServe)
        deliberateFreeHandPinch(g,start:101);#expect(g.isPreparingServe)
    }
    func advanceReady(_ g:GameModel,seconds:Float) {
        var remaining=seconds
        while remaining>0 {
            let dt=min(0.05,remaining);remaining -= dt
            g.receiveHandPose(wrist(at:[2,1.6,-0.25]));g.update(dt)
        }
    }
    @Test(arguments:[GameMode.practice,.targets])
    func automaticServeWaitsForReadinessAndFeedsAnotherPoint(mode:GameMode) {
        let g=game(mode);g.automaticServing=true
        advanceReady(g,seconds:1.9)
        #expect(g.canServe);#expect(!g.isPreparingServe);#expect(g.nextServeCountdown>0)
        advanceReady(g,seconds:0.15);#expect(g.isPreparingServe)
        finishIncoming(g);#expect(g.canServe)
        if mode == .practice { #expect(g.score.milo == 1) }
        else { #expect(g.targetPoints == 0);#expect(g.streak == 0) }
        #expect(g.nextServeCountdown == 2)
        advanceReady(g,seconds:1.9);#expect(!g.isPreparingServe)
        advanceReady(g,seconds:0.15);#expect(g.isPreparingServe)
    }
    @Test func automaticServeReadinessResetsForLossPausePanelAndBackground() {
        let g=game();g.automaticServing=true
        advanceReady(g,seconds:1.9);g.receiveHandPose(nil);g.update(0.05)
        #expect(g.nextServeCountdown == 2);#expect(!g.isPreparingServe)
        g.showCourtMenu=true;advanceReady(g,seconds:2.1)
        #expect(!g.isPreparingServe);#expect(g.nextServeCountdown == 2)
        g.showCourtMenu=false;g.paused=true;advanceReady(g,seconds:2.1)
        #expect(!g.isPreparingServe);g.paused=false
        g.sceneActivityChanged(active:false);advanceReady(g,seconds:2.1)
        #expect(!g.isPreparingServe);#expect(g.nextServeCountdown == 2)
        g.sceneActivityChanged(active:true);advanceReady(g,seconds:2.05)
        #expect(g.isPreparingServe)
    }
    @Test func automaticServeStopsAtMatchWinnerAndRestartRestoresReadiness() {
        let g=game(.match)
        for _ in 0..<7 { g.receiveHandPose(wrist(at:[2,1.6,-0.25]));g.serve();finishIncoming(g) }
        g.automaticServing=true;advanceReady(g,seconds:3)
        #expect(g.score.winner == .milo);#expect(!g.rallyInProgress)
        g.restart();advanceReady(g,seconds:1.9);#expect(!g.isPreparingServe)
        advanceReady(g,seconds:0.15);#expect(g.isPreparingServe)
    }
    @Test func controllerTriggerCannotServeBehindPanelsOrInactiveScene() {
        let g=game();g.input = .sense
        func trackedController() {
            let grip=matrix_identity_float4x4,mounted=g.controllerGripFit.mountedPose(fromGrip:grip)
            g.receiveControllerPose(.init(originFromGrip:grip,leftHand:false,measured:mounted,rendered:mounted,headVelocity:.zero,timestamp:CACurrentMediaTime()))
        }
        trackedController()
        g.showCourtMenu=true;g.serve();#expect(!g.isPreparingServe)
        g.showCourtMenu=false;g.showPlaySetup=true;g.serve();#expect(!g.isPreparingServe)
        g.showPlaySetup=false;g.showSettings=true;g.serve();#expect(!g.isPreparingServe)
        g.showSettings=false;g.showRackets=true;g.serve();#expect(!g.isPreparingServe)
        g.showRackets=false;g.sceneActivityChanged(active:false);g.serve();#expect(!g.isPreparingServe)
        g.sceneActivityChanged(active:true);trackedController();g.serve();#expect(g.isPreparingServe)
    }
    @Test func slowFrameUsesItsActualTimeAndInterruptionRequiresResume() throws {
        let a=game(),b=game();beginIncoming(a);beginIncoming(b)
        a.receiveHandPose(wrist(at:[2,1.6,-0.25]));a.update(0.08)
        for _ in 0..<8 { b.receiveHandPose(wrist(at:[2,1.6,-0.25]));b.update(0.01) }
        #expect(simd_distance(try #require(a.shuttleState).position,try #require(b.shuttleState).position)<0.005)
        let before=try #require(a.shuttleState).position,robot=a.assets.milo.position
        a.update(0.11);#expect(a.paused);#expect(a.shuttleState?.position == before)
        a.receiveHandPose(wrist(at:[2,1.6,-0.25]));a.update(0.03)
        #expect(a.shuttleState?.position == before);#expect(a.assets.milo.position == robot)
        a.paused=false;a.update(0.03);#expect(a.shuttleState?.position != before)
    }
    @Test func heldRacketHasZeroSwingSpeedAndContactBeforeFloorWinsFrame() throws {
        let g=game();beginIncoming(g)
        for _ in 0..<600 {
            let ball=try #require(g.shuttleState)
            if ball.position.y<0.16 && ball.velocity.y<0 { break }
            g.receiveHandPose(wrist(at:[2,1.6,-0.25]));g.update(1/240)
        }
        let ball=try #require(g.shuttleState),future=ball.advanced(0.012).position
        let centre=V3(future.x,0.045,future.z),now=CACurrentMediaTime()
        g.receiveHandPose(wrist(at:centre-[0,0.05,0],angle:.pi/2),timestamp:now-0.03);g.update(0)
        g.receiveHandPose(wrist(at:centre-[0,0.05,0],angle:.pi/2),timestamp:now-0.02);g.update(0)
        g.receiveHandPose(wrist(at:centre,angle:.pi/2),timestamp:now-0.01);g.update(0.005)
        // The same measured anchor is held while the cork approaches its plane.
        g.update(0.08)
        let contact=try #require(g.lastContact)
        #expect(contact.side == .player);#expect(contact.headVelocity == .zero)
        #expect(simd_distance(contact.cork,contact.stringPoint)<=0.045)
        #expect(g.score.milo == 0);#expect(g.shuttleState != nil)
    }
    @Test(arguments:[Float(5.5),Float(36)])
    func timestampLessHandMotionUsesRenderIntervalAndRetainsSpeedLimit(speed:Float) {
        let g=game(),dt=Float(1)/30,start=V3(2,1.6,-0.25)
        // Establish a motion baseline without advancing the scene. A zero
        // duration must never interpret placement as a measured swing.
        g.receiveHandPose(wrist(at:start));g.update(0)
        #expect(g.handHeadVelocity == .zero)
        g.receiveHandPose(wrist(at:start));g.update(dt)
        g.receiveHandPose(wrist(at:start+[0,speed*dt,0]));g.update(dt)
        if speed<35 {
            #expect(simd_distance(g.handHeadVelocity,V3(0,speed,0))<0.001)
        } else {
            #expect(g.handHeadVelocity == .zero)
            #expect(g.lastContact == nil)
        }
    }
    #if DEBUG
    @Test(arguments:[false,true])
    func previewSwingUsesFrameEndpointsAndStillRequiresStringContact(miss:Bool) throws {
        let g=game();beginIncoming(g)
        var probe=try #require(g.shuttleState),contactAt:Float=0
        for _ in 0..<600 {
            if probe.position.z >= -0.25 { break }
            probe.step(1/240);contactAt += 1/240
        }
        let contact=probe.position,offset:Float=miss ? 0.8:0
        let initial=GameModel.previewHandPose(contact:contact,contactAt:contactAt,elapsed:0,delta:0,miss:offset)
        g.receiveHandPose(initial);g.update(0)
        let intervals:[Float]=[1/30,1/60,1/90]
        var elapsed:Float=0,measuredFrames=0
        for index in 0..<300 {
            let dt=intervals[index%intervals.count]
            let pose=GameModel.previewHandPose(contact:contact,contactAt:contactAt,elapsed:elapsed,delta:dt,miss:offset)
            g.receiveHandPose(pose);g.update(dt)
            // Only the unclamped portion is the deliberate 5.5 m/s swing.
            if elapsed-contactAt >= -0.09,elapsed+dt-contactAt <= 0.14 {
                #expect(simd_distance(g.handHeadVelocity,V3(0,3.3,-4.4))<0.001)
                measuredFrames += 1
            }
            elapsed += dt
            if g.lastContact?.side == .player || g.shuttleState == nil { break }
        }
        #expect(measuredFrames>0)
        if miss {
            #expect(g.lastContact == nil && g.rallyHits == 0 && g.score.milo == 1)
        } else {
            let hit=try #require(g.lastContact)
            #expect(hit.side == .player && g.rallyHits == 1)
            #expect(simd_distance(hit.cork,hit.stringPoint)<=0.040006)
            #expect(simd_distance(hit.headVelocity,V3(0,3.3,-4.4))<0.001)
        }
    }
    #endif
    @Test func miloMovementAndStrokeFreezeDuringPauseAndThenRecover() throws {
        let g=game();g.serve();swingIntoServe(g)
        #expect(g.lastContact?.side == .player)
        let startingPosition=g.assets.milo.position
        advanceReady(g,seconds:0.25)
        #expect(simd_distance(g.assets.milo.position,startingPosition)>0.02)
        let position=g.assets.milo.position,arm=g.assets.robotArm.orientation.vector,racket=g.assets.robotRacket.orientation.vector
        g.paused=true;advanceReady(g,seconds:0.5)
        #expect(g.assets.milo.position == position);#expect(g.assets.robotArm.orientation.vector == arm)
        #expect(g.assets.robotRacket.orientation.vector == racket)
        g.paused=false
        for _ in 0..<800 {
            g.receiveHandPose(wrist(at:[2,1.6,-0.25]));g.update(1/120)
            if g.lastContact?.side == .milo || g.shuttleState == nil { break }
        }
        let contact=try #require(g.lastContact)
        #expect(contact.side == .milo);#expect(simd_length(contact.headVelocity)>0.5)
        let strikePosition=g.assets.milo.position,strikeArm=g.assets.robotArm.orientation.vector
        advanceReady(g,seconds:0.5)
        #expect(simd_distance(g.assets.milo.position,V3(0.4,0,-8))<simd_distance(strikePosition,V3(0.4,0,-8)))
        #expect(abs(simd_dot(g.assets.robotArm.orientation.vector,strikeArm))<0.999)
        #expect(g.miloPhase == .recovering || g.miloPhase == .ready)
    }
    @Test func inactiveRallyStaysPausedUntilExplicitResume() {
        let g=game();beginIncoming(g);g.update(0.03);let before=g.shuttleState!.position
        g.sceneActivityChanged(active:false);#expect(g.paused)
        g.sceneActivityChanged(active:true);g.update(0.03)
        #expect(g.paused);#expect(g.shuttleState!.position == before)
        g.receiveHandPose(wrist(at:[2,1.6,-0.25]));g.paused=false;g.update(0.03)
        #expect(g.shuttleState!.position != before)
    }
    @Test func timedSwingMissingStringsCannotReturn() {
        let g=game(); g.serve(); swingIntoServe(g,miss:0.8); finishIncoming(g)
        #expect(g.lastContact == nil); #expect(g.rallyHits == 0); #expect(g.score.milo == 1)
    }
    @Test(arguments:[false,true])
    func shaftRotationUsesActualEdgeMotionAndRejectsImplausibleJumps(implausible:Bool) throws {
        let g=game();beginIncoming(g)
        for _ in 0..<600 {
            guard let ball=g.shuttleState,ball.position.z < -1 else { break }
            g.receiveHandPose(wrist(at:[2,1.6,-0.25]));g.update(1/240)
        }
        let ball=try #require(g.shuttleState)
        let centre=ball.position+V3(-0.1,0,implausible ? 0.039:0.08)
        func yawPose(_ angle:Float)->simd_float4x4 {
            let rotation=simd_quatf(angle:angle,axis:[0,1,0])
            var pose=simd_float4x4(rotation)
            pose.columns.3=SIMD4(centre-rotation.act(V3(0,0.37,0)),1)
            return pose
        }
        // Establish the measured stationary handle before the distinct turn.
        g.receiveHandPose(yawPose(0));g.update(0)
        g.receiveHandPose(yawPose(0));g.update(0)
        g.receiveHandPose(yawPose(implausible ? 1.5:0.2));g.update(implausible ? 0.001:0.02)
        if implausible {
            #expect(g.lastContact == nil && g.rallyHits == 0)
        } else {
            let hit=try #require(g.lastContact)
            #expect(hit.side == .player && simd_length(hit.headVelocity)<0.0001)
            #expect(simd_length(hit.contactVelocity)>0.8)
            #expect(simd_distance(hit.cork,hit.stringPoint)<=0.040006)
            #expect(g.rallyHits == 1)
        }
    }
    @Test func targetHitAddsPointsAndNextMissResetsStreak() {
        let g=game(.targets); g.assets.targetLocations=[.init(position:[0,0,-8.5],radius:3.5,value:20)]
        g.serve(); swingIntoServe(g); #expect(g.lastContact?.side == .player); finishIncoming(g)
        #expect(g.targetPoints == 20); #expect(g.streak == 1)
        g.serve(); finishIncoming(g); #expect(g.targetPoints == 20); #expect(g.streak == 0)
    }
    @Test func quickMatchStopsAtWinner() {
        let g=game(.match)
        for _ in 0..<7 { g.receiveHandPose(wrist(at:[2,1.6,-0.25])); g.serve(); finishIncoming(g) }
        #expect(g.score.winner == .milo); #expect(!g.canServe); g.serve(); #expect(g.shuttleState == nil)
        #expect(!g.isPreparingServe);g.restart();#expect(g.score.winner == nil);#expect(g.canServe)
        g.receiveHandPose(wrist(at:[2,1.6,-0.25]));beginIncoming(g)
        #expect(g.shuttleState != nil);#expect(g.score.player == 0);#expect(g.score.milo == 0)
    }
    @Test func onlyTrackedInputsAreOfferedAndServeRequiresTracking() {
        #expect(InputMode.allCases == [.hands,.sense]); let g=game(); g.receiveHandPose(nil)
        g.serve(); #expect(g.shuttleState == nil); g.input = .sense; g.controllerReady=false
        g.serve(); #expect(g.shuttleState == nil)
    }
    @Test func racketCannotChangeDuringRally() {
        let g=game(); g.serve(); g.selectRacket(.solar); #expect(g.racketKind == .coral)
    }
    @Test func measuredIntersectionPlacesCorkAtVisibleStrings() throws {
        let g=game(); g.serve(); swingIntoServe(g)
        let contact=try #require(g.lastContact)
        #expect(contact.side == .player); #expect(g.rallyHits == 1); #expect((g.shuttleState?.velocity.z ?? 1)<0)
        #expect(simd_distance(contact.headVelocity,V3(0,3,-4))<0.001)
        #expect(simd_distance(contact.cork,contact.stringPoint)<=0.045)
        let local=(simd_inverse(contact.racketPose)*SIMD4(contact.stringPoint,1)).xyz-[0,0.37,0]
        #expect(abs(local.z)<0.001)
        #expect(pow(local.x/0.17,2)+pow(local.y/0.22,2)<=1)
    }
    @Test func lostHandPausesAndRecoveryNeedsExplicitResume() {
        let g=game();beginIncoming(g);g.update(1/120);let before=g.shuttleState!.position
        g.receiveHandPose(nil); g.update(1/120)
        #expect(g.paused); #expect(g.shuttleState!.position == before); #expect(g.rallyHits == 0)
        g.receiveHandPose(wrist(at:[2,1.6,-0.25])); g.update(1/120)
        #expect(g.paused); #expect(g.shuttleState!.position == before)
        g.paused=false; g.update(1/120); #expect(g.shuttleState!.position != before)
    }
    @Test func staleHandDataCannotStartARally() {
        let g=game(); g.receiveHandPose(matrix_identity_float4x4,timestamp:CACurrentMediaTime()-1)
        g.serve(); #expect(g.shuttleState == nil); g.update(1/120); #expect(!g.handVisible)
    }
    @Test func lobbyInputChangesDiscardOldTrackingWithoutStartingProviders() {
        let g=game();g.update(1/120)
        #expect(g.handVisible);#expect(g.assets.racket.isEnabled);#expect(!g.trackingActive)
        g.controllerReady=true;g.input = .sense;g.reconfigureTracking()
        #expect(!g.handVisible);#expect(!g.controllerReady);#expect(!g.assets.racket.isEnabled)
        #expect(!g.trackingActive);#expect(g.trackingMessage.isEmpty)
        // Switching back must not revive the last pose from the previous mode.
        g.input = .hands;g.reconfigureTracking();g.update(1/120);g.serve()
        #expect(!g.handVisible);#expect(!g.assets.racket.isEnabled);#expect(g.shuttleState == nil)
        g.receiveHandPose(wrist(at:[2,1.6,-0.25]));g.serve()
        #expect(g.isPreparingServe);advanceServe(g);#expect(g.shuttleState != nil)
    }
    @Test func racketHandChangeFreezesRallyAndRequiresNewPoseAndExplicitResume() throws {
        let g=game();beginIncoming(g);g.update(1/120)
        let before=try #require(g.shuttleState).position
        g.leftHand=true;g.reconfigureTracking()
        #expect(g.paused);#expect(!g.handVisible);#expect(!g.controllerReady)
        #expect(!g.assets.racket.isEnabled);#expect(!g.trackingActive)
        for _ in 0..<30 { g.update(1/120) }
        #expect(g.shuttleState?.position == before);#expect(g.rallyHits == 0);#expect(g.lastContact == nil)
        g.receiveHandPose(wrist(at:[2,1.6,-0.25]));g.update(1/120)
        #expect(g.paused);#expect(g.assets.racket.isEnabled);#expect(g.shuttleState?.position == before)
        g.paused=false;g.receiveHandPose(wrist(at:[2,1.6,-0.25]));g.update(1/120)
        #expect(g.shuttleState?.position != before);#expect(g.rallyHits == 0)
    }
    @Test func setGripCorrectsOrientationAfterPalmFrameWithoutMovingPalm() {
        let g=game()
        g.assets.root.transform=Transform(scale:[1,1,1],rotation:simd_quatf(angle:0.6,axis:[0,1,0]),translation:[0.8,0,-1.1])
        var grip=simd_float4x4(simd_quatf(angle:0.8,axis:simd_normalize(V3(1,2,0))))
        grip.columns.3=SIMD4<Float>(0.2,1.25,-0.3,1)
        let worldGrip=g.assets.root.transformMatrix(relativeTo:nil)*grip
        g.receiveHandPose(worldGrip);g.update(1/120);g.setGrip();g.update(1/120)
        let racket=g.assets.racket.transformMatrix(relativeTo:g.assets.root)
        let desired=simd_quatf(angle:0,axis:[0,0,1])
        #expect(simd_distance(racket.columns.3.xyz,grip.columns.3.xyz)<0.0001)
        #expect(simd_distance(racket.columns.1.xyz,desired.act(V3(0,1,0)))<0.0001)
        #expect(simd_distance(racket.columns.2.xyz,desired.act(V3(0,0,1)))<0.0001)
        // The correction follows the next measured grip instead of pinning it.
        grip.columns.3=SIMD4<Float>(-0.4,1.45,-0.1,1)
        g.receiveHandPose(g.assets.root.transformMatrix(relativeTo:nil)*grip);g.update(1/120)
        #expect(simd_distance(g.assets.racket.position,grip.columns.3.xyz)<0.0001)
    }
    @Test func miloCannotReturnByBodyProximityWithoutRacketContact() {
        let g=game(); g.serve(); swingIntoServe(g)
        #expect(g.lastContact?.side == .player)
        g.assets.robotRacket.position=[5,0,0]
        // Put the body in the shuttle's path but keep its racket several metres away.
        for _ in 0..<800 {
            if let ball=g.shuttleState { g.assets.milo.position=[ball.position.x,0,ball.position.z] }
            g.receiveHandPose(wrist(at:[2,1.6,-0.25])); g.update(1/120)
            if g.shuttleState == nil { break }
        }
        #expect(g.lastContact?.side != .milo)
    }
    @Test(arguments:Difficulty.allCases,[Float(1)/30,Float(1)/60,Float(1)/90])
    func miloReturnAlsoTouchesVisibleStrings(difficulty:Difficulty,dt:Float) throws {
        let g=game();g.difficulty=difficulty;g.serve();swingIntoServe(g,dt:dt)
        #expect(g.lastContact?.side == .player)
        for _ in 0..<800 {
            g.receiveHandPose(wrist(at:[2,1.6,-0.25])); g.update(dt)
            if g.lastContact?.side == .milo || g.shuttleState == nil { break }
        }
        let contact=try #require(g.lastContact)
        #expect(contact.side == .milo)
        #expect(simd_distance(contact.cork,contact.stringPoint)<=0.045)
        let state=g.shuttleState
        var outgoing=try #require(state)
        #expect(outgoing.velocity.z > 0)
        var crossed=false,reachedPlayer=false
        for _ in 0..<600 {
            let before=outgoing.position; outgoing.step(1/240)
            if let height=Court.crossingHeight(from:before,to:outgoing.position) {
                #expect(height >= Court.netHeight); crossed=true
            }
            if before.z < -0.25,outgoing.position.z >= -0.25 {
                let fraction=(-0.25-before.z)/(outgoing.position.z-before.z)
                let arrival=before+(outgoing.position-before)*fraction
                #expect(abs(arrival.x)<0.8)
                #expect(arrival.y>1 && arrival.y<2.3)
                #expect(outgoing.velocity.y<0)
                reachedPlayer=true;break
            }
            if outgoing.position.y <= 0.04 { break }
        }
        #expect(crossed);#expect(reachedPlayer)
    }
    @Test(arguments:[Difficulty.friendly,.club],[Float(1)/30,Float(1)/60,Float(1)/90])
    func approachableMiloFeedsAllowASecondActualPlayerHit(difficulty:Difficulty,dt:Float) throws {
        let g=game();g.difficulty=difficulty
        beginIncoming(g);swingIntoServe(g,dt:dt,strength:1.1)
        #expect(g.lastContact?.side == .player)
        for _ in 0..<800 {
            g.receiveHandPose(wrist(at:[2,1.6,-0.25]));g.update(dt)
            if g.lastContact?.side == .milo || g.shuttleState == nil { break }
        }
        let robotContact=try #require(g.lastContact)
        #expect(robotContact.side == .milo)
        #expect(simd_distance(robotContact.cork,robotContact.stringPoint)<=0.040006)
        #expect(g.rallyHits == 2 && g.score.player == 0 && g.score.milo == 0)
        // Replay a measured swing against the returned flight. The second
        // player hit must come through the ordinary finite string sweep.
        swingIntoServe(g,dt:dt)
        let playerContact=try #require(g.lastContact)
        #expect(playerContact.side == .player)
        #expect(simd_distance(playerContact.cork,playerContact.stringPoint)<=0.040006)
        #expect(g.rallyHits == 3 && g.score.player == 0 && g.score.milo == 0)
    }
}

@Suite struct HandRacketPoseTests {
    func joint(_ position:V3,tracked:Bool=true)->HandRacketPose.Joint { .init(position:position,isTracked:tracked) }
    func pose(mirror:Float=1)->simd_float4x4? {
        HandRacketPose.make(wrist:joint(.zero),indexKnuckle:joint([0.04*mirror,0.09,0]),
                            middleKnuckle:joint([0,0.1,0]),littleKnuckle:joint([-0.035*mirror,0.085,0]))
    }
    @Test func handleOriginIsInsidePalmAndAxesFollowKnuckles() throws {
        let grip=try #require(pose())
        #expect(simd_distance(grip.columns.3.xyz,V3(0,0.055,0))<0.0001)
        let y=grip.columns.1.xyz
        #expect(simd_dot(y,V3(0.075,0.005,0))>0.07)
        #expect(simd_dot(grip.columns.2.xyz,V3(0,0,1))>0.99)
        #expect(simd_distance(grip.columns.0.xyz,simd_cross(y,grip.columns.2.xyz))<0.0001)
        for column in 0..<3 { #expect(abs(simd_length(grip[column].xyz)-1)<0.0001) }
        #expect(abs(simd_dot(grip.columns.0.xyz,grip.columns.1.xyz))<0.0001)
    }
    @Test func mirroredHandsProduceProperFramesWithIndexSideExit() throws {
        for mirror:Float in [1,-1] {
            let grip=try #require(pose(mirror:mirror))
            #expect(grip.columns.1.x*mirror>0.99)
            let rotation=simd_float3x3(columns:(grip.columns.0.xyz,grip.columns.1.xyz,grip.columns.2.xyz))
            #expect(abs(simd_determinant(rotation)-1)<0.0001)
        }
    }
    @Test func measuredFrameFollowsWorldRotationAndTranslation() throws {
        let local=try #require(pose())
        var world=simd_float4x4(simd_quatf(angle:0.7,axis:simd_normalize(V3(1,2,3))))
        world.columns.3=SIMD4<Float>(1.2,1.7,-0.5,1)
        func transformed(_ p:V3)->HandRacketPose.Joint { joint((world*SIMD4(p,1)).xyz) }
        let actual=try #require(HandRacketPose.make(wrist:transformed(.zero),indexKnuckle:transformed([0.04,0.09,0]),
                            middleKnuckle:transformed([0,0.1,0]),littleKnuckle:transformed([-0.035,0.085,0])))
        let expected=world*local
        for column in 0..<4 { #expect(simd_distance(actual[column],expected[column])<0.0001) }
    }
    @Test func missingWristOrMiddleAndDegenerateGeometryCannotCreateARacket() {
        let positions:[V3]=[.zero,[0.04,0.09,0],[0,0.1,0],[-0.035,0.085,0]]
        for missing in [0,2] {
            let joints=positions.enumerated().map { joint($0.element,tracked:$0.offset != missing) }
            #expect(HandRacketPose.make(wrist:joints[0],indexKnuckle:joints[1],middleKnuckle:joints[2],littleKnuckle:joints[3]) == nil)
        }
        #expect(HandRacketPose.make(wrist:joint(.zero),indexKnuckle:joint([0,0.1,0]),
                                    middleKnuckle:joint([0,0.1,0]),littleKnuckle:joint([0,0.1,0])) == nil)
        #expect(HandRacketPose.make(wrist:joint(.zero),indexKnuckle:joint([0,0.12,0]),
                                    middleKnuckle:joint([0,0.1,0]),littleKnuckle:joint([0,0.08,0])) == nil)
        #expect(HandRacketPose.make(wrist:joint([Float.nan,0,0]),indexKnuckle:joint(positions[1]),
                                    middleKnuckle:joint(positions[2]),littleKnuckle:joint(positions[3])) == nil)
    }
}
