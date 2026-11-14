import XCTest
@testable import BattleCore

final class ZoneAndModeTests: XCTestCase {
    func testGameModeTable() {
        let rb = GameMode.make(kind: .roundBattle, playerCount: 3)
        XCTAssertEqual(rb.arenaRadius, 60)
        XCTAssertEqual(rb.startShield, 25)
        XCTAssertEqual(rb.winScore, 3)
        XCTAssertEqual(rb.maxRounds, 12)
        XCTAssertFalse(rb.respawns)
        XCTAssertFalse(rb.lootHasWeapons)
        XCTAssertEqual(rb.stages.map(\.dps), [5, 12])
        XCTAssertEqual(GameMode.roundBattleSets.count, 5)

        XCTAssertEqual(GameMode.make(kind: .killRace, playerCount: 2).killTarget, 10)
        XCTAssertEqual(GameMode.make(kind: .killRace, playerCount: 4).killTarget, 15)
        let kr = GameMode.make(kind: .killRace, playerCount: 3)
        XCTAssertTrue(kr.respawns)
        XCTAssertEqual(kr.outsideDPS, 5)
        XCTAssertEqual(kr.lootRespawnDelay, 20)
        XCTAssertEqual(kr.timeLimit, 300)

        let small2 = GameMode.make(kind: .battleRoyale, playerCount: 2)
        let small4 = GameMode.make(kind: .battleRoyale, playerCount: 4)
        let big = GameMode.make(kind: .battleRoyale, playerCount: 8)
        XCTAssertEqual([small2.arenaRadius, small4.arenaRadius, big.arenaRadius], [90, 120, 210])
        XCTAssertEqual([small2.islandWide, small4.islandWide, big.islandWide], [false, false, true])
        XCTAssertEqual(small2.totalZoneDuration, 190, accuracy: 0.1)             // 約 3 分
        XCTAssertEqual(big.totalZoneDuration, 260, accuracy: 0.1)                // 約 4〜5 分
        XCTAssertEqual(big.stages.map(\.dps), [2, 4, 7, 10, 15])
        XCTAssertEqual(big.stages[0].endFraction * 210, 120, accuracy: 0.01)
        XCTAssertEqual(small2.stages[0].endFraction * 90, 90 * 120 / 210, accuracy: 0.01)    // 同じ割合
        XCTAssertEqual(GameMode.defaultKind(playerCount: 2), .roundBattle)
        XCTAssertEqual(GameMode.defaultKind(playerCount: 4), .roundBattle)
        XCTAssertEqual(GameMode.defaultKind(playerCount: 5), .battleRoyale)
    }

    func testZoneShrinksOnSchedule() {
        let mode = GameMode.make(kind: .battleRoyale, playerCount: 8)
        let ends = mode.stages.map { Disc(x: 0, z: 0, r: 210 * $0.endFraction) }
        let zone = Zone(initial: Disc(x: 0, z: 0, r: 210), ends: ends, stages: mode.stages, outsideDPS: 0)
        XCTAssertEqual(zone.circle(at: 0).r, 210)
        XCTAssertEqual(zone.circle(at: 44).r, 210)                              // 45 秒は待つ
        XCTAssertEqual(zone.circle(at: 60).r, (210 + 120) / 2, accuracy: 0.01)   // せばまる途中(15 / 30 秒)
        XCTAssertEqual(zone.circle(at: 75).r, 120, accuracy: 0.01)
        XCTAssertEqual(zone.circle(at: 100).r, 120, accuracy: 0.01)              // 次の段階も 30 秒は待つ
        XCTAssertEqual(zone.circle(at: 135).r, 70, accuracy: 0.01)
        XCTAssertEqual(zone.circle(at: 9999).r, 0, accuracy: 0.01)
        XCTAssertEqual(zone.dps(at: 10), 2)
        XCTAssertEqual(zone.dps(at: 80), 4)
        XCTAssertEqual(zone.dps(at: 9999), 15)
        XCTAssertTrue(zone.isOutside(x: 150, z: 0, at: 80))
        XCTAssertFalse(zone.isOutside(x: 100, z: 0, at: 80))
        XCTAssertEqual(zone.stageIndex(at: 0), 0)
        XCTAssertEqual(zone.stageIndex(at: 80), 1)
        let next = zone.timeUntilChange(at: 10)
        XCTAssertEqual(next?.shrinking, false)
        XCTAssertEqual(next?.seconds ?? 0, 35, accuracy: 0.01)
        XCTAssertEqual(zone.timeUntilChange(at: 60)?.shrinking, true)
        XCTAssertNil(zone.timeUntilChange(at: 9999))
    }

