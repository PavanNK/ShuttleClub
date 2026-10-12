import Testing
import simd
import ShuttleCore
@testable import ShuttleClub

@Suite
struct HandGripGestureTests {
    /// Distinct 50 Hz observations spanning each required dwell.
    func acquire(_ gesture: inout HandGripGesture, at start: Double = 0) -> [HandGripGesture.Event] {
        var events: [HandGripGesture.Event] = []
        for index in 0...5 {
            let time = start + Double(index) * 0.02
            if let event = gesture.update(curl: 1.8, timestamp: time, now: time) { events.append(event) }
        }
        for index in 0...5 {
            let time = start + 0.12 + Double(index) * 0.02
            if let event = gesture.update(curl: 1.1, timestamp: time, now: time) { events.append(event) }
        }
        return events
    }

    private func fingers(_ ratios:[Float])->[(knuckle:V3,tip:V3)] {
        ratios.enumerated().map { index,ratio in
            let knuckle=V3(Float(index+1)*0.02,0.07,0)
            return (knuckle:knuckle,tip:knuckle*ratio)
        }
    }

    private func proximalFingers(_ alignments:[Float])->[(knuckle:V3,intermediate:V3)] {
        alignments.enumerated().map { index,alignment in
            let angle=Float(index)*0.12
            let direction=V3(sin(angle),cos(angle),0),tangent=V3(cos(angle),-sin(angle),0)
            let knuckle=direction*(0.07+Float(index)*0.01)
            let firstBone=(direction*alignment+tangent*sqrt(max(0,1-alignment*alignment)))*0.03
            return (knuckle:knuckle,intermediate:knuckle+firstBone)
        }
    }

    @Test func openThenCloseAcquiresExactlyOnceAndHeldClosedAtStartCannotAcquire() {
        var gesture = HandGripGesture()
        var events: [HandGripGesture.Event] = []
        for index in 0..<30 {
            let time = Double(index) * 0.02
            if let event = gesture.update(curl: 1.1, timestamp: time, now: time) { events.append(event) }
        }
        #expect(events.isEmpty && !gesture.isHeld)
        events = acquire(&gesture, at: 0.60)
        #expect(events == [.grabbed] && gesture.isHeld)
        for index in 0..<30 {
            let time = 0.84 + Double(index) * 0.02
            if let event = gesture.update(curl: 1.1, timestamp: time, now: time) { events.append(event) }
        }
        #expect(events == [.grabbed] && gesture.isHeld)
    }

    @Test func bothOpenAndCloseRequireContinuousDwellAtThresholds() {
        var gesture = HandGripGesture()
        var event = gesture.update(curl: 1.65, timestamp: 0, now: 0)
        #expect(event == nil)
        event = gesture.update(curl: 1.65, timestamp: 0.08, now: 0.08)
        #expect(event == nil)
        // Closing before the full open dwell does not arm.
        for index in 0...10 {
            let time = 0.10 + Double(index) * 0.02
            event = gesture.update(curl: 1.25, timestamp: time, now: time)
            #expect(event == nil && !gesture.isHeld)
        }
        event = gesture.update(curl: 1.65, timestamp: 0.32, now: 0.32)
        event = gesture.update(curl: 1.65, timestamp: 0.42, now: 0.42)
        event = gesture.update(curl: 1.25, timestamp: 0.44, now: 0.44)
        event = gesture.update(curl: 1.25, timestamp: 0.52, now: 0.52)
        #expect(event == nil && !gesture.isHeld)
        // A partial close interrupts the close dwell but preserves valid arming.
        event = gesture.update(curl: 1.45, timestamp: 0.54, now: 0.54)
        event = gesture.update(curl: 1.25, timestamp: 0.56, now: 0.56)
        event = gesture.update(curl: 1.25, timestamp: 0.66, now: 0.66)
        #expect(event == .grabbed && gesture.isHeld)
    }

