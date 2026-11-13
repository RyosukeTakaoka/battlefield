import XCTest
@testable import BattleCore

final class FoundationTests: XCTestCase {
    func testVectorBasics() {
        XCTAssertEqual(Vec3(3, 4, 0).length, 5, accuracy: 1e-5)
        XCTAssertEqual(Vec3(1, 0, 0).cross(Vec3(0, 1, 0)), Vec3(0, 0, 1))
        XCTAssertEqual(Vec3.forward, Vec3(0, 0, -1))
        XCTAssertEqual(Vec3(0, 0, 0).normalized(or: .up), .up)
        XCTAssertEqual(clamp(5, 0, 3), 3)
        XCTAssertEqual(abs(wrapAngle(3 * .pi)), .pi, accuracy: 1e-4)     // π と -π は同じ向き
        XCTAssertEqual(wrapAngle(2 * .pi + 0.5), 0.5, accuracy: 1e-4)
        XCTAssertEqual(approach(2, 0), 0, accuracy: 1e-6)
        XCTAssertGreaterThan(approach(2, 10), 0.999)
    }

    func testHeightfieldInterpolates() {
        let hf = makeHeightfield { x, _ in x * 0.5 }          // x 方向に傾いた面
        XCTAssertEqual(hf.height(x: 0, z: 0), 0, accuracy: 1e-4)
        XCTAssertEqual(hf.height(x: 10, z: 7), 5, accuracy: 1e-3)
        XCTAssertEqual(hf.height(x: -13.3, z: 22), -6.65, accuracy: 1e-2)
        XCTAssertTrue(hf.contains(x: 0, z: 0))
        XCTAssertFalse(hf.contains(x: 100, z: 0))
        // 範囲の外は端の値.
        XCTAssertEqual(hf.height(x: 1000, z: 0), hf.height(x: 40, z: 0), accuracy: 1e-4)
        // 面の法線は傾きのぶん x の負の向きへ.
        let n = hf.normal(col: 20, row: 20)
        XCTAssertLessThan(n.x, 0)
        XCTAssertEqual(n.length, 1, accuracy: 1e-4)
    }

    func testHeightfieldLoadsPPHF() throws {
        let src = makeHeightfield(cols: 5, rows: 4, cell: 2, originX: -4, originZ: 3) { x, z in x + 2 * z }
        let data = pphfData(cols: 5, rows: 4, originX: -4, originZ: 3, cell: 2, heights: src.heights)
        let hf = try Heightfield(data: data)
        XCTAssertEqual(hf.cols, 5)
        XCTAssertEqual(hf.rows, 4)
        for (a, b) in zip(hf.heights, src.heights) { XCTAssertEqual(a, b, accuracy: 0.01) }
        XCTAssertThrowsError(try Heightfield(data: Data("XXXX".utf8)))
        XCTAssertThrowsError(try Heightfield(data: data.prefix(40)))
    }

    func testTerrainChunkIsValidAndFacesUp() {
        // まん中に急な崖のある地形.
        let hf = makeHeightfield { x, _ in x > 0 ? 12 : 0 }
        let img = TerrainMesher.ImageRect(xMin: -40, xMax: 40, zMin: -40, zMax: 40)
        let m = TerrainMesher.chunk(hf, xMin: -40, xMax: 40, zMin: -40, zMax: 40, image: img, splitRock: true, uv: .init())
        XCTAssertEqual(m.ground.positions.count, 41 * 41)
        XCTAssertFalse(m.rock.isEmpty, "the cliff should be split into the rock material")
        XCTAssertEqual(m.ground.triangleCount + m.rock.triangleCount, 40 * 40 * 2)
        for mesh in [m.ground, m.rock] {
            XCTAssertTrue(mesh.indices.allSatisfy { Int($0) < mesh.positions.count })
            XCTAssertEqual(mesh.normals.count, mesh.positions.count)
            XCTAssertEqual(mesh.uvs.count, mesh.positions.count)
        }
    }

