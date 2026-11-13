import XCTest
@testable import BattleCore

final class MatchFlowTests: XCTestCase {
    // MARK: 道具

    /// 2 人を, 戦う円の中に 20 m はなして置く(円の外だと 円のダメージを受けるため).
    func placePair(_ h: MatchHarness, _ a: Int = 0, _ b: Int = 1) {
        h.place(a, h.state.arena.x, h.state.arena.z)
        h.place(b, h.state.arena.x + 20, h.state.arena.z)
    }

    /// winner が loser を 1 発でたおして, ラウンドを取る(スナイパーの頭 = 140).
    func winRound(_ h: MatchHarness, winner: Int, loser: Int, shotId: UInt16) {
        placePair(h, winner, loser)
        h.claim(from: winner, to: loser, head: true, distance: 20, shotId: shotId)
    }

    /// 2 人とも円の外へ出して, 同時にやられる(引き分け).
    func drawRound(_ h: MatchHarness) {
        h.place(0, h.state.arena.x + 300, h.state.arena.z)
        h.place(1, h.state.arena.x - 300, h.state.arena.z)
        h.advance(to: h.state.startAt + 21)
    }

    /// 次のラウンドの戦い始めまで進める.
    func nextRound(_ h: MatchHarness) {
        h.advance(to: h.now + GameMode.betweenRounds + 0.1)
        h.advance(to: h.state.startAt + 0.05)
    }

    // MARK: ラウンド戦

    func testRoundBattleFirstToThree() throws {
        let h = MatchHarness(world: try loadIsland(), seed: 11)
        h.begin(.roundBattle, players: 2)
        var sets: [Int] = [], arenas: [Circle] = []
        let winners = [1, 0, 1, 0, 1]                       // P1 が 3 点で先に勝つ
        for (r, w) in winners.enumerated() {
            XCTAssertEqual(h.state.round, r)
            XCTAssertEqual(h.state.phase, .playing)
            sets.append(h.state.loadoutSet)
            arenas.append(h.state.arena)
            winRound(h, winner: w, loser: 1 - w, shotId: UInt16(r + 1))
            XCTAssertEqual(h.state.roundWinner, w)
            XCTAssertEqual(h.state.participant(w)?.score, winners[0...r].filter { $0 == w }.count)
            if r < winners.count - 1 {
                XCTAssertEqual(h.state.phase, .betweenRounds)
                nextRound(h)
                // 新しいラウンドは, 全員が体力 100・シールド 25 で始まる.
                XCTAssertEqual(h.state.participants.map(\.hp), [100, 100])
                XCTAssertEqual(h.state.participants.map(\.shield), [25, 25])
                XCTAssertTrue(h.state.participants.allSatisfy { $0.alive })
            }
        }
        XCTAssertEqual(h.state.phase, .finished)
        XCTAssertEqual(h.state.matchWinner, 1)
        XCTAssertEqual(h.state.participants.map(\.score), [2, 3])
        XCTAssertEqual(h.state.participants.map(\.placement), [2, 1])
        XCTAssertEqual(h.state.participants.map(\.kills), [2, 3])
        // 武器の組は 1〜5 で, 続けて同じ組にならない. 場所は名所をめぐる.
        XCTAssertTrue(sets.allSatisfy { (1...5).contains($0) })
        for i in 1..<sets.count { XCTAssertNotEqual(sets[i], sets[i - 1]) }
        XCTAssertEqual(Set(arenas.map { "\($0.x),\($0.z)" }).count, 4, "5 rounds visit all 4 places (the 5th repeats the first)")
        // 終わったら 次のラウンドは始まらない.
        h.advance(to: h.now + 30)
        XCTAssertEqual(h.state.phase, .finished)
        XCTAssertEqual(h.state.round, 4)
    }

    func testEveryoneStartsWithTheSameLoadoutSet() throws {
        let h = MatchHarness(world: try loadIsland(), seed: 4)
        h.apply(h.host.beginMatch(matchId: 1, kind: .roundBattle, roster: MatchHarness.roster(4), now: 0))
        guard case .startRound(let m) = h.messages[0] else { return XCTFail() }
        XCTAssertTrue((1...5).contains(m.loadoutSet))      // 1 つの数字を全員に配る = 全員同じ組
        XCTAssertEqual(m.players.count, 4)
    }

