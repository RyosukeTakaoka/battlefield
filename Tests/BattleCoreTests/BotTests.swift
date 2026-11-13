import XCTest
@testable import BattleCore

final class BotTests: XCTestCase {
    func testBotsMoveAndStayOnLand() throws {
        let world = try loadIsland()
        for (kind, n) in [(GameMode.Kind.roundBattle, 4), (.battleRoyale, 4), (.killRace, 3)] {
            let m = BotMatch(world: world, kind: kind, roster: BotMatch.allBots(n), seed: 3)
            m.run(until: { m.h.state.phase == .playing }, timeout: 10)
            let start = m.runner.botSlots.map { m.runner.position(of: $0)! }
            var maxTravel = [Float](repeating: 0, count: n)
            for _ in 0..<(60 * 12) {                                       // 12 秒
                m.step()
                for (i, slot) in m.runner.botSlots.enumerated() {
                    let p = m.runner.position(of: slot)!
                    XCTAssertGreaterThan(p.y, GameRules.minGroundY, "\(kind) bot \(slot) fell in the water")
                    maxTravel[i] = max(maxTravel[i], (p - start[i]).horizontal.length)
                }
            }
            XCTAssertGreaterThan(maxTravel.filter { $0 > 8 }.count, n - 1, "\(kind): the bots actually walk (\(maxTravel))")
        }
    }

    func testBotsShootEachOtherAndDealDamage() throws {
        let world = try loadIsland()
        let m = BotMatch(world: world, kind: .roundBattle, roster: BotMatch.allBots(2), seed: 5, difficulty: .hard)
        m.run(until: { m.h.state.phase == .playing }, timeout: 10)
        m.run(until: { m.h.state.participants.contains { $0.hp < 100 || $0.shield < 25 } }, timeout: 60)
        XCTAssertTrue(m.h.state.participants.contains { $0.hp < 100 || $0.shield < 25 }, "the two bots met and one hit the other")
        XCTAssertGreaterThan(m.hits, 0)
    }

    func testBotFightsAHumanWhoStandsStill() throws {
        let world = try loadIsland()
        var roster = BotMatch.allBots(2)
        roster[0] = RosterEntry(slot: 0, peerKey: 11, name: "人", isBot: false)
        let m = BotMatch(world: world, kind: .roundBattle, roster: roster, seed: 8, difficulty: .hard)
        let spawn = m.h.state.participant(0)!.spawn
        m.humans = [0: spawn]
        m.h.host.observe(slot: 0, position: spawn, weapon: .handgun)
        m.run(until: { m.h.state.phase == .playing }, timeout: 10)
        m.run(until: { !m.h.alive(0) || m.h.state.phase != .playing }, timeout: 60)
        XCTAssertTrue(m.h.hp(0) < 100 || m.h.shield(0) < 25 || !m.h.alive(0), "the bot found the human and shot them")
    }

    func testBotLoadoutFollowsTheRoundBattleSet() throws {
        let world = try loadIsland()
        let m = BotMatch(world: world, kind: .roundBattle, roster: BotMatch.allBots(2), seed: 6)
        m.run(until: { m.h.state.phase == .playing }, timeout: 10)
        let want = GameMode.weapons(forSet: m.h.state.loadoutSet)
        for slot in m.runner.botSlots {
            XCTAssertEqual(m.runner.loadout(of: slot)?.current, want[0])
        }
    }

    func testBotsFinishABattleRoyaleAndARoundBattle() throws {
        let world = try loadIsland()
        let started = Date()
        for (seed, kind, n) in [(UInt64(1), GameMode.Kind.battleRoyale, 3), (2, .battleRoyale, 4), (3, .roundBattle, 2), (4, .roundBattle, 3)] {
            let m = BotMatch(world: world, kind: kind, roster: BotMatch.allBots(n), seed: seed)
            m.run(until: { m.h.state.phase == .finished }, timeout: 60 * 40)
            XCTAssertEqual(m.h.state.phase, .finished, "\(kind) \(n) bots seed \(seed): reached \(m.h.state.round) at \(m.h.now - 100)s")
            XCTAssertLessThanOrEqual(m.h.state.round, 12)
            if kind == .roundBattle {
                XCTAssertGreaterThanOrEqual(m.h.state.participants.map(\.score).max() ?? 0, 1)
            }
        }
        print("BOT finish time \(Date().timeIntervalSince(started))")
    }

    func testSameSeedSameBotMatch() throws {
        let world = try loadIsland()
        var logs: [[Message]] = []
        for _ in 0..<2 {
            let m = BotMatch(world: world, kind: .battleRoyale, roster: BotMatch.allBots(3), seed: 77)
            m.run(60)
            logs.append(m.h.messages)
        }
        XCTAssertEqual(logs[0], logs[1])
    }

    /// ボット 4 体だけのラウンド戦が, 12 ラウンド以内に かならず終わる. 回数は環境変数 BOT_STRESS(ふだんは 15 回. 100 回で確かめた).
    func testFourBotRoundBattlesAlwaysFinish() throws {
        let world = try loadIsland()
        let count = Int(ProcessInfo.processInfo.environment["BOT_STRESS"] ?? "") ?? 15
        var rounds: [Int] = []
        var unfinished: [UInt64] = []
        for seed in 1...UInt64(count) {
            let m = BotMatch(world: world, kind: .roundBattle, roster: BotMatch.allBots(4), seed: seed * 7 + 1)
            m.run(until: { m.h.state.phase == .finished }, timeout: 60 * 60)
            if m.h.state.phase != .finished { unfinished.append(seed) }
            rounds.append(m.h.state.round + 1)
        }
        XCTAssertTrue(unfinished.isEmpty, "unfinished seeds: \(unfinished)")
        XCTAssertLessThanOrEqual(rounds.max() ?? 0, 13, "rounds: \(rounds)")
        print("BOT stress \(count): rounds avg \(Double(rounds.reduce(0, +)) / Double(rounds.count)) max \(rounds.max() ?? 0)")
    }
}
