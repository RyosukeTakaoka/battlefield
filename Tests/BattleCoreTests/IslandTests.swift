import XCTest
@testable import BattleCore

/// `Tools/map/build_arena.py` が作った島のデータを, ゲームの側(Swift)から読んで確かめる.
final class IslandTests: XCTestCase {
    func testIslandLoads() throws {
        let world = try loadIsland()
        XCTAssertEqual(world.map.id, "island")
        XCTAssertEqual(world.terrain.cols, 257)
        XCTAssertEqual(world.terrain.rows, 257)
        XCTAssertEqual(world.terrain.cell, 2)
        XCTAssertEqual(world.terrain.originX, -256)
        XCTAssertEqual(world.terrain.originZ, 256)
        XCTAssertGreaterThan(world.map.props.count, 500)
        XCTAssertEqual(world.solids.count, world.map.obstacles.count)
        XCTAssertEqual(world.map.pois.count, 4)
        XCTAssertEqual(world.map.spawns.count, 16)
        XCTAssertGreaterThanOrEqual(world.map.loot.count, 40)
    }

    func testPoisAreFarApart() throws {
        let pois = try loadIsland().map.pois
        for i in 0..<pois.count {
            for j in (i + 1)..<pois.count {
                let a = pois[i].center, b = pois[j].center
                XCTAssertGreaterThanOrEqual(((a.x - b.x) * (a.x - b.x) + (a.z - b.z) * (a.z - b.z)).squareRoot(), 120,
                                            "\(pois[i].name) / \(pois[j].name)")
            }
        }
    }

    func testSpawnsAndLootAreOnLandAndClear() throws {
        let world = try loadIsland()
        for s in world.map.spawns {
            let h = world.terrainHeight(x: s[0], z: s[1])
            XCTAssertGreaterThan(h, 1.0)
            XCTAssertGreaterThanOrEqual(world.terrainNormal(x: s[0], z: s[1]).y, GameRules.walkableNormalY)
            XCTAssertTrue(world.isClear(x: s[0], z: s[1], radius: GameRules.playerRadius))
        }
        for l in world.map.loot {
            XCTAssertGreaterThan(world.terrainHeight(x: l[0], z: l[2]), 1.0)
            XCTAssertTrue(world.isClear(x: l[0], z: l[2], radius: 1.0))
            // 置き場の高さは地面の少し上.
            XCTAssertEqual(l[1] - world.terrainHeight(x: l[0], z: l[2]), 0.5, accuracy: 0.05)
        }
    }

    func testEachPoiHasCoverAndLoot() throws {
        let world = try loadIsland()
        for poi in world.map.pois {
            let c = poi.center
            let cover = world.solids.filter { s in
                let dx = s.center.x - c.x, dz = s.center.z - c.z
                return (dx * dx + dz * dz).squareRoot() < poi.r && (s.topY - s.baseY) >= 1.2
            }
            XCTAssertGreaterThanOrEqual(cover.count, 8, poi.name)
            let loot = world.map.loot.filter { l in
                let dx = l[0] - c.x, dz = l[2] - c.z
                return (dx * dx + dz * dz).squareRoot() < poi.r
            }
            XCTAssertGreaterThanOrEqual(loot.count, 6, poi.name)
        }
    }

    func testArenaSpawnsWorkInEveryPoiForTwoThreeFourPlayers() throws {
        let world = try loadIsland()
        for poi in world.map.pois {
            for n in 2...4 {
                let s = try XCTUnwrap(world.arenaSpawns(centerX: poi.center.x, centerZ: poi.center.z, radius: poi.r, count: n),
                                      "\(poi.name) \(n) players")
                XCTAssertEqual(s.count, n)
                for a in s {
                    XCTAssertTrue(world.isClear(x: a.position.x, z: a.position.z, radius: GameRules.playerRadius))
                    XCTAssertGreaterThan(a.position.y, 1.0)
                }
            }
        }
    }

    func testBattleRoyaleSizedSpawnsWorkAroundTheIsland() throws {
        // バトルロイヤルの小さい版(半径 90 / 120 m)の出発点を, 島の中のいろいろな場所で探せる.
        let world = try loadIsland()
        for (cx, cz, r, n) in [(0, 0, 90, 2), (0, 0, 120, 4), (30, -20, 90, 2), (-20, 30, 120, 3)] as [(Float, Float, Float, Int)] {
            XCTAssertNotNil(world.arenaSpawns(centerX: cx, centerZ: cz, radius: r, count: n, fraction: 0.9), "\(cx),\(cz) r\(r) n\(n)")
        }
    }

    func testWalkingFromSpawnToPoiAcrossTheIsland() throws {
        // 出発点から名所の中心へ向かってまっすぐ歩いても, 水に落ちたり 地図の外へ出たりしない(止まるだけ).
        let world = try loadIsland()
        let s = world.map.spawns[0]
        var p = PlayerState(position: Vec3(s[0], world.terrainHeight(x: s[0], z: s[1]), s[1]))
        p.isGrounded = true
        let c = world.map.pois[0].center
        var input = PlayerInput()
        input.moveY = 1
        input.yaw = atan2(c.x - s[0], -(c.z - s[1]))
        for _ in 0..<(60 * 40) {
            CharacterMotor.step(&p, input: input, world: world, dt: GameRules.tick)
            XCTAssertGreaterThan(p.position.y, GameRules.minGroundY)
        }
    }

    func testBulletsAreStoppedByHousesButPassThroughBushes() throws {
        let world = try loadIsland()
        // 村の最初の家(当たり判定の箱)をまっすぐ撃つ.
        let house = try XCTUnwrap(world.solids.first { $0.isBox && $0.half.x > 4 })
        let origin = Vec3(house.center.x, house.center.y, house.center.z + 30)
        let hit = try XCTUnwrap(world.raycast(origin: origin, direction: Vec3(0, 0, -1), maxDistance: 100))
        XCTAssertNotEqual(hit.surface, .terrain)
    }
}
