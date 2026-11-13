import XCTest
@testable import BattleCore

/// 上限 16 人(Game Center のリアルタイム対戦の上限)で動くか.
final class SixteenPlayerTests: XCTestCase {
    func testCapIsSixteen() {
        XCTAssertEqual(GameRules.maxPlayers, 16)
        XCTAssertEqual(MessageCodec.maxPlayers, 16)
        // 送る回数は人数で減らす(全員が全員へ送るため).
        XCTAssertEqual(NetSession.stateInterval(humans: 2), 1.0 / 20, accuracy: 1e-9)
        XCTAssertEqual(NetSession.stateInterval(humans: 4), 1.0 / 20, accuracy: 1e-9)
        XCTAssertEqual(NetSession.stateInterval(humans: 8), 1.0 / 15, accuracy: 1e-9)
        XCTAssertEqual(NetSession.stateInterval(humans: 9), 1.0 / 10, accuracy: 1e-9)
        XCTAssertEqual(NetSession.stateInterval(humans: 16), 1.0 / 10, accuracy: 1e-9)
    }

    func testMessagesCarrySixteenPlayersAndRejectSeventeen() {
        func players(_ n: Int) -> [PlayerSlotInfo] {
            (0..<n).map { PlayerSlotInfo(slot: $0, peerKey: UInt64($0 + 1) * 1_000_003, isBot: $0 % 3 == 0, score: $0 % 4,
                                         spawn: Vec3(Float($0) * 10, 2, -50), spawnYaw: 0, name: "プレイヤー\($0)") }
        }
        let loot = (0..<64).map { LootSpawn(id: $0, kind: LootKind.allCases[$0 % LootKind.allCases.count]) }
        let start = Message.startRound(StartRoundMessage(matchId: 7, round: 0, mode: .battleRoyale, mapId: 0, startAt: 12.5,
                                                         arena: Disc(x: 0, z: 0, r: 210), loadoutSet: 0, players: players(16),
                                                         zones: [Disc(x: 1, z: 2, r: 120)], loot: loot))
        let data = MessageCodec.encode(start)
        XCTAssertEqual(MessageCodec.decode(data), start)
        // 1 通の大きさ: 信頼ありの上限(GameKit)より ずっと小さい.
        XCTAssertLessThan(data.count, 2000)

        let end = Message.roundEnd(RoundEndMessage(matchId: 7, round: 0, winner: 15, final: true,
                                                   results: (0..<16).map { .init(placement: $0 + 1, kills: $0, score: 0) }))
        XCTAssertEqual(MessageCodec.decode(MessageCodec.encode(end)), end)
        let snap = Message.hostSnapshot(HostSnapshotMessage(matchId: 7, round: 0, hostEpoch: 0, phase: .playing,
                                                            players: (0..<16).map { .init(hp: 100 - $0, shield: $0, kills: 0, placement: 0, score: 0) },
                                                            lootTaken: (0..<64).map { $0 % 5 == 0 }))
        XCTAssertEqual(MessageCodec.decode(MessageCodec.encode(snap)), snap)

        let tooMany = Message.startRound(StartRoundMessage(matchId: 7, round: 0, mode: .battleRoyale, mapId: 0, startAt: 1,
                                                           arena: Disc(x: 0, z: 0, r: 210), loadoutSet: 0, players: players(17),
                                                           zones: [], loot: []))
        XCTAssertNil(MessageCodec.decode(MessageCodec.encode(tooMany)), "17 人は受けつけない")
    }

    func testIslandHasEnoughLootAndSpawnsForSixteen() throws {
        let world = try loadIsland()
        XCTAssertEqual(world.map.spawns.count, 16)
        XCTAssertGreaterThanOrEqual(world.map.loot.count, 64)
        XCTAssertLessThanOrEqual(world.map.loot.count, 255, "置き場の番号は 1 バイト")
    }

    func testBattleRoyaleStartForNineToSixteen() throws {
        for n in [9, 12, 16] {
            let h = MatchHarness(world: try loadIsland(), seed: UInt64(n))
            h.apply(h.host.beginMatch(matchId: 1, kind: .battleRoyale, roster: MatchHarness.roster(n), now: 0))
            let s = h.state
            XCTAssertEqual(s.participants.count, n)
            XCTAssertTrue(s.mode.islandWide)
            XCTAssertEqual(s.arena.r, 210)
            XCTAssertEqual(s.loot.count, h.world.map.loot.count, "\(n): 島じゅうの置き場を使う")
            let spawns = s.participants.map(\.spawn)
            for i in 0..<n {
                XCTAssertTrue(h.world.isClear(x: spawns[i].x, z: spawns[i].z, radius: GameRules.playerRadius))
                for j in (i + 1)..<n { XCTAssertGreaterThan((spawns[i] - spawns[j]).length, 30, "\(n) 人: \(i) と \(j)") }
            }
        }
    }