    @Test func relaxedGripBriefOpenJitterAndMissingFingersDoNotDropRacket() {
        var gesture = HandGripGesture()
        let events = acquire(&gesture)
        #expect(events == [.grabbed])
        for index in 0..<8 {
            let time = 0.24 + Double(index) * 0.02
            let event = gesture.update(curl: 1.45, timestamp: time, now: time)
            #expect(event == nil && gesture.isHeld)
        }
        for index in 0...5 {
            let time = 0.40 + Double(index) * 0.02
            let event = gesture.update(curl: 1.8, timestamp: time, now: time)
            #expect(event == nil && gesture.isHeld)
        }
        var event = gesture.update(curl: 1.60, timestamp: 0.52, now: 0.52)
        #expect(event == nil && gesture.isHeld)
        event = gesture.update(curl: nil, timestamp: 0.54, now: 0.54)
        #expect(event == nil && gesture.isHeld)
        // A long missing-data interval breaks release dwell but retains holding.
        event = gesture.update(curl: nil, timestamp: 1.20, now: 1.20)
        event = gesture.update(curl: 1.8, timestamp: 1.22, now: 1.22)
        event = gesture.update(curl: 1.8, timestamp: 1.32, now: 1.32)
        #expect(event == nil && gesture.isHeld)
        event = gesture.update(curl: 1.45, timestamp: 1.34, now: 1.34)
        #expect(event == nil && gesture.isHeld)
    }