    func testRoundLimitTwelveRoundsLeaderWins() throws {
        let h = MatchHarness(world: try loadIsland(), seed: 21)
        h.begin(.roundBattle, players: 2)
        winRound(h, winner: 0, loser: 1, shotId: 1)           // P0 が 1 点
        for _ in 1..<11 {                                      // 引き分けを 10 ラウンド
            nextRound(h)
            drawRound(h)
            XCTAssertNil(h.state.roundWinner)
            XCTAssertEqual(h.state.phase, .betweenRounds)
        }
        nextRound(h)
        XCTAssertEqual(h.state.round, 11)                      // 12 ラウンド目
        drawRound(h)
        XCTAssertEqual(h.state.phase, .finished, "after 12 rounds the one with the most points wins")
        XCTAssertEqual(h.state.matchWinner, 0)
    }

    func testRoundLimitTieKeepsPlaying() throws {
        let h = MatchHarness(world: try loadIsland(), seed: 22)
        h.begin(.roundBattle, players: 2)
        drawRound(h)
        for _ in 1..<12 {
            nextRound(h)
            drawRound(h)
        }
        XCTAssertEqual(h.state.round, 11)
        XCTAssertEqual(h.state.phase, .betweenRounds, "0 : 0 after 12 rounds → one more round")
        nextRound(h)
        XCTAssertEqual(h.state.round, 12)
        winRound(h, winner: 1, loser: 0, shotId: 77)
        XCTAssertEqual(h.state.phase, .finished)
        XCTAssertEqual(h.state.matchWinner, 1)
    }

    func testThreePlayersAndALeaverEndsTheMatch() throws {
        let h = MatchHarness(world: try loadIsland(), seed: 30)
        h.begin(.roundBattle, players: 3)
        h.place(0, 0, 0); h.place(1, 15, 0); h.place(2, 0, 15)
        h.apply(h.host.playerLeft(slot: 2, state: h.state, now: h.now))
        XCTAssertTrue(h.state.participant(2)!.left)
        XCTAssertFalse(h.alive(2))
        XCTAssertEqual(h.state.phase, .playing, "two are still fighting")
        XCTAssertTrue(h.events.contains(.playerLeft(slot: 2)))
        h.apply(h.host.playerLeft(slot: 1, state: h.state, now: h.now))
        XCTAssertEqual(h.state.phase, .finished, "only one player is left → that player wins")
        XCTAssertEqual(h.state.matchWinner, 0)
    }

    func testLeaverBetweenRoundsEndsATwoPlayerMatch() throws {
        let h = MatchHarness(world: try loadIsland(), seed: 31)
        h.begin(.roundBattle, players: 2)
        winRound(h, winner: 0, loser: 1, shotId: 1)
        XCTAssertEqual(h.state.phase, .betweenRounds)
        h.apply(h.host.playerLeft(slot: 1, state: h.state, now: h.now))
        XCTAssertEqual(h.state.phase, .finished)
        XCTAssertEqual(h.state.matchWinner, 0)
        h.advance(to: h.now + 30)
        XCTAssertEqual(h.state.phase, .finished, "no next round")
    }

    // MARK: キル勝負

