import Testing
import simd
@testable import ShuttleClub

@MainActor @Suite
struct SenseRacketMountTests {
    @Test func racketExtendsFromGripTowardThumbAfterWorldMovement() {
        let rotations:[simd_quatf]=[
            simd_quatf(angle:0,axis:[0,1,0]),
            simd_quatf(angle:1.1,axis:simd_normalize(SIMD3<Float>(1,2,-1))),
            simd_quatf(angle:-0.8,axis:[1,0,0])]
        for rotation in rotations {
            var grip=simd_float4x4(rotation)
            grip.columns.3=SIMD4<Float>(1.4,0.9,-2.3,1)
            let racket=SenseControllers.racketPose(fromGrip:grip)
            let handle=racket * SIMD4<Float>(0,0,0,1)
            let head=racket * SIMD4<Float>(0,0.37,0,1)
            let expectedHead=grip * SIMD4<Float>(0,0,-0.37,1)
            let face=racket * SIMD4<Float>(0,0,1,0)
            let palmNormal=grip * SIMD4<Float>(1,0,0,0)
            #expect(simd_distance(handle,grip.columns.3)<0.00001)
            #expect(simd_distance(head,expectedHead)<0.00001)
            #expect(simd_distance(face,palmNormal)<0.00001)
            #expect(abs(simd_distance(head,handle)-0.37)<0.00001)
        }
    }

    @Test func mountIsAProperRigidRotation() {
        let mount=SenseControllers.gripFromRacket
        let basis=simd_float3x3(columns:(
            SIMD3(mount.columns.0.x,mount.columns.0.y,mount.columns.0.z),
            SIMD3(mount.columns.1.x,mount.columns.1.y,mount.columns.1.z),
            SIMD3(mount.columns.2.x,mount.columns.2.y,mount.columns.2.z)))
        #expect(abs(simd_determinant(basis)-1)<0.00001)
        for column in [basis.columns.0,basis.columns.1,basis.columns.2] {
            #expect(abs(simd_length(column)-1)<0.00001)
        }
        #expect(abs(simd_dot(basis.columns.0,basis.columns.1))<0.00001)
        #expect(abs(simd_dot(basis.columns.1,basis.columns.2))<0.00001)
        #expect(abs(simd_dot(basis.columns.2,basis.columns.0))<0.00001)
        #expect(mount.columns.3 == SIMD4<Float>(0,0,0,1))
    }
}
