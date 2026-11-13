import XCTest
@testable import BattleCore

final class WorldTests: XCTestCase {
    func testSeededRandomIsReproducible() {
        var a = SeededRandom(seed: 42), b = SeededRandom(seed: 42), c = SeededRandom(seed: 43)
        let xs = (0..<10).map { _ in a.next() }
        XCTAssertEqual(xs, (0..<10).map { _ in b.next() })
        XCTAssertNotEqual(xs, (0..<10).map { _ in c.next() })
        var r = SeededRandom(seed: 1)
        for _ in 0..<1000 {
            let f = r.nextFloat()
            XCTAssertTrue(f >= 0 && f < 1)
            XCTAssertTrue((0..<5).contains(r.int(below: 5)))
        }
    }

    func testRaycastHitsTerrain() throws {
        let world = makeWorld()
        // 目の高さ 1.6 m (地面から)から, 前下がり 45° に撃つ → 約 1.6 m 先.
        let dir = Vec3(0, -1, -1).normalized()
        let hit = try XCTUnwrap(world.raycast(origin: Vec3(0, 3.6, 0), direction: dir, maxDistance: 100))
        XCTAssertEqual(hit.point.y, 2, accuracy: 0.01)
        XCTAssertEqual(hit.distance, 1.6 * Float(2).squareRoot(), accuracy: 0.05)
        XCTAssertEqual(hit.surface, .terrain)
        XCTAssertGreaterThan(hit.normal.y, 0.9)
        // 空へは当たらない.
        XCTAssertNil(world.raycast(origin: Vec3(0, 3.6, 0), direction: Vec3(0, 1, -1).normalized(), maxDistance: 300))
    }

    func testRaycastHitsBoxesIncludingRotated() throws {
        let world = makeWorld(obstacles: [.box(center: Vec3(0, 4, -10), half: Vec3(2, 2, 1)),
                                          .box(center: Vec3(20, 4, -10), half: Vec3(3, 2, 0.5), yaw: .pi / 2)])
        let h1 = try XCTUnwrap(world.raycast(origin: Vec3(0, 4, 0), direction: .forward, maxDistance: 100))
        XCTAssertEqual(h1.distance, 9, accuracy: 0.01)
        XCTAssertEqual(h1.surface, .obstacle(0))
        XCTAssertEqual(h1.normal, Vec3(0, 0, 1))
        // 90° 回した箱: 世界の x 方向の幅が 0.5, z 方向の幅が 3. x 方向から撃つ → x = 20 - 0.5 = 19.5.
        let h2 = try XCTUnwrap(world.raycast(origin: Vec3(10, 4, -10), direction: Vec3(1, 0, 0), maxDistance: 100))
        XCTAssertEqual(h2.distance, 9.5, accuracy: 0.01)
        XCTAssertEqual(h2.surface, .obstacle(1))
        // 箱のわきを通る線は当たらない.
        XCTAssertNil(world.raycast(origin: Vec3(5, 4, 0), direction: .forward, maxDistance: 100)
            .flatMap { $0.surface == .terrain ? nil : $0 })
        // 箱の上を通る線.
        XCTAssertNil(world.raycast(origin: Vec3(0, 8, 0), direction: .forward, maxDistance: 60))
    }

    func testRaycastHitsCylinderSideAndTop() throws {
        let world = makeWorld(obstacles: [.cylinder(base: Vec3(0, 2, -10), radius: 1, height: 4)])
        let side = try XCTUnwrap(world.raycast(origin: Vec3(0, 4, 0), direction: .forward, maxDistance: 100))
        XCTAssertEqual(side.distance, 9, accuracy: 0.01)
        XCTAssertEqual(side.normal.z, 1, accuracy: 1e-3)
        let top = try XCTUnwrap(world.raycast(origin: Vec3(0, 10, -10), direction: Vec3(0, -1, 0), maxDistance: 100))
        XCTAssertEqual(top.distance, 4, accuracy: 0.01)
        XCTAssertEqual(top.normal, Vec3(0, 1, 0))
        // 円柱の外側すれすれを通る.
        XCTAssertNotEqual(world.raycast(origin: Vec3(1.2, 4, 0), direction: .forward, maxDistance: 100)?.surface, .obstacle(0))
    }

