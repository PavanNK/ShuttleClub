import Testing
@testable import ShuttleClub

@Suite
struct ServePinchGestureTests {
    @Test func heldPinchOnFirstAcquisitionCannotServe() {
        var gesture = ServePinchGesture()
        var served = false
        for index in 0..<60 {
            let time = Double(index) / 60
            served = gesture.update(distance: 0.01, timestamp: time, now: time)
            #expect(!served)
        }
    }

    @Test func deliberatePinchFiresOnceUntilTheFingersReopen() {
        var gesture = ServePinchGesture()
        var served = false
        served = gesture.update(distance: 0.05, timestamp: 0, now: 0)
        #expect(!served)
        var events = 0
        for index in 1...40 {
            let time = Double(index) / 60
            if gesture.update(distance: 0.01, timestamp: time, now: time) { events += 1 }
        }
        #expect(events == 1)
        served = gesture.update(distance: 0.05, timestamp: 0.70, now: 0.70)
        #expect(!served)
        for index in 1...20 {
            let time = 0.70 + Double(index) / 60
            if gesture.update(distance: 0.01, timestamp: time, now: time) { events += 1 }
        }
        #expect(events == 2)
    }

    @Test func partialReleaseAndThresholdJitterRequireANewSustainedHold() {
        var gesture = ServePinchGesture()
        var served = false
        served = gesture.update(distance: 0.05, timestamp: 0, now: 0)
        #expect(!served)
        served = gesture.update(distance: 0.01, timestamp: 0.02, now: 0.02)
        #expect(!served)
        served = gesture.update(distance: 0.01, timestamp: 0.10, now: 0.10)
        #expect(!served)
        served = gesture.update(distance: 0.03, timestamp: 0.12, now: 0.12)
        #expect(!served)
        served = gesture.update(distance: 0.01, timestamp: 0.14, now: 0.14)
        #expect(!served)
        served = gesture.update(distance: 0.026, timestamp: 0.20, now: 0.20)
        #expect(!served)
        served = gesture.update(distance: 0.01, timestamp: 0.22, now: 0.22)
        #expect(!served)
        served = gesture.update(distance: 0.01, timestamp: 0.30, now: 0.30)
        #expect(!served)
        served = gesture.update(distance: 0.01, timestamp: 0.35, now: 0.35)
        #expect(served)
    }

    @Test func untrackedOrStaleSampleDisarmsAndHeldReacquisitionDoesNotServe() {
        for interruption in [Float?.none, Float?.some(0.01)] {
            var gesture = ServePinchGesture()
            var served = false
            served = gesture.update(distance: 0.05, timestamp: 1, now: 1)
            #expect(!served)
            served = gesture.update(distance: 0.01, timestamp: 1.02, now: 1.02)
            #expect(!served)
            // The finite distance variant represents an old tracked anchor.
            let now = interruption == nil ? 1.08 : 1.50
            served = gesture.update(distance: interruption, timestamp: 1.08, now: now)
            #expect(!served)
            for index in 0..<30 {
                let time = 1.60 + Double(index) / 60
                served = gesture.update(distance: 0.01, timestamp: time, now: time)
                #expect(!served)
            }
        }
    }

    @Test func sampleGapInterruptsHoldAndRequiresOpenHandAgain() {
        var gesture = ServePinchGesture()
        var served = false
        served = gesture.update(distance: 0.05, timestamp: 0, now: 0)
        #expect(!served)
        served = gesture.update(distance: 0.01, timestamp: 0.02, now: 0.02)
        #expect(!served)
        served = gesture.update(distance: 0.01, timestamp: 0.08, now: 0.08)
        #expect(!served)
        served = gesture.update(distance: 0.01, timestamp: 0.25, now: 0.25)
        #expect(!served)
        for index in 1...20 {
            let time = 0.25 + Double(index) / 60
            served = gesture.update(distance: 0.01, timestamp: time, now: time)
            #expect(!served)
        }
        served = gesture.update(distance: 0.05, timestamp: 0.60, now: 0.60)
        #expect(!served)
        served = gesture.update(distance: 0.01, timestamp: 0.62, now: 0.62)
        #expect(!served)
        served = gesture.update(distance: 0.01, timestamp: 0.70, now: 0.70)
        #expect(!served)
        served = gesture.update(distance: 0.01, timestamp: 0.76, now: 0.76)
        #expect(served)
    }

    @Test func duplicateAndBackwardSamplesCannotCompleteAFalseHold() {
        var gesture = ServePinchGesture()
        var served = false
        served = gesture.update(distance: 0.05, timestamp: 1, now: 1)
        #expect(!served)
        served = gesture.update(distance: 0.01, timestamp: 1.02, now: 1.02)
        #expect(!served)
        for _ in 0..<20 {
            served = gesture.update(distance: 0.01, timestamp: 1.02, now: 1.08)
            #expect(!served)
        }
        served = gesture.update(distance: 0.01, timestamp: 1.01, now: 1.09)
        #expect(!served)
        for index in 0..<30 {
            let time = 1.10 + Double(index) / 60
            served = gesture.update(distance: 0.01, timestamp: time, now: time)
            #expect(!served)
        }
    }

    @Test func invalidValuesAndExplicitResetRequireOpenHandAgain() {
        for distance in [Float.nan, Float.infinity, -0.01] {
            var gesture = ServePinchGesture()
            var served = false
            served = gesture.update(distance: 0.05, timestamp: 0, now: 0)
            #expect(!served)
            served = gesture.update(distance: distance, timestamp: 0.02, now: 0.02)
            #expect(!served)
            for index in 0..<20 {
                let time = 0.04 + Double(index) / 60
                served = gesture.update(distance: 0.01, timestamp: time, now: time)
                #expect(!served)
            }
        }
        var gesture = ServePinchGesture()
        var served = false
        served = gesture.update(distance: 0.05, timestamp: 0, now: 0)
        #expect(!served)
        gesture.reset()
        served = gesture.update(distance: 0.01, timestamp: 0.02, now: 0.02)
        #expect(!served)
        served = gesture.update(distance: 0.01, timestamp: 0.10, now: 0.10)
        #expect(!served)
        served = gesture.update(distance: 0.01, timestamp: 0.15, now: 0.15)
        #expect(!served)
    }
}
