import Testing
import simd
import ShuttleCore
@testable import ShuttleClub

@Suite struct HandPalmFallbackTests {
    enum MissingSide:CaseIterable,Equatable { case index,little }
    private func joint(_ position:V3,tracked:Bool=true)->HandRacketPose.Joint {
        .init(position:position,isTracked:tracked)
    }
    private func joints(mirror:Float=1,missing:MissingSide?=nil,
                        world:simd_float4x4=matrix_identity_float4x4)->[HandRacketPose.Joint] {
        let positions:[V3]=[.zero,[0.04*mirror,0.09,0],[0,0.1,0],[-0.035*mirror,0.085,0]]
        return positions.enumerated().map { index,position in
            let tracked = !(missing == .index && index == 1 || missing == .little && index == 3)
            return joint(tracked ? (world*SIMD4<Float>(position,1)).xyz:[.nan,.nan,.nan],tracked:tracked)
        }
    }
    private func make(_ measured:[HandRacketPose.Joint])->simd_float4x4? {
        HandRacketPose.make(wrist:measured[0],indexKnuckle:measured[1],middleKnuckle:measured[2],littleKnuckle:measured[3])
    }
    private func update(_ tracker:inout HandGripTracker,wrist:simd_float4x4=matrix_identity_float4x4,
                        joints:[HandRacketPose.Joint])->simd_float4x4? {
        tracker.update(worldFromWrist:wrist,isTracked:joints[0].isTracked,
                       indexKnuckle:joints[1],middleKnuckle:joints[2],littleKnuckle:joints[3])
    }
    private func expectPose(_ actual:simd_float4x4,_ expected:simd_float4x4) {
        for column in 0..<4 { #expect(simd_distance(actual[column],expected[column])<0.0001) }
    }

    @Test func completeKnucklesKeepTheOriginalAuthoredBasis() throws {
        let pose=try #require(make(joints()))
        #expect(simd_distance(pose.columns.0.xyz,V3(0.06651901,-0.99778516,0))<0.0001)
        #expect(simd_distance(pose.columns.1.xyz,V3(0.99778516,0.06651901,0))<0.0001)
        #expect(pose.columns.2.xyz == V3(0,0,1))
        #expect(simd_distance(pose.columns.3.xyz,V3(0,0.055,0))<0.0001)
    }

    @Test(arguments:MissingSide.allCases)
    func oneMissingSideProducesProperMirroredPalmFrames(missing:MissingSide) throws {
        for mirror:Float in [1,-1] {
            let pose=try #require(make(joints(mirror:mirror,missing:missing)))
            #expect(simd_distance(pose.columns.1.xyz,V3(mirror,0,0))<0.0001)
            #expect(simd_distance(pose.columns.3.xyz,V3(0,0.055,0))<0.0001)
            for column in 0..<3 { #expect(abs(simd_length(pose[column].xyz)-1)<0.0001) }
            #expect(abs(simd_dot(pose.columns.0.xyz,pose.columns.1.xyz))<0.0001)
            let rotation=simd_float3x3(columns:(pose.columns.0.xyz,pose.columns.1.xyz,pose.columns.2.xyz))
            #expect(abs(simd_determinant(rotation)-1)<0.0001)
        }
    }

    @Test(arguments:MissingSide.allCases)
    func partialPalmFrameFollowsMeasuredRigidWorldMotion(missing:MissingSide) throws {
        let local=try #require(make(joints(missing:missing)))
        var world=simd_float4x4(simd_quatf(angle:0.9,axis:simd_normalize(V3(1,3,-2))))
        world.columns.3=SIMD4<Float>(0.4,1.3,-0.2,1)
        let moved=try #require(make(joints(missing:missing,world:world)))
        expectPose(moved,world*local)
    }

    @Test(arguments:MissingSide.allCases)
    func partialBasisRejectsLongitudinalFingerLengthSkew(missing:MissingSide) throws {
        var measured=joints(missing:missing)
        if missing == .little { measured[1]=joint([0.04,0.20,0]) }
        else { measured[3]=joint([-0.035,0.03,0]) }
        let pose=try #require(make(measured))
        #expect(simd_distance(pose.columns.1.xyz,V3(1,0,0))<0.0001)
        #expect(simd_distance(pose.columns.3.xyz,V3(0,0.055,0))<0.0001)
    }

    @Test(arguments:MissingSide.allCases)
    func partialAcquisitionKeepsItsMountWhenMoreKnucklesAppearOrDisappear(missing:MissingSide) throws {
        var tracker=HandGripTracker()
        let firstResult=update(&tracker,joints:joints(missing:missing))
        let first=try #require(firstResult)
        let fullResult=update(&tracker,joints:joints())
        expectPose(try #require(fullResult),first)
        var movedWrist=simd_float4x4(simd_quatf(angle:-0.7,axis:[0,1,0]))
        movedWrist.columns.3=SIMD4<Float>(0.2,1.2,-0.4,1)
        let missingJoints=[joint(movedWrist.columns.3.xyz),joint([.nan,0,0],tracked:false),
                           joint([.nan,0,0],tracked:false),joint([.nan,0,0],tracked:false)]
        let movedResult=update(&tracker,wrist:movedWrist,joints:missingJoints)
        expectPose(try #require(movedResult),movedWrist*first)
    }

    @Test func partialPalmCaptureKeepsTheHandleOffsetBounded() throws {
        var measured=joints(missing:.little)
        measured[1]=joint([0.03,0.23,0]);measured[2]=joint([0,0.25,0])
        let palm=try #require(make(measured))
        #expect(abs(simd_length(palm.columns.3.xyz)-0.1375)<0.0001)
        var tracker=HandGripTracker()
        let captured=tracker.capture(worldFromWrist:matrix_identity_float4x4,worldFromGrip:palm)
        #expect(captured)
        var distant=palm;distant.columns.3=SIMD4<Float>(0,0.141,0,1)
        let rejected=tracker.capture(worldFromWrist:matrix_identity_float4x4,worldFromGrip:distant)
        #expect(!rejected)
        let heldResult=update(&tracker,joints:measured)
        expectPose(try #require(heldResult),palm)
    }

    @Test func missingMiddleSingleKnuckleInvalidAndDegenerateDataCannotAcquire() {
        var cases:[[HandRacketPose.Joint]]=[]
        var missingMiddle=joints();missingMiddle[2]=joint(.zero,tracked:false);cases.append(missingMiddle)
        var noSides=joints();noSides[1]=joint(.zero,tracked:false);noSides[3]=joint(.zero,tracked:false);cases.append(noSides)
        var oneIndex=joints(missing:.little);oneIndex[2]=joint(.zero,tracked:false);cases.append(oneIndex)
        var missingWrist=joints();missingWrist[0]=joint(.zero,tracked:false);cases.append(missingWrist)
        var narrow=joints(missing:.little);narrow[1]=joint([0.011,0.09,0]);cases.append(narrow)
        var parallel=joints(missing:.little);parallel[1]=joint([0,0.12,0]);cases.append(parallel)
        var shortPalm=joints(missing:.little);shortPalm[2]=joint([0,0.02,0]);cases.append(shortPalm)
        var invalid=joints(missing:.little);invalid[1]=joint([.nan,0,0]);cases.append(invalid)
        var distant=joints(missing:.little);distant[1]=joint([0.3,0.1,0]);cases.append(distant)
        var invalidComplete=joints();invalidComplete[3]=joint([.infinity,0,0]);cases.append(invalidComplete)
        for measured in cases {
            #expect(make(measured) == nil)
            var tracker=HandGripTracker()
            let acquired=update(&tracker,joints:measured)
            #expect(acquired == nil)
        }
    }
}