    func testRaycastStopsAtNearestThing() throws {
        let world = makeWorld(obstacles: [.box(center: Vec3(0, 4, -10), half: Vec3(2, 2, 1)),
                                          .box(center: Vec3(0, 4, -20), half: Vec3(2, 2, 1))])
        let hit = try XCTUnwrap(world.raycast(origin: Vec3(0, 4, 0), direction: .forward, maxDistance: 100))
        XCTAssertEqual(hit.surface, .obstacle(0))
        XCTAssertNil(world.raycast(origin: Vec3(0, 4, 0), direction: .forward, maxDistance: 5).flatMap { _ in nil as RayHit? })
    }

    func testRaycastIntoTheSeaHitsTheWaterSurface() throws {
        let world = makeWorld()
        let hit = try XCTUnwrap(world.raycast(origin: Vec3(32, 3, 0), direction: Vec3(0, -1, 0), maxDistance: 100))
        XCTAssertEqual(hit.point.y, 0, accuracy: 0.01)         // waterY = 0
        XCTAssertEqual(hit.normal, .up)
    }

    func testRaycastMaxDistance() {
        let world = makeWorld(obstacles: [.box(center: Vec3(0, 4, -50), half: Vec3(2, 2, 1))])
        XCTAssertNil(world.raycast(origin: Vec3(0, 4, 0), direction: .forward, maxDistance: 20))
        XCTAssertNotNil(world.raycast(origin: Vec3(0, 4, 0), direction: .forward, maxDistance: 60))
    }

    func testSpawnsForTwoThreeFourPlayers() throws {
        let world = makeWorld(obstacles: [.cylinder(base: Vec3(0, 2, 25), radius: 2, height: 5)])
        for n in 2...4 {
            let s = try XCTUnwrap(world.arenaSpawns(centerX: 0, centerZ: 0, radius: 40, count: n), "count \(n)")
            XCTAssertEqual(s.count, n)
            for a in s {
                XCTAssertGreaterThan(a.position.y, GameRules.minGroundY)
                XCTAssertTrue(world.isClear(x: a.position.x, z: a.position.z, radius: GameRules.playerRadius))
                XCTAssertEqual(a.position.y, world.terrainHeight(x: a.position.x, z: a.position.z), accuracy: 1e-3)
                // 中心を向いている.
                let toCenter = Vec3(-a.position.x, 0, -a.position.z).normalized()
                XCTAssertGreaterThan(PlayerState(position: a.position, yaw: a.yaw).forward.dot(toCenter), 0.99)
            }
            for i in 0..<n { for j in (i + 1)..<n { XCTAssertGreaterThan((s[i].position - s[j].position).length, 30) } }
        }
    }

    func testSpawnsAvoidWaterAndFailWhenImpossible() {
        let world = makeWorld()
        // 半径 80 は 海(x > 30)や地図の外に出てしまう → 水の上は選ばず, ずらしても無理なら nil.
        XCTAssertNil(world.arenaSpawns(centerX: 0, centerZ: 0, radius: 200, count: 3))
        if let s = world.arenaSpawns(centerX: 0, centerZ: 0, radius: 40, count: 2) {
            XCTAssertTrue(s.allSatisfy { $0.position.x < 30 })
        }
    }

    func testMapDataJSON() throws {
        var map = MapData(id: "island", name: "はじまりの島")
        map.obstacles = [.box(center: Vec3(1, 2, 3), half: Vec3(1, 1, 1), yaw: 0.5), .cylinder(base: Vec3(4, 0, 4), radius: 0.4, height: 4)]
        map.props = [PropInstance(name: "TreePine", position: Vec3(1, 0, 1))]
        map.pois = [MapData.POI(name: "村", p: [40, 12], r: 60)]
        map.loot = [[1, 2, 3]]
        map.spawns = [[180, 0]]
        let back = try MapData.decode(from: JSONEncoder().encode(map))
        XCTAssertEqual(back, map)
        XCTAssertEqual(back.pois[0].center.x, 40)
        // 省いた項目には初期値が入る(JSON にある項目だけでも読める).
        let tiny = #"{"id":"a","name":"b","waterY":0,"sun":{"direction":[0,1,0],"color":[1,1,1],"intensity":1},"ambient":1,"sky":"s","fog":{"color":[1,1,1],"start":1,"end":2},"props":[],"obstacles":[],"spawns":[],"loot":[],"pois":[]}"#
        XCTAssertNoThrow(try MapData.decode(from: Data(tiny.utf8)))
    }
}