    @Test func sustainedOpenReleasesOnceAndCanDeliberatelyGrabAgain() {
        var gesture = HandGripGesture()
        var events = acquire(&gesture)
        for index in 0...15 {
            let time = 0.24 + Double(index) * 0.02
            if let event = gesture.update(curl: 1.65, timestamp: time, now: time) { events.append(event) }
            if index < 15 { #expect(gesture.isHeld) }
        }
        #expect(events == [.grabbed, .released] && !gesture.isHeld)
        for index in 0...5 {
            let time = 0.56 + Double(index) * 0.02
            if let event = gesture.update(curl: 1.25, timestamp: time, now: time) { events.append(event) }
        }
        #expect(events == [.grabbed, .released, .grabbed] && gesture.isHeld)
        gesture.reset()
        #expect(!gesture.isHeld)
        for index in 0...10 {
            let time = 1 + Double(index) * 0.02
            let event = gesture.update(curl: 1.1, timestamp: time, now: time)
            #expect(event == nil && !gesture.isHeld)
        }
    }

    enum Interruption: CaseIterable { case missing, stale, reordered, gap, nonfiniteCurl, future, invalidTime }

    @Test(arguments: Interruption.allCases)
    func interruptedSamplesCannotCompleteAnArmedGrab(_ interruption: Interruption) {
        var gesture = HandGripGesture()
        var event = gesture.update(curl: 1.8, timestamp: 1, now: 1)
        event = gesture.update(curl: 1.8, timestamp: 1.10, now: 1.10)
        event = gesture.update(curl: 1.1, timestamp: 1.12, now: 1.12)
        switch interruption {
        case .missing: event = gesture.update(curl: nil, timestamp: 1.14, now: 1.14)
        case .stale: event = gesture.update(curl: 1.1, timestamp: 1.14, now: 1.40)
        case .reordered: event = gesture.update(curl: 1.1, timestamp: 1.11, now: 1.14)
        case .gap: event = gesture.update(curl: 1.1, timestamp: 1.30, now: 1.30)
        case .nonfiniteCurl: event = gesture.update(curl: .nan, timestamp: 1.14, now: 1.14)
        case .future: event = gesture.update(curl: 1.1, timestamp: 1.30, now: 1.14)
        case .invalidTime: event = gesture.update(curl: 1.1, timestamp: .nan, now: 1.14)
        }
        #expect(event == nil && !gesture.isHeld)
        for index in 0...20 {
            let time = 1.42 + Double(index) * 0.02
            event = gesture.update(curl: 1.1, timestamp: time, now: time)
            #expect(event == nil && !gesture.isHeld)
        }
        let events = acquire(&gesture, at: 1.86)
        #expect(events == [.grabbed] && gesture.isHeld)
    }

    @Test func duplicateSamplesCannotArmGrabOrRelease() {
        var gesture = HandGripGesture()
        var event = gesture.update(curl: 1.8, timestamp: 1, now: 1)
        for index in 0...10 {
            event = gesture.update(curl: 1.8, timestamp: 1, now: 1 + Double(index) * 0.01)
            #expect(event == nil && !gesture.isHeld)
        }
        event = gesture.update(curl: 1.1, timestamp: 1.11, now: 1.11)
        event = gesture.update(curl: 1.1, timestamp: 1.21, now: 1.21)
        #expect(event == nil && !gesture.isHeld)
        let events = acquire(&gesture, at: 1.24)
        #expect(events == [.grabbed])
        event = gesture.update(curl: 1.8, timestamp: 1.48, now: 1.48)
        for index in 0...40 {
            event = gesture.update(curl: 1.8, timestamp: 1.48, now: 1.48 + Double(index) * 0.01)
            #expect(event == nil && gesture.isHeld)
        }
        // A new fresh open observation starts a new dwell after the sample gap.
        event = gesture.update(curl: 1.8, timestamp: 1.90, now: 1.90)
        event = gesture.update(curl: 1.8, timestamp: 2.00, now: 2.00)
        #expect(event == nil && gesture.isHeld)
    }

    @Test func staleOrReorderedSamplesBreakReleaseDwellWithoutDropping() {
        for stale in [false, true] {
            var gesture = HandGripGesture()
            let events = acquire(&gesture)
            #expect(events == [.grabbed])
            var event = gesture.update(curl: 1.8, timestamp: 0.24, now: 0.24)
            event = gesture.update(curl: 1.8, timestamp: 0.34, now: 0.34)
            event = gesture.update(curl: 1.8, timestamp: stale ? 0.36 : 0.33, now: stale ? 0.60 : 0.36)
            #expect(event == nil && gesture.isHeld)
            for index in 0...10 {
                let time = 0.62 + Double(index) * 0.02
                event = gesture.update(curl: 1.8, timestamp: time, now: time)
                #expect(event == nil && gesture.isHeld)
            }
            event = gesture.update(curl: 1.45, timestamp: 0.84, now: 0.84)
            #expect(event == nil && gesture.isHeld)
        }
    }

    @Test func suspensionDisarmsAnOpenSequenceAndPartiallyCompletedGrab() {
        var gesture = HandGripGesture()
        var event = gesture.update(curl: 1.8, timestamp: 0, now: 0)
        event = gesture.update(curl: 1.8, timestamp: 0.10, now: 0.10)
        event = gesture.update(curl: 1.1, timestamp: 0.12, now: 0.12)
        #expect(event == nil && !gesture.isHeld)
        gesture.suspend()
        for index in 0...10 {
            let time = 0.14 + Double(index) * 0.02
            event = gesture.update(curl: 1.1, timestamp: time, now: time)
            #expect(event == nil && !gesture.isHeld)
        }
        let events = acquire(&gesture, at: 0.36)
        #expect(events == [.grabbed] && gesture.isHeld)
    }

    @Test func suspensionRequiresANewFullOpenDwellBeforeArming() {
        var gesture = HandGripGesture()
        var event = gesture.update(curl: 1.8, timestamp: 1, now: 1)
        event = gesture.update(curl: 1.8, timestamp: 1.08, now: 1.08)
        gesture.suspend()
        event = gesture.update(curl: 1.8, timestamp: 1.10, now: 1.10)
        event = gesture.update(curl: 1.8, timestamp: 1.18, now: 1.18)
        for index in 0...8 {
            let time = 1.20 + Double(index) * 0.02
            event = gesture.update(curl: 1.1, timestamp: time, now: time)
            #expect(event == nil && !gesture.isHeld)
        }
        let events = acquire(&gesture, at: 1.38)
        #expect(events == [.grabbed])
    }

    @Test func suspensionKeepsHoldingAndRestartsTheFullReleaseDwell() {
        var gesture = HandGripGesture()
        let acquired = acquire(&gesture)
        #expect(acquired == [.grabbed])
        var event = gesture.update(curl: 1.8, timestamp: 0.24, now: 0.24)
        event = gesture.update(curl: 1.8, timestamp: 0.34, now: 0.34)
        gesture.suspend()
        #expect(gesture.isHeld)
        for index in 0...14 {
            let time = 0.36 + Double(index) * 0.02
            event = gesture.update(curl: 1.8, timestamp: time, now: time)
            #expect(event == nil && gesture.isHeld)
        }
        event = gesture.update(curl: 1.8, timestamp: 0.66, now: 0.66)
        #expect(event == .released && !gesture.isHeld)
    }

    @Test func twoExtendedFingersWithOtherFingersMissingCannotReleaseTheHeldRacket() throws {
        let pairs=fingers([1.9,1.9])
        let curl=try #require(HandGripGesture.curl(wrist:.zero,trackedFingers:pairs))
        let allowed=HandGripGesture.confidentOpenRelease(wrist:.zero,trackedFingers:pairs)
        #expect(curl >= HandGripGesture.openCurl && !allowed)
        var gesture=HandGripGesture()
        let acquired=acquire(&gesture)
        #expect(acquired == [.grabbed])
        for index in 0...25 {
            let time=0.24+Double(index)*0.02
            let event=gesture.update(curl:curl,timestamp:time,now:time,releaseAllowed:allowed)
            #expect(event == nil && gesture.isHeld)
        }
    }

    @Test func aMixedTrackedHandCannotReleaseEvenWhenItsMedianLooksOpen() throws {
        for ratios:[Float] in [[1.9,1.9,1.1],[1.9,1.9,1.9,1.1]] {
            let pairs=fingers(ratios)
            let curl=try #require(HandGripGesture.curl(wrist:.zero,trackedFingers:pairs))
            let allowed=HandGripGesture.confidentOpenRelease(wrist:.zero,trackedFingers:pairs)
            #expect(curl >= HandGripGesture.openCurl && !allowed)
            var gesture=HandGripGesture()
            let acquired=acquire(&gesture)
            #expect(acquired == [.grabbed])
            for index in 0...20 {
                let time=0.24+Double(index)*0.02
                let event=gesture.update(curl:curl,timestamp:time,now:time,releaseAllowed:allowed)
                #expect(event == nil && gesture.isHeld)
            }
        }
    }

    @Test func aFreshConfidentOpeningReleasesOnlyAfterItsOwnFullDwell() throws {
        var gesture=HandGripGesture()
        let acquired=acquire(&gesture)
        #expect(acquired == [.grabbed])
        let uncertain=fingers([1.9,1.9])
        let uncertainCurl=try #require(HandGripGesture.curl(wrist:.zero,trackedFingers:uncertain))
        let uncertainAllowed=HandGripGesture.confidentOpenRelease(wrist:.zero,trackedFingers:uncertain)
        for index in 0...10 {
            let time=0.24+Double(index)*0.02
            let event=gesture.update(curl:uncertainCurl,timestamp:time,now:time,releaseAllowed:uncertainAllowed)
            #expect(event == nil && gesture.isHeld)
        }
        let opened=fingers([1.9,1.9,1.9])
        let openCurl=try #require(HandGripGesture.curl(wrist:.zero,trackedFingers:opened))
        let openAllowed=HandGripGesture.confidentOpenRelease(wrist:.zero,trackedFingers:opened)
        #expect(openAllowed)
        for index in 0...14 {
            let time=0.46+Double(index)*0.02
            let event=gesture.update(curl:openCurl,timestamp:time,now:time,releaseAllowed:openAllowed)
            #expect(event == nil && gesture.isHeld)
        }
        let event=gesture.update(curl:openCurl,timestamp:0.76,now:0.76,releaseAllowed:openAllowed)
        #expect(event == .released && !gesture.isHeld)
    }

    @Test func menuInteractionBreaksReleaseDwellEvenOnTheSameAnchorSample() {
        var gesture=HandGripGesture()
        let acquired=acquire(&gesture)
        #expect(acquired == [.grabbed])
        for time in [0.24,0.34,0.44] {
            let event=gesture.update(curl:1.8,timestamp:time,now:time)
            #expect(event == nil && gesture.isHeld)
        }
        let sameSample=gesture.update(curl:1.8,timestamp:0.44,now:0.44,releaseAllowed:false)
        #expect(sameSample == nil && gesture.isHeld)
        for index in 0...10 {
            let time=0.46+Double(index)*0.02
            let event=gesture.update(curl:1.8,timestamp:time,now:time,releaseAllowed:false)
            #expect(event == nil && gesture.isHeld)
        }
        for index in 0...14 {
            let time=0.68+Double(index)*0.02
            let event=gesture.update(curl:1.8,timestamp:time,now:time)
            #expect(event == nil && gesture.isHeld)
        }
        let event=gesture.update(curl:1.8,timestamp:0.98,now:0.98)
        #expect(event == .released && !gesture.isHeld)
    }

    @Test func releaseConfidenceRejectsInvalidOrDegenerateMeasuredPairs() {
        let opened=fingers([1.9,1.9,1.9,1.9])
        #expect(HandGripGesture.confidentOpenRelease(wrist:.zero,trackedFingers:opened))
        #expect(!HandGripGesture.confidentOpenRelease(wrist:[.nan,0,0],trackedFingers:opened))
        #expect(!HandGripGesture.confidentOpenRelease(wrist:.zero,trackedFingers:fingers([1.9,.nan,1.9])))
        #expect(!HandGripGesture.confidentOpenRelease(wrist:.zero,trackedFingers:[opened[0],opened[1],(.zero,[0,0.1,0])]))
        #expect(!HandGripGesture.confidentOpenRelease(wrist:.zero,trackedFingers:[opened[0],opened[1],([0,0.08,0],[0,.infinity,0])]))
    }

    @Test func proximalCurlRecognizesStraightBentAndIntermediateFirstPhalanges() throws {
        let open=try #require(HandGripGesture.proximalCurl(wrist:.zero,trackedFingers:proximalFingers([1,0.95])))
        let closed=try #require(HandGripGesture.proximalCurl(wrist:.zero,trackedFingers:proximalFingers([0,0.2])))
        let halfway=try #require(HandGripGesture.proximalCurl(wrist:.zero,trackedFingers:proximalFingers([0.65,0.65])))
        #expect(abs(open-1.9)<0.0001 && open >= HandGripGesture.openCurl)
        #expect(abs(closed-1.1)<0.0001 && closed <= HandGripGesture.closedCurl)
        #expect(abs(halfway-1.5)<0.0001 && halfway > HandGripGesture.closedCurl && halfway < HandGripGesture.openCurl)
    }

    @Test func proximalMedianToleratesOneDifferentFingerAndPreservesMixedBends() throws {
        let open=try #require(HandGripGesture.proximalCurl(wrist:.zero,trackedFingers:proximalFingers([1,1,0])))
        let closed=try #require(HandGripGesture.proximalCurl(wrist:.zero,trackedFingers:proximalFingers([0,0,1])))
        let mixed=try #require(HandGripGesture.proximalCurl(wrist:.zero,trackedFingers:proximalFingers([0,1])))
        #expect(abs(open-1.9)<0.0001 && abs(closed-1.1)<0.0001 && abs(mixed-1.5)<0.0001)
    }

    @Test func proximalCurlIsInvariantUnderMeasuredRotationTranslationAndHandSize() throws {
        let original=proximalFingers([0.65,0.7,0.3])
        let expected=try #require(HandGripGesture.proximalCurl(wrist:.zero,trackedFingers:original))
        let rotation=simd_quatf(angle:1.1,axis:simd_normalize(V3(1,2,-0.5))),translation=V3(0.4,1.2,-0.7)
        for scale:Float in [0.4,0.5,1,2] {
            let transformed=original.map { pair in
                (knuckle:rotation.act(pair.knuckle*scale)+translation,
                 intermediate:rotation.act(pair.intermediate*scale)+translation)
            }
            let actual=try #require(HandGripGesture.proximalCurl(wrist:translation,trackedFingers:transformed))
            #expect(abs(actual-expected)<0.0001)
        }
    }

    @Test func proximalCurlRejectsInsufficientInvalidAndTooShortMeasuredBones() {
        let valid=proximalFingers([1,1])
        #expect(HandGripGesture.proximalCurl(wrist:.zero,trackedFingers:[]) == nil)
        #expect(HandGripGesture.proximalCurl(wrist:.zero,trackedFingers:[valid[0]]) == nil)
        #expect(HandGripGesture.proximalCurl(wrist:[.nan,0,0],trackedFingers:valid) == nil)
        let invalid:[(knuckle:V3,intermediate:V3)]=[
            ([.nan,0,0],[0,0.1,0]),([0,0.08,0],[.infinity,0,0]),
            ([0,0.08,0],[0,0.08,0]),([0,0.08,0],[0,0.084,0]),
            ([0,0.019,0],[0,0.049,0]),(.zero,[0,0.03,0])]
        for pair in invalid {
            #expect(HandGripGesture.proximalCurl(wrist:.zero,trackedFingers:[valid[0],pair]) == nil)
        }
    }

    @Test func proximalAcquisitionCannotSubstituteForObservedFingertipReleaseConfidence() throws {
        let open=try #require(HandGripGesture.proximalCurl(wrist:.zero,trackedFingers:proximalFingers([1,1,1])))
        let closed=try #require(HandGripGesture.proximalCurl(wrist:.zero,trackedFingers:proximalFingers([0,0,0])))
        let releaseAllowed=HandGripGesture.confidentOpenRelease(wrist:.zero,trackedFingers:[])
        #expect(!releaseAllowed)
        var gesture=HandGripGesture(),events:[HandGripGesture.Event]=[]
        for index in 0...5 {
            let time=Double(index)*0.02
            if let event=gesture.update(curl:open,timestamp:time,now:time,releaseAllowed:releaseAllowed) { events.append(event) }
        }
        for index in 0...5 {
            let time=0.12+Double(index)*0.02
            if let event=gesture.update(curl:closed,timestamp:time,now:time,releaseAllowed:releaseAllowed) { events.append(event) }
        }
        #expect(events == [.grabbed] && gesture.isHeld)
        for index in 0...25 {
            let time=0.24+Double(index)*0.02
            let event=gesture.update(curl:open,timestamp:time,now:time,releaseAllowed:releaseAllowed)
            #expect(event == nil && gesture.isHeld)
        }
    }

    @Test func medianCurlIsInvariantUnderHandSizeRigidMovementAndOneNoisyFinger() throws {
        let fingers: [(knuckle: V3, tip: V3)] = [
            ([0, 0.07, 0], [0, 0.14, 0]),
            ([0.06, 0, 0], [0.12, 0, 0]),
            ([0, 0, 0.08], [0, 0, 0.72])]
        let base = try #require(HandGripGesture.curl(wrist: .zero, trackedFingers: fingers))
        #expect(abs(base - 2) < 0.00001)
        let rotation = simd_quatf(angle: 1.1, axis: simd_normalize(V3(1, 2, -1)))
        let translation = V3(2, -0.5, 1.2)
        for scale: Float in [0.25, 0.5, 1, 2, 4] {
            let moved = fingers.map { finger in
                (knuckle: rotation.act(finger.knuckle * scale) + translation,
                 tip: rotation.act(finger.tip * scale) + translation)
            }
            let result = try #require(HandGripGesture.curl(wrist: translation, trackedFingers: moved))
            #expect(abs(result - base) < 0.0001)
        }
        let two = try #require(HandGripGesture.curl(wrist: .zero,
            trackedFingers: [([0.05, 0, 0], [0.05, 0, 0]), ([0, 0.08, 0], [0, 0.16, 0])]))
        #expect(abs(two - 1.5) < 0.00001)
    }

    @Test func curlRejectsInsufficientInvalidAndDegenerateFingerData() {
        let valid: (knuckle: V3, tip: V3) = ([0, 0.07, 0], [0, 0.14, 0])
        #expect(HandGripGesture.curl(wrist: .zero, trackedFingers: []) == nil)
        #expect(HandGripGesture.curl(wrist: .zero, trackedFingers: [valid]) == nil)
        #expect(HandGripGesture.curl(wrist: [.nan, 0, 0], trackedFingers: [valid, valid]) == nil)
        #expect(HandGripGesture.curl(wrist: .zero, trackedFingers: [valid, ([.nan, 0, 0], [0, 0.1, 0])]) == nil)
        #expect(HandGripGesture.curl(wrist: .zero, trackedFingers: [valid, ([0, 0.1, 0], [.infinity, 0, 0])]) == nil)
        #expect(HandGripGesture.curl(wrist: .zero, trackedFingers: [valid, (.zero, [0, 0.1, 0])]) == nil)
        #expect(HandGripGesture.curl(wrist: .zero, trackedFingers: [valid, ([0, 0.00001, 0], [0, 0.1, 0])]) == nil)
    }
}
