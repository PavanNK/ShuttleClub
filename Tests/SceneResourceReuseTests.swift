import Foundation
import Testing
import RealityKit
import UIKit
import simd
import ShuttleCore
@testable import ShuttleClub

#if DEBUG
@MainActor @Suite(.serialized)
struct SceneResourceReuseTests {
    private func mesh(_ entity:ModelEntity) throws -> MeshResource {
        try #require(entity.model?.mesh)
    }
    private func indexCount(_ resource:MeshResource)->Int {
        resource.contents.models.reduce(0) { total,model in
            total+model.parts.reduce(0) { $0+($1.triangleIndices?.count ?? 0) }
        }
    }
    private func sameGeometry(_ actual:MeshResource,_ expected:MeshResource) {
        #expect(actual.bounds.min == expected.bounds.min && actual.bounds.max == expected.bounds.max)
        let actualParts=actual.contents.models.flatMap { Array($0.parts) }
        let expectedParts=expected.contents.models.flatMap { Array($0.parts) }
        #expect(actualParts.count == expectedParts.count)
        for (a,b) in zip(actualParts,expectedParts) {
            #expect(a[MeshBuffers.positions]?.elements == b[MeshBuffers.positions]?.elements)
            #expect(a[MeshBuffers.normals]?.elements == b[MeshBuffers.normals]?.elements)
            #expect(a[MeshBuffers.textureCoordinates]?.elements == b[MeshBuffers.textureCoordinates]?.elements)
            #expect(a.triangleIndices?.elements == b.triangleIndices?.elements)
        }
    }

    @Test func repeatedPrimitivesShareResourcesAndKeepIndependentTransformsMaterialsAndParents() throws {
        ClubScene.resetMeshCacheForTesting()
        let firstParent=Entity(),secondParent=Entity()
        let coral=ClubScene.material(ClubScene.coral),mint=ClubScene.material(ClubScene.teal)
        let first=ClubScene.sphere(firstParent,0.0025,[1,2,3],coral)
        let second=ClubScene.sphere(secondParent,0.0025,[-1,0,2],mint,scale:[1,2,1])
        let firstMesh=try mesh(first),secondMesh=try mesh(second)
        #expect(firstMesh === secondMesh)
        #expect(first !== second && first.parent === firstParent && second.parent === secondParent)
        #expect(first.position == V3(1,2,3) && second.position == V3(-1,0,2))
        #expect(first.scale == V3(1,1,1) && second.scale == V3(1,2,1))
        first.position = .zero;first.scale=[3,3,3]
        first.model?.materials=[ClubScene.glow(.white)]
        #expect(second.position == V3(-1,0,2) && second.scale == V3(1,2,1))
        #expect(second.model?.materials.first is PhysicallyBasedMaterial)
        #expect(ClubScene.meshCacheMetrics.generations == 1 && ClubScene.meshCacheMetrics.hits == 1)
    }

    @Test func primitiveKeysPreserveExactDimensionsRoundingAndNativeTopology() throws {
        ClubScene.resetMeshCacheForTesting()
        let parent=Entity(),mat=ClubScene.material(.white),size=V3(0.5,0.2,0.7)
        let rounded=ClubScene.box(parent,size,[1,0,0],mat,round:0.025)
        let repeated=ClubScene.box(parent,size,[2,0,0],mat,round:0.025)
        let square=ClubScene.box(parent,size,.zero,mat)
        let changed=ClubScene.box(parent,[0.5,0.2,0.71],.zero,mat,round:0.025)
        let roundedMesh=try mesh(rounded),repeatedMesh=try mesh(repeated)
        let squareMesh=try mesh(square),changedMesh=try mesh(changed)
        #expect(roundedMesh === repeatedMesh && roundedMesh !== squareMesh && roundedMesh !== changedMesh)
        sameGeometry(roundedMesh,.generateBox(size:size,cornerRadius:0.025))
        let sphere=ClubScene.sphere(parent,0.021,.zero,mat)
        sameGeometry(try mesh(sphere),.generateSphere(radius:0.021))
        let a=V3(0,0,0),b=V3(0,0.14,0),shift=V3(0,0,0.7)
        let rod=ClubScene.rod(parent,a,b,0.012,mat)
        let shifted=ClubScene.rod(parent,a+shift,b+shift,0.012,mat)
        let rodMesh=try mesh(rod),shiftedMesh=try mesh(shifted)
        #expect(rodMesh === shiftedMesh)
        sameGeometry(rodMesh,.generateCylinder(height:simd_length(b-a),radius:0.012))
        #expect(rod.position == (a+b)/2 && shifted.position == (a+b)/2+shift)
        #expect(rod.parent === parent && shifted.parent === parent)
    }

