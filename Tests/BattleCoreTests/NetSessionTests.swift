import XCTest
@testable import BattleCore

final class NetSessionTests: XCTestCase {
    func makeCluster(keys: [UInt64] = [50, 10, 70, 30], skew: [Double]? = nil, seed: UInt64 = 5) throws -> Cluster {
        let c = Cluster(world: try loadIsland(), keys: keys, skew: skew ?? keys.indices.map { Double($0) * 37.3 }, seed: seed)
        c.connectAll()
        return c
    }

    // MARK: つながる・ホスト

    func testEveryoneChoosesTheSameHost() throws {
        let c = try makeCluster()
        c.run(1)
        XCTAssertTrue(c.sessions.allSatisfy { $0.status == .lobby })
        XCTAssertTrue(c.sessions.allSatisfy { $0.hostKey == 10 })
        XCTAssertEqual(c.sessions.filter { $0.isHost }.count, 1)
        XCTAssertTrue(c.sessions[1].isHost)
        XCTAssertEqual(c.sessions[0].lobbyPlayers.map(\.peerKey), [10, 30, 50, 70])
        XCTAssertEqual(c.sessions[0].lobbyPlayers.filter(\.isHost).count, 1)
        XCTAssertEqual(c.sessions[2].lobbyPlayers.filter(\.isMe).map(\.peerKey), [70])
        XCTAssertEqual(c.sessions[3].humanCount, 4)
    }

    func testVersionMismatchIsDetected() throws {
        let world = try loadIsland()
        var s = NetSession(world: world, myKey: 1, name: "a")
        _ = s.begin(peers: [7], now: 0)
        let hello = MessageCodec.encode(.hello(HelloMessage(protocolVersion: MessageCodec.protocolVersion &+ 1, peerKey: 2, name: "b")))
        _ = s.receive(hello, from: 7, now: 0)
        XCTAssertEqual(s.status, .versionMismatch)
        XCTAssertTrue(s.startMatch(now: 1).isEmpty)
    }

    func testOnlyTheHostCanStartAMatch() throws {
        let c = try makeCluster()
        c.run(1)
        XCTAssertTrue(c.sessions[0].startMatch(now: c.local(0)).isEmpty, "not the host")
        XCTAssertTrue(c.sessions[2].startMatch(now: c.local(2)).isEmpty)
        var solo = NetSession(world: try loadIsland(), myKey: 5, name: "solo")
        _ = solo.begin(peers: [], now: 0)
        XCTAssertEqual(solo.status, .lobby)
        XCTAssertTrue(solo.isHost)
        XCTAssertTrue(solo.startMatch(now: 1).isEmpty, "one human and no bots: nobody to play against")
    }

    // MARK: 時計と同時スタート

    func testClocksAgreeAndTheMatchStartsAtTheSameMoment() throws {
        let c = try makeCluster(skew: [0, 1000, 250.5, 37.2])      // 端末ごとに 時計が大きくずれている
        c.run(3)
        c.startMatch(host: 1, kind: .roundBattle)
        c.run(until: { c.sessions.allSatisfy { $0.status == .inMatch } }, timeout: 3)
        XCTAssertTrue(c.sessions.allSatisfy { $0.status == .inMatch })
        let startAt = c.sessions[1].match.startAt
        XCTAssertTrue(c.sessions.allSatisfy { $0.match.startAt == startAt })
        // 本当の時間 startAt に ずっと近づけた時点で, どの端末の「ホストの時計」も ほぼ同じ(±50 ms).
        c.run(1)
        let hostClock = c.sessions[1].hostNow(local: c.local(1))
        for i in c.sessions.indices {
            XCTAssertEqual(c.sessions[i].hostNow(local: c.local(i)), hostClock, accuracy: 0.05, "session \(i)")
        }
        // 戦い始めの瞬間: 本当の時間が同じとき, 全員が .playing になる.
        c.run(until: { c.sessions.allSatisfy { $0.match.phase == .playing } }, timeout: 8)
        XCTAssertTrue(c.sessions.allSatisfy { $0.match.phase == .playing })
        XCTAssertEqual(c.sessions[1].hostNow(local: c.local(1)), startAt, accuracy: 0.1)
    }

