import XCTest
@testable import BattleCore

final class MessagesTests: XCTestCase {
    func roundTrip(_ m: Message, file: StaticString = #filePath, line: UInt = #line) -> Message? {
        let data = MessageCodec.encode(m)
        let back = MessageCodec.decode(data)
        XCTAssertNotNil(back, "decode failed", file: file, line: line)
        // もう一度書いても同じバイト列(量子化したあとは安定).
        if let back { XCTAssertEqual(MessageCodec.encode(back), data, file: file, line: line) }
        return back
    }

    func sampleMessages() -> [Message] {
        let players = [PlayerSlotInfo(slot: 0, peerKey: 0xDEAD_BEEF_0123_4567, isBot: false, score: 2, spawn: Vec3(12.34, 5.5, -80.25),
                                      spawnYaw: 0, name: "たろう"),
                       PlayerSlotInfo(slot: 1, peerKey: 0, isBot: true, score: 0, spawn: Vec3(-100, 7.75, 3), spawnYaw: 0, name: "ボット1")]
        return [
            .hello(HelloMessage(protocolVersion: 1, peerKey: 0x0123_4567_89AB_CDEF, name: "Ryosuke")),
            .startRound(StartRoundMessage(matchId: 4_000_000_000, round: 3, mode: .battleRoyale, mapId: 0, startAt: 105.05,
                                          arena: Circle(x: -80, z: 40.5, r: 60), loadoutSet: 4, players: players,
                                          zones: [Circle(x: -70, z: 30, r: 34.2), Circle(x: -70, z: 30, r: 0)],
                                          loot: [LootSpawn(id: 0, kind: .shield), LootSpawn(id: 43, kind: .sniper)])),
            .playerState(PlayerStateMessage(slot: 3, seq: 65535, timeMs: 123_456, position: Vec3(1.23, 4.56, -7.89), yaw: 0, pitch: 0,
                                            velocity: Vec3(6, -2.5, 0), flags: [.grounded, .firing, .alive], weapon: .shotgun)),
            .shotFx(ShotFxMessage(slot: 2, weapon: .shotgun, origin: Vec3(1, 2, 3),
                                  shots: (0..<8).map { .init(end: Vec3(Float($0), 1.5, -20), hitKind: UInt8($0 % 4)) })),
            .ping(clientMs: 4_294_967_295),
            .pong(clientMs: 77, hostMs: 123_456_789),
            .hitClaim(HitClaimMessage(shotId: 65000, attacker: 1, target: 2, weapon: .sniper, head: true, pellets: 1, distance: 123.4)),
            .damage(DamageMessage(round: 2, target: 1, attacker: 255, weapon: nil, hp: 37, shield: 0, head: false, killed: false, alive: 3)),
            .damage(DamageMessage(round: 2, target: 1, attacker: 0, weapon: .assaultRifle, hp: 0, shield: 0, head: true, killed: true, alive: 2)),
            .vitals(VitalsMessage(round: 1, slot: 4, hp: 100, shield: 50)),
            .respawn(RespawnMessage(round: 0, slot: 2, position: Vec3(10.5, 3, -4.25), yaw: 0, atTime: 250.75)),
            .pickupRequest(PickupRequestMessage(lootId: 42, slot: 1)),
            .lootTaken(LootTakenMessage(round: 5, lootId: 7, slot: 3)),
            .lootRestored(LootRestoredMessage(round: 5, lootId: 7, kind: .medkit)),
            .roundEnd(RoundEndMessage(matchId: 9, round: 4, winner: nil, final: true,
                                      results: [.init(placement: 2, kills: 3, score: 1), .init(placement: 1, kills: 5, score: 3)])),
            .roundEnd(RoundEndMessage(matchId: 9, round: 4, winner: 1, final: false, results: [.init(placement: 1, kills: 0, score: 0)])),
            .hostSnapshot(HostSnapshotMessage(matchId: 1, round: 2, hostEpoch: 3, phase: .playing,
                                              players: [.init(hp: 90, shield: 10, kills: 2, placement: 0, score: 1)],
                                              lootTaken: [true, false, true, true, false, false, false, true, true, false])),
            .leave(slot: 5),
        ]
    }

    func testEveryMessageRoundTrips() {
        for m in sampleMessages() {
            let back = roundTrip(m)
            XCTAssertEqual(back, m, "\(m)")
        }
    }

    func testPlayerStateIs22Bytes() {
        let m = sampleMessages().first { if case .playerState = $0 { return true } else { return false } }!
        XCTAssertEqual(MessageCodec.encode(m).count, 22)
    }