    func testKillRaceRespawnInvulnerabilityAndTarget() throws {
        let h = MatchHarness(world: try loadIsland(), seed: 40)
        h.begin(.killRace, players: 2)
        XCTAssertTrue(h.state.mode.respawns)
        for k in 0..<10 {
            XCTAssertEqual(h.state.phase, .playing, "kill \(k)")
            placePair(h)
            let killedAt = h.now
            h.claim(from: 0, to: 1, head: true, distance: 20, shotId: UInt16(k + 1))
            XCTAssertEqual(h.state.participant(0)?.kills, k + 1)
            if k == 9 { break }
            XCTAssertFalse(h.alive(1))
            XCTAssertTrue(h.messages.contains { if case .respawn(let r) = $0 { return r.slot == 1 && abs(r.atTime - (killedAt + 3)) < 1e-6 } else { return false } })
            h.advance(to: killedAt + 2.9)
            XCTAssertFalse(h.alive(1), "not yet")
            h.advance(to: killedAt + 3.05)
            XCTAssertTrue(h.alive(1))
            XCTAssertEqual(h.hp(1), 100)
            XCTAssertEqual(h.shield(1), 0)
            XCTAssertTrue(h.events.contains(.respawned(slot: 1)))
            // 生き返って 2 秒は無敵.
            placePair(h)
            XCTAssertTrue(h.claim(from: 0, to: 1, head: true, distance: 20, shotId: 1000).isEmpty, "invulnerable")
            h.advance(to: killedAt + 5.1)
            XCTAssertFalse(h.state.isInvulnerable(1, at: h.now))
        }
        XCTAssertEqual(h.state.phase, .finished)
        XCTAssertEqual(h.state.matchWinner, 0)
        XCTAssertEqual(h.state.participant(0)?.kills, 10)
        XCTAssertEqual(h.state.participants.map(\.placement), [1, 2])
    }

    func testKillRaceTargetForFourPlayersIsFifteen() throws {
        let h = MatchHarness(world: try loadIsland(), seed: 41)
        h.begin(.killRace, players: 4)
        XCTAssertEqual(h.state.mode.killTarget, 15)
        XCTAssertEqual(h.state.participants.count, 4)
    }

    func testKillRaceRespawnSpotIsFarFromEnemies() throws {
        let h = MatchHarness(world: try loadIsland(), seed: 42)
        h.begin(.killRace, players: 2)
        h.place(0, h.state.arena.x - 50, h.state.arena.z)            // 円の西のはし
        h.place(1, h.state.arena.x - 49, h.state.arena.z)
        let out = h.claim(from: 0, to: 1, head: true, distance: 1)
        guard let respawn = out.compactMap({ m -> RespawnMessage? in if case .respawn(let r) = m { return r } else { return nil } }).first else {
            return XCTFail("no respawn")
        }
        XCTAssertTrue(h.state.arena.contains(x: respawn.position.x, z: respawn.position.z))
        XCTAssertGreaterThan(respawn.position.x, h.state.arena.x, "respawns on the far (east) side, away from the killer")
    }

    func testKillRaceTimeLimitTieContinuesUntilNextKill() throws {
        let h = MatchHarness(world: try loadIsland(), seed: 43)
        h.begin(.killRace, players: 2)
        placePair(h)
        for t in stride(from: 10.0, through: 301, by: 10) {          // 円の中にいつづける
            h.advance(to: h.state.startAt + t)
            placePair(h)
        }
        XCTAssertEqual(h.state.phase, .playing, "tied at 0 : 0 → keep playing")
        placePair(h)
        h.claim(from: 0, to: 1, head: true, distance: 20)
        XCTAssertEqual(h.state.phase, .finished)
        XCTAssertEqual(h.state.matchWinner, 0)
    }

    func testKillRaceTimeLimitLeaderWins() throws {
        let h = MatchHarness(world: try loadIsland(), seed: 44)
        h.begin(.killRace, players: 2)
        placePair(h)
        h.claim(from: 1, to: 0, head: true, distance: 20)
        for t in stride(from: 10.0, through: 301, by: 10) {
            h.advance(to: h.state.startAt + t)
            placePair(h)
        }
        XCTAssertEqual(h.state.phase, .finished)
        XCTAssertEqual(h.state.matchWinner, 1)
    }

    func testKillRaceOutsideTheCircleHurtsWithoutShrinking() throws {
        let h = MatchHarness(world: try loadIsland(), seed: 45)
        h.begin(.killRace, players: 2)
        h.place(0, h.state.arena.x, h.state.arena.z)
        h.place(1, h.state.arena.x + 400, h.state.arena.z)
        h.advance(to: h.state.startAt + 4.5)
        XCTAssertEqual(h.hp(1), 100 - 4 * 5)
        XCTAssertEqual(h.state.zone.circle(at: 200).r, 80)
    }