    func testSlotsAreAssignedByPeerKeyAndEveryoneKnowsTheirOwn() throws {
        let c = try makeCluster()
        c.run(2)
        c.startMatch(host: 1, kind: .roundBattle)
        c.run(until: { c.sessions.allSatisfy { $0.status == .inMatch } }, timeout: 3)
        XCTAssertEqual(c.sessions.map(\.mySlot), [2, 0, 3, 1])           // keys [50, 10, 70, 30] → 小さい順
        XCTAssertEqual(c.sessions[0].match.participants.map(\.name), ["P10", "P30", "P50", "P70"])
        XCTAssertTrue(c.replicasAgree())
    }

    // MARK: 試合を最後まで

    func testRoundBattleToTheEndOnFourDevices() throws {
        let c = try makeCluster(seed: 8)
        c.run(2)
        c.startMatch(host: 1, kind: .roundBattle)
        c.run(until: { c.sessions.allSatisfy { $0.match.phase == .playing } }, timeout: 10)
        var shot: UInt16 = 1
        // slot 1(P30 の端末)が 3 ラウンド取る.
        for round in 0..<3 {
            c.run(until: { c.sessions.allSatisfy { $0.match.phase == .playing && $0.match.round == round } }, timeout: 15)
            XCTAssertEqual(c.sessions[3].match.round, round)
            c.win(slot: 1, shotId: &shot)
            c.run(1)
            XCTAssertEqual(c.sessions[0].match.roundWinner, 1, "round \(round)")
            XCTAssertEqual(c.sessions[2].match.participant(1)?.score, round + 1)
        }
        c.run(1)
        for s in c.sessions {
            XCTAssertEqual(s.match.phase, .finished)
            XCTAssertEqual(s.match.matchWinner, 1)
        }
        XCTAssertTrue(c.replicasAgree())
        XCTAssertEqual(c.sessions[0].match.participants.map(\.score), [0, 3, 0, 0])
        XCTAssertEqual(c.sessions[0].match.participants[1].kills, 9)
        // 武器の組は ラウンドごとに全員同じ(1 つの数字を配る).
        let events = c.sessions.map { $0.match.loadoutSet }
        XCTAssertEqual(Set(events).count, 1)
    }

    func testRematchStartsFresh() throws {
        let c = try makeCluster(keys: [10, 20], seed: 3)
        c.run(2)
        c.startMatch(host: 0, kind: .battleRoyale)
        c.run(until: { c.sessions.allSatisfy { $0.match.phase == .playing } }, timeout: 10)
        var shot: UInt16 = 1
        c.win(slot: 0, shotId: &shot)
        c.run(1)
        XCTAssertEqual(c.sessions[1].match.phase, .finished)
        let firstId = c.sessions[1].match.matchId
        c.startMatch(host: 0, kind: .battleRoyale)                       // もう一度
        c.run(until: { c.sessions.allSatisfy { $0.match.phase == .playing && $0.match.matchId == firstId + 1 } }, timeout: 10)
        for s in c.sessions {
            XCTAssertEqual(s.match.matchId, firstId + 1)
            XCTAssertEqual(s.match.round, 0)
            XCTAssertTrue(s.match.participants.allSatisfy { $0.alive && $0.kills == 0 && $0.hp == 100 })
        }
    }

    func testMatchCompletesWhenUnreliablePacketsAreLost() throws {
        let c = try makeCluster(keys: [10, 20, 30], seed: 12)
        c.loss = 0.3
        c.run(2)
        c.startMatch(host: 0, kind: .roundBattle)
        c.run(until: { c.sessions.allSatisfy { $0.match.phase == .playing } }, timeout: 10)
        var shot: UInt16 = 1
        for round in 0..<3 {
            c.run(until: { c.sessions.allSatisfy { $0.match.phase == .playing && $0.match.round == round } }, timeout: 15)
            c.win(slot: 2, shotId: &shot)
            c.run(1)
        }
        c.run(1)
        XCTAssertTrue(c.sessions.allSatisfy { $0.match.phase == .finished && $0.match.matchWinner == 2 })
        XCTAssertTrue(c.replicasAgree())
        XCTAssertGreaterThan(c.droppedUnreliable, 20, "the test really dropped packets")
    }