    func testAnglesVelocityAndPositionPrecision() throws {
        var m = PlayerStateMessage(slot: 1, seq: 7, timeMs: 5, position: Vec3(123.456, -7.891, 250.004), yaw: 5.0, pitch: -1.2,
                                   velocity: Vec3(5.9, -12.3, 0.1), flags: [.alive], weapon: .handgun)
        guard case .playerState(let b)? = MessageCodec.decode(MessageCodec.encode(.playerState(m))) else { return XCTFail() }
        XCTAssertEqual(b.position.x, m.position.x, accuracy: 0.006)
        XCTAssertEqual(b.position.y, m.position.y, accuracy: 0.006)
        XCTAssertEqual(b.position.z, m.position.z, accuracy: 0.006)
        XCTAssertEqual(b.yaw, 5.0, accuracy: 0.0002)
        XCTAssertEqual(b.pitch, -1.2, accuracy: 0.013)
        XCTAssertEqual(b.velocity.x, 5.9, accuracy: 0.13)
        // 負の向き(-1 rad)も 0〜2π の中へ.
        m.yaw = -1
        guard case .playerState(let c)? = MessageCodec.decode(MessageCodec.encode(.playerState(m))) else { return XCTFail() }
        XCTAssertEqual(c.yaw, 2 * .pi - 1, accuracy: 0.0002)
        // 範囲の外はふちに止める(落ちない).
        m.position = Vec3(900, -900, 0)
        guard case .playerState(let d)? = MessageCodec.decode(MessageCodec.encode(.playerState(m))) else { return XCTFail() }
        XCTAssertEqual(d.position.x, 327.67, accuracy: 0.01)
        XCTAssertEqual(d.position.y, -327.68, accuracy: 0.01)
    }

    func testLongNamesAreCutAtACharacterBoundary() throws {
        let long = String(repeating: "あ", count: 20)            // 60 バイト
        guard case .hello(let h)? = MessageCodec.decode(MessageCodec.encode(.hello(HelloMessage(protocolVersion: 1, peerKey: 1, name: long)))) else {
            return XCTFail()
        }
        XCTAssertEqual(h.name, String(repeating: "あ", count: 8))   // 24 バイト = 8 文字
    }

    func testGarbageNeverCrashes() {
        var rng = SeededRandom(seed: 123)
        var decoded = 0
        for _ in 0..<20_000 {
            let n = rng.int(below: 120)
            var bytes = (0..<n).map { _ in UInt8(truncatingIfNeeded: rng.next()) }
            if !bytes.isEmpty, rng.nextFloat() < 0.7 {          // 種類の番号だけは本物にして, 中身をでたらめに
                bytes[0] = [0x01, 0x02, 0x10, 0x11, 0x12, 0x13, 0x20, 0x21, 0x22, 0x23, 0x30, 0x31, 0x32, 0x40, 0x41, 0x50][rng.int(below: 16)]
            }
            if MessageCodec.decode(Data(bytes)) != nil { decoded += 1 }
        }
        XCTAssertGreaterThan(decoded, 0)           // 短い種類(leave など)は偶然読めることもある
    }

    func testTruncatedAndExtendedDataAreRejected() {
        for m in sampleMessages() {
            let data = MessageCodec.encode(m)
            for cut in 0..<data.count {
                XCTAssertNil(MessageCodec.decode(data.prefix(cut)), "\(m) cut at \(cut)")
            }
            XCTAssertNil(MessageCodec.decode(data + Data([0])), "extra byte on \(m)")
        }
        XCTAssertNil(MessageCodec.decode(Data()))
        XCTAssertNil(MessageCodec.decode(Data([0xFF, 1, 2, 3])))
    }

    func testBadEnumsAreRejected() {
        var bad = MessageCodec.encode(.hitClaim(HitClaimMessage(shotId: 1, attacker: 0, target: 1, weapon: .sniper, head: false, pellets: 1, distance: 5)))
        bad[5] = 9                                          // 武器の番号が範囲の外
        XCTAssertNil(MessageCodec.decode(bad))
        var tooMany = MessageCodec.encode(.roundEnd(RoundEndMessage(matchId: 1, round: 0, winner: 0, final: false,
                                                                    results: [.init(placement: 1, kills: 0, score: 0)])))
        tooMany[8] = 200                                    // 人数が多すぎる
        XCTAssertNil(MessageCodec.decode(tooMany))
    }

    func testMessageClassification() {
        XCTAssertTrue(Message.damage(DamageMessage(round: 0, target: 0, attacker: 0, weapon: nil, hp: 0, shield: 0, head: false, killed: false, alive: 0)).isHostOnly)
        XCTAssertFalse(Message.hitClaim(HitClaimMessage(shotId: 0, attacker: 0, target: 1, weapon: .handgun, head: false, pellets: 1, distance: 1)).isHostOnly)
        XCTAssertFalse(Message.playerState(PlayerStateMessage(slot: 0, seq: 0, timeMs: 0, position: .zero, yaw: 0, pitch: 0, velocity: .zero,
                                                              flags: [], weapon: .handgun)).isReliable)
        XCTAssertTrue(Message.lootTaken(LootTakenMessage(round: 0, lootId: 0, slot: 0)).isReliable)
    }
}