    func testZoneWithNoStagesUsesTheConstantDamage() {
        let z = Zone(initial: Disc(x: 0, z: 0, r: 80), ends: [], stages: [], outsideDPS: 5)
        XCTAssertEqual(z.circle(at: 1000).r, 80)
        XCTAssertEqual(z.dps(at: 50), 5)
    }

    func testLootTableRatios() {
        var rng = SeededRandom(seed: 3)
        var counts: [LootKind: Int] = [:]
        for _ in 0..<20000 { counts[LootTable.roll(rng: &rng, withWeapons: true), default: 0] += 1 }
        let n = Float(20000)
        let weapons = Float((counts[.assaultRifle] ?? 0) + (counts[.shotgun] ?? 0) + (counts[.sniper] ?? 0)) / n
        XCTAssertEqual(weapons, 0.45, accuracy: 0.02)
        XCTAssertEqual(Float(counts[.shield] ?? 0) / n, 0.30, accuracy: 0.02)
        XCTAssertEqual(Float(counts[.medkit] ?? 0) / n, 0.25, accuracy: 0.02)
        XCTAssertEqual(Float(counts[.assaultRifle] ?? 0) / (weapons * n), 0.40, accuracy: 0.03)
        var noWeapons: Set<LootKind> = []
        for _ in 0..<500 { noWeapons.insert(LootTable.roll(rng: &rng, withWeapons: false)) }
        XCTAssertEqual(noWeapons, [.shield, .medkit])
    }
}

final class HostLogicTests: XCTestCase {
    func makeRound(_ kind: GameMode.Kind = .roundBattle, players n: Int = 2) throws -> MatchHarness {
        let h = MatchHarness(world: try loadIsland())
        h.begin(kind, players: n)
        return h
    }

    // MARK: 申し出

    func testValidClaimDamagesShieldFirst() throws {
        let h = try makeRound()
        XCTAssertEqual(h.state.phase, .playing)
        XCTAssertEqual(h.shield(1), 25)
        h.place(0, 0, 0, weapon: .assaultRifle); h.place(1, 20, 0)
        h.claim(from: 0, to: 1, weapon: .assaultRifle, head: false, distance: 20)        // 14
        XCTAssertEqual(h.shield(1), 11)
        XCTAssertEqual(h.hp(1), 100)
        h.now += 1
        h.place(0, 0, 0, weapon: .sniper)
        h.claim(from: 0, to: 1, weapon: .sniper, head: false, distance: 20, shotId: 2)   // 70: シールド 11 + HP 59
        XCTAssertEqual(h.shield(1), 0)
        XCTAssertEqual(h.hp(1), 100 - 59)
        XCTAssertTrue(h.events.contains { if case .damaged(1, 0, .sniper, 41, 0, false) = $0 { return true } else { return false } })
    }

    func testClaimsThatMustBeRejected() throws {
        let h = try makeRound()
        h.place(0, 0, 0); h.place(1, 20, 0)
        func rejected(_ out: [Message], _ why: String) { XCTAssertTrue(out.isEmpty, why) }
        rejected(h.claim(from: 0, to: 1, weapon: .handgun, distance: 20), "weapon differs from what the host saw")
        rejected(h.claim(from: 0, to: 0, distance: 0), "self")
        rejected(h.claim(from: 0, to: 1, distance: 300), "beyond 1.1 × range (sniper range 300)")
        rejected(h.claim(from: 0, to: 1, distance: 60), "distance disagrees with positions by more than 5 m")
        rejected(h.claim(from: 0, to: 1, pellets: 2, distance: 20), "sniper has 1 pellet")
        rejected(h.claim(from: 0, to: 5, distance: 20), "no such target")
        // sender が違う(他の人のふりをする).
        let spoof = h.host.handle(.hitClaim(HitClaimMessage(shotId: 9, attacker: 0, target: 1, weapon: .sniper, head: true, pellets: 1,
                                                            distance: 20)), sender: 1, state: h.state, now: h.now)
        rejected(spoof, "attacker must be the sender")
        XCTAssertEqual(h.hp(1), 100)
        // 正しい申し出は通る. 通信で かたまって届いた 2〜3 個は通すが, ずっと速すぎる申し出は 通さない.
        XCTAssertFalse(h.claim(from: 0, to: 1, head: false, distance: 20, shotId: 20).isEmpty)
        h.now += 0.05
        XCTAssertFalse(h.claim(from: 0, to: 1, head: false, distance: 20, shotId: 21).isEmpty, "a small burst is fine")
        var accepted = 0
        for i in 0..<10 {                                  // スナイパー(0.8 発/秒)で 0.05 秒ごとに 10 回
            h.now += 0.05
            if !h.claim(from: 0, to: 1, head: false, distance: 20, shotId: UInt16(30 + i)).isEmpty { accepted += 1 }
            if !h.alive(1) { break }
        }
        XCTAssertLessThanOrEqual(accepted, 1, "spamming faster than the weapon is rejected")
        // 同じ shotId の 2 度送り.
        h.now += 2
        rejected(h.claim(from: 0, to: 1, head: false, distance: 20, shotId: 20), "duplicate shotId")
    }