    @Test func authoredRingsLeavesAndFloorKeepTessellationAndUVKeys() throws {
        ClubScene.resetMeshCacheForTesting()
        let parent=Entity(),mat=ClubScene.material(.white)
        let first=try #require(ClubScene.ring(parent,rx:0.14,ry:0.18,tube:0.006,at:[0,0.37,0],mat:mat))
        let second=try #require(ClubScene.ring(parent,rx:0.14,ry:0.18,tube:0.006,at:[1,0.37,0],mat:ClubScene.glow(.cyan)))
        let firstMesh=try mesh(first),secondMesh=try mesh(second)
        #expect(firstMesh === secondMesh)
        #expect(indexCount(firstMesh) == 80*8*6)
        #expect(first.position == V3(0,0.37,0) && second.position == V3(1,0.37,0))
        let leaf=try #require(ClubScene.leafBlade()),leafAgain=try #require(ClubScene.leafBlade())
        #expect(leaf === leafAgain && indexCount(leaf) == 20*6*12)
        let uv=leaf.contents.models.flatMap { $0.parts.flatMap { $0[MeshBuffers.textureCoordinates]?.elements ?? [] } }
        #expect(!uv.isEmpty && uv.allSatisfy { $0.x >= 0 && $0.x <= 1 && $0.y >= 0 && $0.y <= 1 })
        let floors=Entity()
        ClubScene.tiledFloor(floors,size:[2,3],repeatUV:[1,1],at:.zero,mat:mat)
        ClubScene.tiledFloor(floors,size:[2,3],repeatUV:[2,1],at:.zero,mat:mat)
        let models=floors.children.compactMap { $0 as? ModelEntity }
        #expect(models.count == 2)
        let floorA=try mesh(models[0]),floorB=try mesh(models[1])
        #expect(floorA !== floorB && floorA.bounds.min == floorB.bounds.min && floorA.bounds.max == floorB.bounds.max)
        let floorBUV=floorB.contents.models.flatMap { $0.parts.flatMap { $0[MeshBuffers.textureCoordinates]?.elements ?? [] } }
        #expect(floorBUV.contains(SIMD2<Float>(2,1)))
    }