    // MARK: バトルロイヤル

    func testBattleRoyaleLastOneStanding() throws {
        let h = MatchHarness(world: try loadIsland(), seed: 50)
        h.begin(.battleRoyale, players: 3)
        h.place(0, 0, 0); h.place(1, 10, 0); h.place(2, 0, 10)
        h.claim(from: 0, to: 1, head: true, distance: 10, shotId: 1)
        XCTAssertEqual(h.state.phase, .playing)
        h.now += 2
        h.claim(from: 0, to: 2, head: true, distance: 10, shotId: 2)
        XCTAssertEqual(h.state.phase, .finished)
        XCTAssertEqual(h.state.matchWinner, 0)
        XCTAssertEqual(h.state.participants.map(\.placement), [1, 3, 2])
        XCTAssertEqual(h.state.participants.map(\.kills), [2, 0, 0])
    }

    func testBattleRoyaleEndsByTheShrinkingCircle() throws {
        for n in [2, 8] {
            let h = MatchHarness(world: try loadIsland(), seed: UInt64(60 + n))
            h.begin(.battleRoyale, players: n)
            for s in 0..<n { h.place(s, h.state.arena.x, h.state.arena.z) }     // 全員が中心にいる
            h.advance(to: h.state.startAt + Double(h.state.mode.totalZoneDuration) + 15)
            XCTAssertEqual(h.state.phase, .finished, "\(n) players: the circle closes and ends the match")
            XCTAssertEqual(h.state.aliveCount, 0)
        }
    }

    // MARK: 写し(MatchState)

    func testStaleMessagesAreIgnored() throws {
        let h = MatchHarness(world: try loadIsland(), seed: 70)
        h.begin(.roundBattle, players: 2)
        let before = h.state
        _ = h.state.apply(.damage(DamageMessage(round: 5, target: 1, attacker: 0, weapon: .sniper, hp: 0, shield: 0, head: true,
                                                killed: true, alive: 1)), now: h.now)
        _ = h.state.apply(.vitals(VitalsMessage(round: 5, slot: 0, hp: 1, shield: 1)), now: h.now)
        _ = h.state.apply(.lootTaken(LootTakenMessage(round: 5, lootId: 0, slot: 0)), now: h.now)
        XCTAssertEqual(h.state, before)
    }

    func testSnapshotResyncsAMissedMessage() throws {
        let h = MatchHarness(world: try loadIsland(), seed: 71)
        h.begin(.roundBattle, players: 2)
        // 別の端末(写し)が damage を取りこぼしたあと, スナップショットで追いつく.
        var other = h.state
        h.place(0, 0, 0); h.place(1, 20, 0)
        h.claim(from: 0, to: 1, head: false, distance: 20)
        let snap = h.host.makeSnapshot(h.state)
        XCTAssertNotEqual(other.participants[1].shield, h.state.participants[1].shield)
        _ = other.apply(.hostSnapshot(snap), now: h.now)
        XCTAssertEqual(other.participants.map(\.hp), h.state.participants.map(\.hp))
        XCTAssertEqual(other.participants.map(\.shield), h.state.participants.map(\.shield))
    }

    func testTwoReplicasStayIdentical() throws {
        // ホストが出したメッセージを 2 つの写しに同じ順で当てると, 全く同じ状態になる.
        let h = MatchHarness(world: try loadIsland(), seed: 72)
        var replica = MatchState()
        h.apply(h.host.beginMatch(matchId: 1, kind: .roundBattle, roster: MatchHarness.roster(3), now: h.now))
        h.advance(to: h.state.startAt + 0.05)
        h.place(0, 0, 0); h.place(1, 20, 0); h.place(2, 0, 20)
        h.claim(from: 0, to: 1, head: true, distance: 20, shotId: 1)
        h.advance(to: h.now + 3)
        h.claim(from: 0, to: 2, head: true, distance: 20, shotId: 2)
        h.advance(to: h.now + 6)
        for m in h.messages { _ = replica.apply(m, now: h.now) }
        _ = replica.advance(now: h.now)
        XCTAssertEqual(replica, h.state)
    }
}