    func testClaimBurstsAreFineButSpamIsCapped() throws {
        let h = try makeRound()
        // 100 m はなれて アサルトライフル(1 発 9 ダメージ前後なので, すぐには たおれない).
        h.place(0, 0, 0, weapon: .assaultRifle); h.place(1, 100, 0)
        var accepted = 0
        for i in 0..<30 {                                  // 0.5 秒に 30 回(武器は 9 発/秒)
            if !h.claim(from: 0, to: 1, weapon: .assaultRifle, head: false, distance: 100, shotId: UInt16(i + 1)).isEmpty { accepted += 1 }
            h.now += 0.5 / 30
        }
        XCTAssertTrue(h.alive(1))
        XCTAssertGreaterThanOrEqual(accepted, 5, "the real rate plus a small burst gets through")
        XCTAssertLessThanOrEqual(accepted, 9, "not 30")
        // 1 秒あとには また まとめて 3 つ 通る(通信で かたまって届いた分).
        h.now += 1
        var burst = 0
        for i in 0..<3 where !h.claim(from: 0, to: 1, weapon: .assaultRifle, head: false, distance: 100, shotId: UInt16(100 + i)).isEmpty { burst += 1 }
        XCTAssertEqual(burst, 3)
    }

    func testDeadPlayersCannotShootOrBeShot() throws {
        let h = try makeRound(.battleRoyale, players: 3)
        h.place(0, 0, 0); h.place(1, 10, 0); h.place(2, 0, 10)
        XCTAssertFalse(h.claim(from: 0, to: 1, head: true, distance: 10).isEmpty)       // 頭 140 → やられる
        XCTAssertFalse(h.alive(1))
        h.now += 2
        XCTAssertTrue(h.claim(from: 0, to: 1, distance: 10, shotId: 5).isEmpty, "target already dead")
        XCTAssertTrue(h.claim(from: 1, to: 2, distance: 14, shotId: 6).isEmpty, "attacker is dead")
        XCTAssertEqual(h.state.participant(1)?.placement, 3)
        XCTAssertEqual(h.state.participant(0)?.kills, 1)
    }

    func testNothingHappensBeforeTheRoundStarts() throws {
        let h = MatchHarness(world: try loadIsland())
        h.apply(h.host.beginMatch(matchId: 1, kind: .roundBattle, roster: MatchHarness.roster(2), now: h.now))
        XCTAssertEqual(h.state.phase, .countdown)
        h.place(0, 0, 0); h.place(1, 20, 0)
        XCTAssertTrue(h.claim(from: 0, to: 1, distance: 20).isEmpty)
    }

    func testShotgunClaimWithManyPellets() throws {
        let h = try makeRound(.battleRoyale, players: 2)
        h.place(0, 0, 0, weapon: .shotgun); h.place(1, 5, 0)
        let out = h.claim(from: 0, to: 1, weapon: .shotgun, head: false, pellets: 8, distance: 5)
        XCTAssertFalse(out.isEmpty)
        XCTAssertEqual(h.hp(1), 100 - 72)                                          // 9 × 8, シールド無し
    }

    // MARK: ひろうもの

