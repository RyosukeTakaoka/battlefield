import XCTest
@testable import BattleCore

/// ロードで動く Core の処理の時間を測る(実機の「島をつくっています」に当たる部分).
final class LoadBenchTests: XCTestCase {
    func fakeMesh(vertices: Int, triangles: Int) -> MeshData {
        var m = MeshData()
        for i in 0..<vertices {
            let a = Float(i)
            m.positions.append(Vec3(sin(a), Float(i % 10) * 0.3, cos(a)))
            m.normals.append(Vec3(0, 1, 0))
            m.uvs.append(SIMD2(0.5, 0.5))
        }
        for t in 0..<triangles { m.indices += [UInt32(t % vertices), UInt32((t + 1) % vertices), UInt32((t + 2) % vertices)] }
        return m
    }

    func testMeasureLoad() throws {
        let clock = ContinuousClock()
        let begin = clock.now
        var t = clock.now
        func lap(_ label: String) { let n = clock.now; print("BENCH \(label): \(n - t)"); t = n }
        let world = try loadIsland()
        lap("島のデータを読む")
        let sizes: [String: (Int, Int)] = ["TreeRound": (683, 1336), "TreeSakura": (1112, 2144), "TreePine": (147, 236), "GrassTuft": (27, 9),
                                           "LogPile": (1692, 3240), "Bush": (126, 240), "RockA": (240, 80), "RockB": (240, 80),
                                           "Log": (282, 540), "RockSavanna": (240, 80), "Chalet": (534, 178), "House": (192, 64), "StoneArch": (324, 108)]
        var meshes: [String: [MeshData]] = [:]
        for (k, v) in sizes { meshes[k] = (0..<4).map { _ in fakeMesh(vertices: v.0, triangles: v.1) } }
        lap("仮の小物の形")
        var total = 0
        for cx in 0..<4 {
            for cz in 0..<4 {
                let xMin = -256 + Float(cx) * 128, zMax = 256 - Float(cz) * 128
                let image = TerrainMesher.ImageRect(xMin: -256, xMax: 0, zMin: 0, zMax: 256)
                let chunk = TerrainMesher.chunk(world.terrain, xMin: xMin, xMax: xMin + 128, zMin: zMax - 128, zMax: zMax, image: image,
                                                splitRock: true, uv: .init())
                total += chunk.ground.triangleCount
            }
        }
        lap("地形 16 区画")
        for cx in 0..<4 {
            for cz in 0..<4 {
                let xMin = -256 + Float(cx) * 128, zMax = 256 - Float(cz) * 128
                let inside = world.map.props.filter { $0.position.x >= xMin && $0.position.x < xMin + 128 && $0.position.z >= zMax - 128 && $0.position.z < zMax }
                total += TerrainMesher.props(inside, meshes: meshes).triangleCount
            }
        }
        lap("小物を区画ごとにまとめる")
        for kind in GameMode.Kind.allCases {
            var host = HostLogic(world: world, seed: 1)
            _ = host.beginMatch(matchId: 1, kind: kind, roster: MatchHarness.roster(kind == .battleRoyale ? 4 : 2), now: 0)
            lap("試合の準備 \(kind)")
        }
        XCTAssertGreaterThan(total, 0)
        // 最適化なし(デバッグ)でも 数秒かからないこと(Linux で 0.4 秒ほど). 遅くなったら ここで気づける.
        XCTAssertLessThan(clock.now - begin, .seconds(5))
    }
}