    func testRemotePlayersMoveSmoothlyOnScreen() throws {
        let c = try makeCluster(keys: [10, 20], seed: 14)
        // 20 の端末の人は, 一定の速さで歩く.
        var walked: Float = 0
        var walking = false
        c.snapshotFor = { c, i in
            guard let slot = c.sessions[i].mySlot, let p = c.sessions[i].match.participant(slot), p.alive else { return nil }
            var st = PlayerState(position: p.spawn + (i == 1 ? Vec3(walked, 0, 0) : .zero), yaw: 0)
            st.velocity = (i == 1 && walking) ? Vec3(4, 0, 0) : .zero
            st.isGrounded = true
            return LocalSnapshot(player: st, flags: [.grounded, .alive], weapon: .handgun)
        }
        c.run(2)
        c.startMatch(host: 0, kind: .roundBattle)
        c.run(until: { c.sessions.allSatisfy { $0.match.phase == .playing } }, timeout: 10)
        let walker = c.sessions[1].mySlot!
        c.run(1)
        walking = true
        var xs: [Float] = []
        for _ in 0..<240 {
            walked += 4 / 60
            c.step()
            if let p = c.sessions[0].remotePose(slot: walker, now: c.local(0)) { xs.append(p.position.x) }
        }
        XCTAssertGreaterThan(xs.count, 200)
        // 画面に出る相手の動きは, 戻らず・飛ばず なめらか(1 コマで 0.4 m を こえて動かない).
        var maxStep: Float = 0
        for i in 1..<xs.count {
            XCTAssertGreaterThanOrEqual(xs[i], xs[i - 1] - 1e-3, "never goes back")
            maxStep = max(maxStep, xs[i] - xs[i - 1])
        }
        XCTAssertLessThan(maxStep, 0.4)
        XCTAssertGreaterThan(xs.last! - xs.first!, 4 * 3.0 * 0.7)
    }

    // MARK: なりすましを受けつけない

    func testSpoofedHostMessagesAreIgnored() throws {
        let c = try makeCluster(keys: [10, 20, 30], seed: 20)
        c.run(2)
        c.startMatch(host: 0, kind: .roundBattle)
        c.run(until: { c.sessions.allSatisfy { $0.match.phase == .playing } }, timeout: 10)
        let before = c.sessions[2].match
        // ホストではない 20 が「30 は 0 HP」というメッセージを送ってきても, 受けつけない.
        let fake = MessageCodec.encode(.damage(DamageMessage(round: 0, target: 2, attacker: 1, weapon: .sniper, hp: 0, shield: 0,
                                                             head: true, killed: true, alive: 1)))
        _ = c.sessions[2].receive(fake, from: 1, now: c.local(2))
        XCTAssertEqual(c.sessions[2].match.participants, before.participants)
        // ほかの人の slot を名乗る playerState も 受けつけない(slot 0 のふりをして 20 が送る).
        let spoofState = MessageCodec.encode(.playerState(PlayerStateMessage(slot: 0, seq: 999, timeMs: 1, position: Vec3(1, 1, 1), yaw: 0,
                                                                            pitch: 0, velocity: .zero, flags: [.alive], weapon: .sniper)))
        _ = c.sessions[2].receive(spoofState, from: 1, now: c.local(2))
        XCTAssertNotEqual(c.sessions[2].latestPose(slot: 0)?.position, Vec3(1, 1, 1))
        // 20 が「30 が撃った」と申し出ても(attacker が送り主と違う), ホストは通さない.
        let hostHP = c.sessions[0].match.participant(2)!.hp
        let spoofClaim = MessageCodec.encode(.hitClaim(HitClaimMessage(shotId: 5, attacker: 2, target: 0, weapon: .sniper, head: true,
                                                                       pellets: 1, distance: 10)))
        c.enqueue(from: 0, c.sessions[0].receive(spoofClaim, from: 1, now: c.local(0)))
        c.run(1)
        XCTAssertEqual(c.sessions[0].match.participant(2)!.hp, hostHP)
        XCTAssertTrue(c.sessions[0].match.participant(0)!.alive)
    }

    func testGarbageDataDoesNotBreakASession() throws {
        let c = try makeCluster(keys: [10, 20], seed: 21)
        c.run(2)
        var rng = SeededRandom(seed: 5)
        for _ in 0..<2000 {
            let bytes = (0..<rng.int(below: 80)).map { _ in UInt8(truncatingIfNeeded: rng.next()) }
            c.enqueue(from: 0, c.sessions[0].receive(Data(bytes), from: 1, now: c.local(0)))
        }
        c.startMatch(host: 0, kind: .roundBattle)
        c.run(until: { c.sessions.allSatisfy { $0.match.phase == .playing } }, timeout: 10)
        XCTAssertTrue(c.sessions.allSatisfy { $0.match.phase == .playing })
    }

    // MARK: ぬけた人・ホストの引きつぎ