    func testSixteenBotsFinishABattleRoyale() throws {
        let world = try loadIsland()
        let m = BotMatch(world: world, kind: .battleRoyale, roster: BotMatch.allBots(16), seed: 16)
        m.run(until: { m.h.state.phase == .finished }, timeout: 60 * 8)
        XCTAssertEqual(m.h.state.phase, .finished)
        // 順位は 1〜16 が 1 回ずつ(同時に円でやられたときも, ホストが処理した順で決まる).
        let placements = m.h.state.participants.map(\.placement).filter { $0 > 0 }.sorted()
        XCTAssertEqual(Set(placements).count, placements.count, "\(placements)")
        XCTAssertGreaterThan(m.hits, 0, "ボットどうしが撃ち合った")
    }

    func testSixteenDevicesPlayABattleRoyale() throws {
        let keys = (0..<16).map { UInt64(1000 + ($0 * 37) % 101) }        // ばらばらの peerKey
        let c = Cluster(world: try loadIsland(), keys: keys, skew: keys.indices.map { Double($0) * 13.7 }, seed: 99)
        c.loss = 0.1
        c.connectAll()
        c.run(3)
        let hostKey = keys.min()!
        XCTAssertTrue(c.sessions.allSatisfy { $0.status == .lobby && $0.hostKey == hostKey })
        let host = c.hostIndex!
        c.startMatch(host: host, kind: .battleRoyale)
        c.run(until: { c.sessions.allSatisfy { $0.match.phase == .playing } }, timeout: 12)
        XCTAssertTrue(c.sessions.allSatisfy { $0.match.phase == .playing })
        XCTAssertEqual(c.sessions[0].match.participants.count, 16)
        XCTAssertEqual(Set(c.sessions.compactMap(\.mySlot)).count, 16, "全員が ちがう slot")
        XCTAssertEqual(c.sessions[0].renderDelay, 0.2, accuracy: 1e-9, "16 人は 10 回/秒 → 相手は 0.2 秒前の姿")
        // 島のふちの出発点どうしは 遠すぎる(反対がわは 340 m. スナイパーでも 300 m まで)ので,
        // 全員が 島のまん中の近く(半径 15 m の円)に集まってから, slot 3 の人が 15 人を たおす.
        let world = try loadIsland()
        func spot(_ slot: Int) -> Vec3 {
            let a = Float(slot) / 16 * 2 * .pi
            let x = 15 * cos(a), z = 15 * sin(a)
            return Vec3(x, world.terrainHeight(x: x, z: z), z)
        }
        c.snapshotFor = { c, i in
            guard let slot = c.sessions[i].mySlot, c.sessions[i].match.participant(slot)?.alive == true else { return nil }
            var st = PlayerState(position: spot(slot))
            st.isGrounded = true
            return LocalSnapshot(player: st, flags: [.grounded, .alive], weapon: .sniper)
        }
        c.run(1)
        let shooter = c.sessions.indices.first { c.sessions[$0].mySlot == 3 }!
        var shot: UInt16 = 1
        for target in 0..<16 where target != 3 {
            c.send(shooter, .hitClaim(HitClaimMessage(shotId: shot, attacker: 3, target: target, weapon: .sniper, head: true,
                                                      pellets: 1, distance: (spot(3) - spot(target)).length)))
            shot += 1
            c.run(1)
        }
        c.run(2)
        XCTAssertTrue(c.sessions.allSatisfy { $0.match.phase == .finished && $0.match.matchWinner == 3 })
        XCTAssertTrue(c.replicasAgree())
        let placements = c.sessions[0].match.participants.map(\.placement).sorted()
        XCTAssertEqual(placements, Array(1...16))
    }

    func testTwelveHumansPlusFourBotsFillSixteen() throws {
        let keys = (0..<12).map { UInt64(500 + $0) }
        let c = Cluster(world: try loadIsland(), keys: keys, seed: 12)
        c.connectAll()
        c.run(3)
        c.startMatch(host: c.hostIndex!, kind: .battleRoyale, bots: 10)      // 10 体たのんでも 16 人まで
        c.run(until: { c.sessions.allSatisfy { $0.status == .inMatch } }, timeout: 5)
        let parts = c.sessions[0].match.participants
        XCTAssertEqual(parts.count, 16)
        XCTAssertEqual(parts.filter(\.isBot).count, 4)
    }
}