    @Test func twentyAuthoredRacketsReuseEveryMeshOnTheSecondBatchAndReportConstructionTime() throws {
        ClubScene.resetMeshCacheForTesting()
        let kinds=(0..<20).map { RacketKind.allCases[$0 % RacketKind.allCases.count] }
        let coldStart=Date.timeIntervalSinceReferenceDate
        let cold=kinds.map { ClubScene.makeRacket($0) }
        let coldMilliseconds=(Date.timeIntervalSinceReferenceDate-coldStart)*1000
        let coldMetrics=ClubScene.meshCacheMetrics
        let warmStart=Date.timeIntervalSinceReferenceDate
        let warm=kinds.map { ClubScene.makeRacket($0) }
        let warmMilliseconds=(Date.timeIntervalSinceReferenceDate-warmStart)*1000
        let warmMetrics=ClubScene.meshCacheMetrics
        #expect(coldMetrics.generations > 0 && coldMetrics.evictions == 0)
        #expect(warmMetrics.generations == coldMetrics.generations && warmMetrics.entries == coldMetrics.entries)
        #expect(warmMetrics.hits > coldMetrics.hits && warmMetrics.evictions == 0)
        for (a,b) in zip(cold,warm) {
            let aModels=a.children.compactMap { $0 as? ModelEntity }
            let bModels=b.children.compactMap { $0 as? ModelEntity }
            #expect(aModels.count == 71 && bModels.count == 71)
            for (first,second) in zip(aModels,bModels) {
                let firstMesh=try mesh(first),secondMesh=try mesh(second)
                #expect(firstMesh === secondMesh)
                for column in 0..<4 { #expect(first.transform.matrix[column] == second.transform.matrix[column]) }
                #expect(first.parent === a && second.parent === b)
            }
        }
        let grommetReference=ClubScene.sphere(Entity(),0.0025,.zero,ClubScene.material(.black))
        let grommetMesh=try mesh(grommetReference)
        for racket in cold {
            let grommets=racket.children.compactMap { $0 as? ModelEntity }.filter { $0.model?.mesh === grommetMesh }
            #expect(grommets.count == 40)
        }
        print("SceneResourceReuse rackets=20 cold_ms=\(coldMilliseconds) warm_ms=\(warmMilliseconds) cold_generated=\(coldMetrics.generations) warm_generated=\(warmMetrics.generations-coldMetrics.generations) warm_hits=\(warmMetrics.hits-coldMetrics.hits) cache_entries=\(warmMetrics.entries)")
    }

    @Test func cacheStaysBoundedEvictsLeastUsedAndNeverInvalidatesLiveEntities() throws {
        ClubScene.resetMeshCacheForTesting()
        let parent=Entity(),mat=ClubScene.material(.white),capacity=ClubScene.meshCacheMetrics.capacity
        let protected=ClubScene.sphere(parent,0.0025,[1,2,3],mat)
        let protectedMesh=try mesh(protected)
        var oldest:MeshResource?
        for index in 0..<(capacity-1) {
            let entity=ClubScene.sphere(parent,0.01+Float(index)*0.00001,.zero,mat)
            if index == 0 { oldest=try mesh(entity) }
        }
        let touched=ClubScene.sphere(parent,0.0025,.zero,mat)
        let touchedMesh=try mesh(touched)
        #expect(touchedMesh === protectedMesh)
        for index in 0..<8 { ClubScene.sphere(parent,0.03+Float(index)*0.00001,.zero,mat) }
        let metrics=ClubScene.meshCacheMetrics
        #expect(metrics.entries == capacity && metrics.evictions == 8 && metrics.generations == capacity+8)
        let kept=ClubScene.sphere(parent,0.0025,.zero,mat),keptMesh=try mesh(kept)
        #expect(keptMesh === protectedMesh)
        let recreated=ClubScene.sphere(parent,0.01,.zero,mat),recreatedMesh=try mesh(recreated)
        #expect(recreatedMesh !== oldest)
        #expect(ClubScene.meshCacheMetrics.entries == capacity && ClubScene.meshCacheMetrics.evictions == 9)
        #expect(protected.parent === parent && protected.position == V3(1,2,3))
        #expect(protected.model?.mesh === protectedMesh && protectedMesh.bounds.extents.x > 0)
    }

    @Test func repeatedCourtBuildReusesCachedGeometryAndReportsMeshColdWarmTimes() {
        ClubScene.resetMeshCacheForTesting()
        let coldStart=Date.timeIntervalSinceReferenceDate
        let cold=ClubScene.build()
        let coldMilliseconds=(Date.timeIntervalSinceReferenceDate-coldStart)*1000
        let coldMetrics=ClubScene.meshCacheMetrics
        let warmStart=Date.timeIntervalSinceReferenceDate
        let warm=ClubScene.build()
        let warmMilliseconds=(Date.timeIntervalSinceReferenceDate-warmStart)*1000
        let warmMetrics=ClubScene.meshCacheMetrics
        #expect(coldMetrics.generations > 0 && coldMetrics.evictions == 0)
        #expect(warmMetrics.generations == coldMetrics.generations && warmMetrics.evictions == 0)
        #expect(warmMetrics.hits > coldMetrics.hits && warmMetrics.entries <= warmMetrics.capacity)
        #expect(cold.root.children.count == warm.root.children.count)
        #expect(cold.robotRacket.parent === cold.robotArm && warm.robotRacket.parent === warm.robotArm)
        #expect(cold.robotArm.parent === cold.robotBody && warm.robotArm.parent === warm.robotBody)
        print("SceneResourceReuse court_mesh_cold_ms=\(coldMilliseconds) court_mesh_warm_ms=\(warmMilliseconds) cached_cold_generated=\(coldMetrics.generations) cached_warm_generated=\(warmMetrics.generations-coldMetrics.generations) warm_hits=\(warmMetrics.hits-coldMetrics.hits) cache_entries=\(warmMetrics.entries) textures_not_reset=true")
    }
}
#endif