    func testNonHostLeavingMidMatch() throws {
        let c = try makeCluster(keys: [10, 20, 30], seed: 30)
        c.run(2)
        c.startMatch(host: 0, kind: .roundBattle)
        c.run(until: { c.sessions.allSatisfy { $0.match.phase == .playing } }, timeout: 10)
        c.kill(2)                                                       // 30 の端末が切れた
        c.run(1)
        for i in [0, 1] {
            XCTAssertTrue(c.sessions[i].match.participant(2)!.left)
            XCTAssertFalse(c.sessions[i].match.participant(2)!.alive)
            XCTAssertEqual(c.sessions[i].match.phase, .playing, "two are still fighting")
        }
        XCTAssertTrue(c.replicasAgree())
        c.kill(1)
        c.run(1)
        XCTAssertEqual(c.sessions[0].match.phase, .finished, "only the host is left → host wins")
        XCTAssertEqual(c.sessions[0].match.matchWinner, 0)
    }

    func testHostMigrationMidRoundKeepsTheMatchGoing() throws {
        let c = try makeCluster(keys: [30, 10, 20, 40], skew: [0, 500, 300, 12], seed: 31)
        c.run(3)
        c.startMatch(host: 1, kind: .roundBattle)                        // 10(index 1)がホスト
        c.run(until: { c.sessions.allSatisfy { $0.match.phase == .playing } }, timeout: 10)
        c.run(2)
        c.kill(1)                                                        // ホストが切れた
        c.run(3)
        // 残りの 3 台が, 同じ新しいホスト(peerKey 20 = index 2)をえらぶ.
        XCTAssertEqual(c.hostIndex, 2)
        for i in [0, 2, 3] {
            XCTAssertEqual(c.sessions[i].hostKey, 20)
            XCTAssertEqual(c.sessions[i].hostEpoch, 1)
        }
        XCTAssertEqual(c.sessions.indices.filter { c.alive[$0] && c.sessions[$0].isHost }.count, 1)
        XCTAssertTrue(c.sessions[0].match.participants.first { $0.peerKey == 10 }!.left, "the old host is out")
        XCTAssertEqual(c.sessions[0].match.phase, .playing)
        // 新しい時計: 新しいホストの時計に, ほかの人が合わせ直している.
        let hostClock = c.sessions[2].hostNow(local: c.local(2))
        for i in [0, 3] { XCTAssertEqual(c.sessions[i].hostNow(local: c.local(i)), hostClock, accuracy: 0.05, "session \(i)") }
        // 続きの試合: 新しいホストが円のダメージ・勝ち負け・次のラウンドを動かす.
        var shot: UInt16 = 1
        let winnerSlot = c.sessions[3].mySlot!
        c.win(slot: winnerSlot, shotId: &shot)
        c.run(1)
        XCTAssertEqual(c.sessions[0].match.roundWinner, winnerSlot)
        c.run(until: { [0, 2, 3].allSatisfy { c.sessions[$0].match.round == 1 && c.sessions[$0].match.phase == .playing } }, timeout: 15)
        XCTAssertTrue([0, 2, 3].allSatisfy { c.sessions[$0].match.round == 1 }, "the new host started the next round")
        XCTAssertTrue(c.replicasAgree())
    }

    func testHostMigrationBetweenRoundsStartsTheNextRound() throws {
        let c = try makeCluster(keys: [10, 20, 30], seed: 32)
        c.run(2)
        c.startMatch(host: 0, kind: .roundBattle)
        c.run(until: { c.sessions.allSatisfy { $0.match.phase == .playing } }, timeout: 10)
        var shot: UInt16 = 1
        c.win(slot: 1, shotId: &shot)
        c.run(0.5)
        XCTAssertEqual(c.sessions[1].match.phase, .betweenRounds)
        c.kill(0)
        c.run(until: { [1, 2].allSatisfy { c.sessions[$0].match.round == 1 } }, timeout: 15)
        XCTAssertTrue([1, 2].allSatisfy { c.sessions[$0].match.round == 1 }, "the next round still starts")
        XCTAssertEqual(c.hostIndex, 1)
    }

    func testLeaveMessageFromAClientMarksThemAsLeft() throws {
        let c = try makeCluster(keys: [10, 20, 30], seed: 33)
        c.run(2)
        c.startMatch(host: 0, kind: .roundBattle)
        c.run(until: { c.sessions.allSatisfy { $0.match.phase == .playing } }, timeout: 10)
        c.send(2, .leave(slot: c.sessions[2].mySlot!))
        c.run(1)
        for i in [0, 1] { XCTAssertTrue(c.sessions[i].match.participant(2)!.left) }
        XCTAssertTrue(c.replicasAgree([0, 1]))
    }
}