    func testPickupFirstComeFirstServedAndRules() throws {
        let h = try makeRound(.killRace, players: 2)
        let id = try XCTUnwrap(h.state.loot.first { $0.kind == .shield || $0.kind == .medkit }?.id)
        let spot = vec(h.world.map.loot[id])
        h.place(0, spot.x, spot.z); h.place(1, spot.x + 1, spot.z)
        let kind = h.state.lootItem(id: id)!.kind
        if kind == .shield { XCTAssertEqual(h.shield(0), 0) }
        // 体力が満タンなら 救急キットはひろえない. 先に減らす.
        if kind == .medkit {
            XCTAssertTrue(h.pickup(slot: 0, loot: id).isEmpty, "full health")
            h.claim(from: 1, to: 0, weapon: .sniper, head: false, distance: 1)        // -70 → 30
            h.place(0, spot.x, spot.z)
            XCTAssertEqual(h.hp(0), 30)
        }
        let first = h.pickup(slot: 0, loot: id)
        XCTAssertFalse(first.isEmpty)
        XCTAssertTrue(h.state.lootItem(id: id)!.taken)
        if kind == .shield { XCTAssertEqual(h.shield(0), 25) } else { XCTAssertEqual(h.hp(0), 80) }
        XCTAssertTrue(h.pickup(slot: 1, loot: id).isEmpty, "already taken")
        XCTAssertTrue(h.events.contains { if case .lootTaken(id, 0, _) = $0 { return true } else { return false } })
    }

    func testPickupTooFarAndShieldCap() throws {
        let h = try makeRound(.killRace, players: 2)
        let id = try XCTUnwrap(h.state.loot.first?.id)
        let spot = vec(h.world.map.loot[id])
        h.place(0, spot.x + 20, spot.z)
        XCTAssertTrue(h.pickup(slot: 0, loot: id).isEmpty, "too far (limit 4 m)")
        XCTAssertTrue(h.pickup(slot: 0, loot: 9999).isEmpty, "no such item")
    }

    func testShieldNeverExceedsCapAndWeaponsAreAlwaysTaken() throws {
        let h = try makeRound(.killRace, players: 2)
        let w = try XCTUnwrap(h.state.loot.first { $0.kind.weapon != nil })
        let spot = vec(h.world.map.loot[w.id])
        h.place(0, spot.x, spot.z)
        XCTAssertFalse(h.pickup(slot: 0, loot: w.id).isEmpty)
        XCTAssertEqual(h.hp(0), 100)
        XCTAssertEqual(h.shield(0), 0)
    }

    func testLootIsRestoredInKillRaceAfter20Seconds() throws {
        let h = try makeRound(.killRace, players: 2)
        let item = try XCTUnwrap(h.state.loot.first { $0.kind.weapon != nil })
        let spot = vec(h.world.map.loot[item.id])
        h.place(0, spot.x, spot.z)
        h.pickup(slot: 0, loot: item.id)
        XCTAssertTrue(h.state.lootItem(id: item.id)!.taken)
        h.advance(to: h.now + 19)
        XCTAssertTrue(h.state.lootItem(id: item.id)!.taken)
        h.advance(to: h.now + 2)
        XCTAssertFalse(h.state.lootItem(id: item.id)!.taken)
        XCTAssertTrue(h.events.contains { if case .lootRestored(item.id, _) = $0 { return true } else { return false } })
    }

    // MARK: 円

    func testZoneDamageBypassesTheShield() throws {
        let h = try makeRound()
        // ラウンド戦: シールド 25 でも, 円の外では HP が直接へる(5 ダメージ/秒).
        h.place(0, h.state.arena.x, h.state.arena.z)                     // 中
        h.place(1, h.state.arena.x + 300, h.state.arena.z)               // 外
        h.advance(to: h.state.startAt + 3.5)
        XCTAssertEqual(h.shield(1), 25)
        XCTAssertEqual(h.hp(1), 100 - 15)
        XCTAssertEqual(h.hp(0), 100)
    }

    func testZoneDamageKillsAndEndsTheRound() throws {
        let h = try makeRound()
        h.place(0, h.state.arena.x, h.state.arena.z)
        h.place(1, h.state.arena.x + 300, h.state.arena.z)
        h.advance(to: h.state.startAt + 21)                              // 100 HP ÷ 5 ダメージ/秒 = 20 秒目にやられる
        XCTAssertFalse(h.alive(1))
        XCTAssertEqual(h.state.roundWinner, 0)
        XCTAssertEqual(h.state.participant(0)?.score, 1)
        XCTAssertTrue(h.events.contains { if case .eliminated(1, nil, 2) = $0 { return true } else { return false } }, "no kill credit for the zone")
    }

