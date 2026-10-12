import Testing
import simd
@testable import ShuttleClub

@MainActor struct SenseMovementInputTests {
    @Test func missingOrNonfiniteMovementAxesStayNeutral() {
        #expect(SenseControllers.movementAxes(x:nil,y:0.5) == .zero)
        #expect(SenseControllers.movementAxes(x:0.5,y:nil) == .zero)
        for invalid in [Float.nan,Float.infinity,-Float.infinity] {
            #expect(SenseControllers.movementAxes(x:invalid,y:0.5) == .zero)
            #expect(SenseControllers.movementAxes(x:0.5,y:invalid) == .zero)
        }
    }

    @Test func finiteMovementAxesKeepDirectionWithinTheirBounds() {
        #expect(SenseControllers.movementAxes(x:0.25,y:-0.6) == SIMD2<Float>(0.25,-0.6))
        #expect(SenseControllers.movementAxes(x:3,y:-2) == SIMD2<Float>(1,-1))
        #expect(SenseControllers.movementAxes(x:0,y:0) == .zero)
    }

    @Test func stoppedControllerInputCannotMoveEitherRacketHand() {
        let controllers=SenseControllers()
        #expect(controllers.movementInput(leftHand:false) == .zero)
        #expect(controllers.movementInput(leftHand:true) == .zero)
        controllers.stop()
        #expect(controllers.movementInput(leftHand:false) == .zero)
    }
}