    func testChunkUVsPointIntoTheImage() {
        let hf = makeHeightfield { _, _ in 0 }
        // 区画は絵(-40〜40)の右半分(x: 0〜40)だけ.
        let img = TerrainMesher.ImageRect(xMin: -40, xMax: 40, zMin: -40, zMax: 40)
        let m = TerrainMesher.chunk(hf, xMin: 0, xMax: 40, zMin: -40, zMax: 40, image: img, splitRock: false, uv: .init())
        XCTAssertEqual(m.ground.positions.count, 21 * 41)
        XCTAssertEqual(m.ground.uvs.first!.x, 0.5, accuracy: 1e-4)      // 区画の左端 = 絵の真ん中
        XCTAssertEqual(m.ground.uvs.first!.y, 1, accuracy: 1e-4)        // 最初の行 = z 最大 = 絵の上(下から数える約束)
        XCTAssertEqual(m.ground.uvs.last!.x, 1, accuracy: 1e-4)
        let flipped = TerrainMesher.chunk(hf, xMin: 0, xMax: 40, zMin: -40, zMax: 40, image: img, splitRock: false,
                                          uv: .init(originAtBottom: false))
        XCTAssertEqual(flipped.ground.uvs.first!.y, 0, accuracy: 1e-4)
    }

    func testAdjacentChunksShareAnEdge() {
        let hf = makeHeightfield { x, z in sin(x * 0.2) * 3 + z * 0.1 }
        let img = TerrainMesher.ImageRect(xMin: -40, xMax: 40, zMin: -40, zMax: 40)
        let a = TerrainMesher.chunk(hf, xMin: -40, xMax: 0, zMin: -40, zMax: 40, image: img, splitRock: false, uv: .init())
        let b = TerrainMesher.chunk(hf, xMin: 0, xMax: 40, zMin: -40, zMax: 40, image: img, splitRock: false, uv: .init())
        let aEdge = a.ground.positions.filter { $0.x == 0 }
        let bEdge = b.ground.positions.filter { $0.x == 0 }
        XCTAssertEqual(aEdge.count, 41)
        XCTAssertEqual(aEdge, bEdge)
    }

    func testFlatWaterAndPropMerge() {
        let w = TerrainMesher.flatWater(half: 300)
        XCTAssertEqual(w.triangleCount, 2)
        XCTAssertTrue(w.normals.allSatisfy { $0 == .up })

        var tri = MeshData()
        tri.positions = [Vec3(1, 0, 0), Vec3(0, 1, 0), Vec3(0, 0, 1)]
        tri.normals = [Vec3(1, 0, 0), Vec3(0, 1, 0), Vec3(0, 0, 1)]
        tri.uvs = Array(repeating: SIMD2(0, 0), count: 3)
        tri.indices = [0, 1, 2]
        let merged = TerrainMesher.props([PropInstance(name: "T", position: Vec3(10, 0, 0)),
                                          PropInstance(name: "T", position: Vec3(0, 5, 0), scale: Vec3(2, 2, 2)),
                                          PropInstance(name: "Missing", position: .zero)],
                                         meshes: ["T": [tri]])
        XCTAssertEqual(merged.triangleCount, 2)               // 知らない種類は飛ばす
        XCTAssertEqual(merged.positions[0], Vec3(11, 0, 0))
        XCTAssertEqual(merged.positions[3], Vec3(2, 5, 0))    // 2 倍にして (0,5,0) へ
        XCTAssertEqual(merged.positions[4], Vec3(0, 7, 0))
        XCTAssertEqual(merged.indices, [0, 1, 2, 3, 4, 5])
    }

    func testPropInstanceJSONRoundTrip() throws {
        let p = PropInstance(name: "TreePine", variant: 2, position: Vec3(1, 2, 3), yaw: 0.5, scale: Vec3(1, 1.2, 1))
        let data = try JSONEncoder().encode([p])
        let back = try JSONDecoder().decode([PropInstance].self, from: data)
        XCTAssertEqual(back, [p])
        let raw = #"[["Rock", 1, 4.0, 5.0, 6.0, 0.25, 1, 1, 1]]"#.data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode([PropInstance].self, from: raw)[0].position, Vec3(4, 5, 6))
    }

    func testSmoothNoiseIsDeterministicAndBounded() {
        let n = SmoothNoise(seed: 7)
        XCTAssertEqual(n.value(1.37), SmoothNoise(seed: 7).value(1.37))
        for i in 0..<200 { XCTAssertLessThanOrEqual(abs(n.fractal(Float(i) * 0.31)), 1.0001) }
    }
}