    func testSimultaneousZoneDeathsGiveNoPoint() throws {
        let h = try makeRound()
        h.place(0, h.state.arena.x + 300, h.state.arena.z)
        h.place(1, h.state.arena.x - 300, h.state.arena.z)
        h.advance(to: h.state.startAt + 21)
        XCTAssertFalse(h.alive(0))
        XCTAssertFalse(h.alive(1))
        XCTAssertNil(h.state.roundWinner)
        XCTAssertEqual(h.state.participants.map(\.score), [0, 0])
        XCTAssertEqual(h.state.phase, .betweenRounds)
    }

    // MARK: スタート

    func testStartRoundMessageForEachMode() throws {
        for (kind, n) in [(GameMode.Kind.roundBattle, 2), (.roundBattle, 3), (.roundBattle, 4), (.killRace, 2), (.killRace, 4),
                          (.battleRoyale, 2), (.battleRoyale, 3), (.battleRoyale, 4), (.battleRoyale, 5), (.battleRoyale, 8)] {
            let h = MatchHarness(world: try loadIsland(), seed: UInt64(n * 31 + Int(kind.rawValue)))
            h.apply(h.host.beginMatch(matchId: 3, kind: kind, roster: MatchHarness.roster(n), now: 10))
            let s = h.state
            let label = "\(kind) \(n)"
            XCTAssertEqual(s.participants.count, n, label)
            XCTAssertEqual(s.startAt, 15, label)
            XCTAssertEqual(s.zone.ends.count, s.mode.stages.count, label)
            XCTAssertFalse(s.loot.isEmpty, label)
            // 出発点: 人数ぶん・陸の上・かべの外・たがいに離れている・戦う円の中.
            let spawns = s.participants.map(\.spawn)
            XCTAssertEqual(Set(spawns.map { "\($0.x),\($0.z)" }).count, n, label)
            for sp in spawns {
                XCTAssertGreaterThan(sp.y, 1.0, label)
                XCTAssertTrue(h.world.isClear(x: sp.x, z: sp.z, radius: GameRules.playerRadius), label)
                if !s.mode.islandWide { XCTAssertTrue(s.arena.contains(x: sp.x, z: sp.z), label) }
            }
            for i in 0..<n { for j in (i + 1)..<max(n, i + 1) { XCTAssertGreaterThan((spawns[i] - spawns[j]).length, 25, label) } }
            // ひろうものは円の中だけ. 円はだんだん小さくなる(各段階の円は前の円の中).
            for item in s.loot {
                let p = vec(h.world.map.loot[item.id])
                XCTAssertTrue(s.mode.islandWide || s.arena.contains(x: p.x, z: p.z), label)
                if !s.mode.lootHasWeapons { XCTAssertNil(item.kind.weapon, label) }
            }
            var prev = s.arena
            for end in s.zone.ends {
                XCTAssertLessThanOrEqual(end.r, prev.r + 1e-3, label)
                let d = ((end.x - prev.x) * (end.x - prev.x) + (end.z - prev.z) * (end.z - prev.z)).squareRoot()
                XCTAssertLessThanOrEqual(d + end.r, prev.r + 0.5, label)
                prev = end
            }
            XCTAssertEqual(s.participants.map(\.shield), Array(repeating: s.mode.startShield, count: n), label)
            if s.mode.islandWide { XCTAssertEqual(s.arena.r, 210, label) }
        }
    }

    func testBattleRoyaleSmallArenaStaysOnTheIsland() throws {
        for seed in 1...12 {
            let h = MatchHarness(world: try loadIsland(), seed: UInt64(seed))
            h.apply(h.host.beginMatch(matchId: UInt32(seed), kind: .battleRoyale, roster: MatchHarness.roster(seed % 3 + 2), now: 0))
            let a = h.state.arena
            XCTAssertLessThanOrEqual((a.x * a.x + a.z * a.z).squareRoot() + a.r, 190, "seed \(seed)")
            XCTAssertGreaterThanOrEqual(h.state.loot.count, h.state.mode.minLootInArena, "seed \(seed)")
        }
    }

    func testSameSeedSameStart() throws {
        let a = MatchHarness(world: try loadIsland(), seed: 99), b = MatchHarness(world: try loadIsland(), seed: 99)
        a.apply(a.host.beginMatch(matchId: 1, kind: .battleRoyale, roster: MatchHarness.roster(3), now: 0))
        b.apply(b.host.beginMatch(matchId: 1, kind: .battleRoyale, roster: MatchHarness.roster(3), now: 0))
        XCTAssertEqual(a.messages, b.messages)
    }
}
