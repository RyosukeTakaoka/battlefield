import Foundation

/// `Message` ⇔ バイト列(`docs/NETCODE.md` §4). 読めないデータ(短い・知らない種類・でたらめ)は `nil` を返して捨てる.
enum MessageCodec {
    /// 通信の版. 形を変えたら 1 増やす(版が違う人とは試合を始めない).
    static let protocolVersion: UInt8 = 1

    static let maxPlayers = 8
    static let maxShots = 16
    static let maxZones = 8
    static let maxLoot = 255

    enum Kind: UInt8 {
        case playerState = 0x01, shotFx = 0x02
        case hello = 0x10, startRound = 0x11, ping = 0x12, pong = 0x13
        case hitClaim = 0x20, damage = 0x21, vitals = 0x22, respawn = 0x23
        case pickupRequest = 0x30, lootTaken = 0x31, lootRestored = 0x32
        case roundEnd = 0x40, hostSnapshot = 0x41
        case leave = 0x50
    }

    private static let none = 255

    static func encode(_ message: Message) -> Data {
        var w = ByteWriter()
        switch message {
        case .playerState(let m):
            w.u8(Int(Kind.playerState.rawValue))
            w.u8(m.slot); w.u16(Int(m.seq)); w.u32(UInt32(truncatingIfNeeded: Int((m.timeMs))))
            w.position(m.position); w.angle(m.yaw); w.pitch(m.pitch); w.velocity(m.velocity)
            w.u8(Int(m.flags.rawValue)); w.u8(Int(m.weapon.rawValue))
        case .shotFx(let m):
            w.u8(Int(Kind.shotFx.rawValue))
            w.u8(m.slot); w.u8(Int(m.weapon.rawValue)); w.position(m.origin)
            let shots = Array(m.shots.prefix(maxShots))
            w.u8(shots.count)
            for s in shots { w.position(s.end); w.u8(Int(s.hitKind)) }
        case .hello(let m):
            w.u8(Int(Kind.hello.rawValue))
            w.u8(Int(m.protocolVersion)); w.u64(m.peerKey); w.name(m.name)
        case .startRound(let m):
            w.u8(Int(Kind.startRound.rawValue))
            w.u32(m.matchId); w.u8(m.round); w.u8(Int(m.mode.rawValue)); w.u8(m.mapId); w.time(m.startAt)
            w.circle(m.arena); w.u8(m.loadoutSet)
            w.u8(m.players.count)
            for p in m.players {
                w.u8(p.slot); w.u64(p.peerKey); w.u8(p.isBot ? 1 : 0); w.u8(p.score)
                w.position(p.spawn); w.angle(p.spawnYaw); w.name(p.name)
            }
            w.u8(m.zones.count)
            for z in m.zones { w.circle(z) }
            let loot = Array(m.loot.prefix(maxLoot))
            w.u8(loot.count)
            for l in loot { w.u8(l.id); w.u8(Int(l.kind.rawValue)) }
        case .ping(let ms):
            w.u8(Int(Kind.ping.rawValue)); w.u32(ms)
        case .pong(let c, let h):
            w.u8(Int(Kind.pong.rawValue)); w.u32(c); w.u32(h)
        case .hitClaim(let m):
            w.u8(Int(Kind.hitClaim.rawValue))
            w.u16(Int(m.shotId)); w.u8(m.attacker); w.u8(m.target); w.u8(Int(m.weapon.rawValue))
            w.u8(m.head ? 1 : 0); w.u8(m.pellets); w.distance(m.distance)
        case .damage(let m):
            w.u8(Int(Kind.damage.rawValue))
            w.u8(m.round); w.u8(m.target); w.u8(m.attacker); w.u8(m.weapon.map { Int($0.rawValue) } ?? none)
            w.u8(m.hp); w.u8(m.shield); w.u8((m.killed ? 1 : 0) | (m.head ? 2 : 0)); w.u8(m.alive)
        case .vitals(let m):
            w.u8(Int(Kind.vitals.rawValue))
            w.u8(m.round); w.u8(m.slot); w.u8(m.hp); w.u8(m.shield)
        case .respawn(let m):
            w.u8(Int(Kind.respawn.rawValue))
            w.u8(m.round); w.u8(m.slot); w.position(m.position); w.angle(m.yaw); w.time(m.atTime)
        case .pickupRequest(let m):
            w.u8(Int(Kind.pickupRequest.rawValue)); w.u8(m.lootId); w.u8(m.slot)
        case .lootTaken(let m):
            w.u8(Int(Kind.lootTaken.rawValue)); w.u8(m.round); w.u8(m.lootId); w.u8(m.slot)
        case .lootRestored(let m):
            w.u8(Int(Kind.lootRestored.rawValue)); w.u8(m.round); w.u8(m.lootId); w.u8(Int(m.kind.rawValue))
        case .roundEnd(let m):
            w.u8(Int(Kind.roundEnd.rawValue))
            w.u32(m.matchId); w.u8(m.round); w.u8(m.winner ?? none); w.u8(m.final ? 1 : 0)
            w.u8(m.results.count)
            for r in m.results { w.u8(r.placement); w.u8(r.kills); w.u8(r.score) }
        case .hostSnapshot(let m):
            w.u8(Int(Kind.hostSnapshot.rawValue))
            w.u32(m.matchId); w.u8(m.round); w.u8(m.hostEpoch); w.u8(Int(m.phase.rawValue))
            w.u8(m.players.count)
            for p in m.players { w.u8(p.hp); w.u8(p.shield); w.u8(p.kills); w.u8(p.placement); w.u8(p.score) }
            let loot = Array(m.lootTaken.prefix(maxLoot))
            w.u8(loot.count)
            var byte = 0
            for (i, t) in loot.enumerated() {
                if t { byte |= 1 << (i % 8) }
                if i % 8 == 7 { w.u8(byte); byte = 0 }
            }
            if loot.count % 8 != 0 { w.u8(byte) }
        case .leave(let slot):
            w.u8(Int(Kind.leave.rawValue)); w.u8(slot)
        }
        return w.data
    }

    static func decode(_ data: Data) -> Message? {
        var r = ByteReader(data)
        guard let kind = Kind(rawValue: UInt8(r.u8())), r.ok else { return nil }
        let message: Message?
        switch kind {
        case .playerState:
            let slot = r.u8(), seq = r.u16(), t = r.u32()
            let pos = r.position(), yaw = r.angle(), pitch = r.pitch(), vel = r.velocity()
            let flags = r.u8()
            guard let weapon = WeaponKind(rawValue: UInt8(r.u8())) else { return nil }
            message = .playerState(PlayerStateMessage(slot: slot, seq: UInt16(seq), timeMs: t, position: pos, yaw: yaw, pitch: pitch,
                                                      velocity: vel, flags: PlayerFlags(rawValue: UInt8(flags)), weapon: weapon))
        case .shotFx:
            let slot = r.u8()
            guard let weapon = WeaponKind(rawValue: UInt8(r.u8())) else { return nil }
            let origin = r.position()
            let n = r.u8()
            guard n <= maxShots else { return nil }
            var shots: [ShotFxMessage.Shot] = []
            for _ in 0..<n { shots.append(.init(end: r.position(), hitKind: UInt8(r.u8()))) }
            message = .shotFx(ShotFxMessage(slot: slot, weapon: weapon, origin: origin, shots: shots))
        case .hello:
            message = .hello(HelloMessage(protocolVersion: UInt8(r.u8()), peerKey: r.u64(), name: r.name()))
        case .startRound:
            let matchId = r.u32(), round = r.u8()
            guard let mode = GameMode.Kind(rawValue: UInt8(r.u8())) else { return nil }
            let mapId = r.u8(), startAt = r.time(), arena = r.circle(), set = r.u8()
            let n = r.u8()
            guard n <= maxPlayers else { return nil }
            var players: [PlayerSlotInfo] = []
            for _ in 0..<n {
                let slot = r.u8(), key = r.u64(), bot = r.u8() != 0, score = r.u8()
                let spawn = r.position(), yaw = r.angle(), name = r.name()
                players.append(PlayerSlotInfo(slot: slot, peerKey: key, isBot: bot, score: score, spawn: spawn, spawnYaw: yaw, name: name))
            }
            let zn = r.u8()
            guard zn <= maxZones else { return nil }
            var zones: [Circle] = []
            for _ in 0..<zn { zones.append(r.circle()) }
            let ln = r.u8()
            var loot: [LootSpawn] = []
            for _ in 0..<ln {
                let id = r.u8()
                guard let k = LootKind(rawValue: UInt8(r.u8())) else { return nil }
                loot.append(LootSpawn(id: id, kind: k))
            }
            message = .startRound(StartRoundMessage(matchId: matchId, round: round, mode: mode, mapId: mapId, startAt: startAt,
                                                    arena: arena, loadoutSet: set, players: players, zones: zones, loot: loot))
        case .ping:
            message = .ping(clientMs: r.u32())
        case .pong:
            message = .pong(clientMs: r.u32(), hostMs: r.u32())
        case .hitClaim:
            let id = r.u16(), a = r.u8(), t = r.u8()
            guard let weapon = WeaponKind(rawValue: UInt8(r.u8())) else { return nil }
            message = .hitClaim(HitClaimMessage(shotId: UInt16(id), attacker: a, target: t, weapon: weapon, head: r.u8() != 0,
                                                pellets: r.u8(), distance: r.distance()))
        case .damage:
            let round = r.u8(), target = r.u8(), attacker = r.u8(), w = r.u8()
            let weapon: WeaponKind? = w == none ? nil : WeaponKind(rawValue: UInt8(w))
            if w != none && weapon == nil { return nil }
            let hp = r.u8(), shield = r.u8(), flags = r.u8(), alive = r.u8()
            message = .damage(DamageMessage(round: round, target: target, attacker: attacker, weapon: weapon, hp: hp, shield: shield,
                                            head: flags & 2 != 0, killed: flags & 1 != 0, alive: alive))
        case .vitals:
            message = .vitals(VitalsMessage(round: r.u8(), slot: r.u8(), hp: r.u8(), shield: r.u8()))
        case .respawn:
            message = .respawn(RespawnMessage(round: r.u8(), slot: r.u8(), position: r.position(), yaw: r.angle(), atTime: r.time()))
        case .pickupRequest:
            message = .pickupRequest(PickupRequestMessage(lootId: r.u8(), slot: r.u8()))
        case .lootTaken:
            message = .lootTaken(LootTakenMessage(round: r.u8(), lootId: r.u8(), slot: r.u8()))
        case .lootRestored:
            let round = r.u8(), id = r.u8()
            guard let k = LootKind(rawValue: UInt8(r.u8())) else { return nil }
            message = .lootRestored(LootRestoredMessage(round: round, lootId: id, kind: k))
        case .roundEnd:
            let matchId = r.u32(), round = r.u8(), w = r.u8(), final = r.u8() != 0, n = r.u8()
            guard n <= maxPlayers else { return nil }
            var results: [RoundEndMessage.Result] = []
            for _ in 0..<n { results.append(.init(placement: r.u8(), kills: r.u8(), score: r.u8())) }
            message = .roundEnd(RoundEndMessage(matchId: matchId, round: round, winner: w == none ? nil : w, final: final, results: results))
        case .hostSnapshot:
            let matchId = r.u32(), round = r.u8(), epoch = r.u8()
            guard let phase = MatchPhase(rawValue: UInt8(r.u8())) else { return nil }
            let n = r.u8()
            guard n <= maxPlayers else { return nil }
            var players: [HostSnapshotMessage.Player] = []
            for _ in 0..<n { players.append(.init(hp: r.u8(), shield: r.u8(), kills: r.u8(), placement: r.u8(), score: r.u8())) }
            let ln = r.u8()
            var taken: [Bool] = []
            var byte = 0
            for i in 0..<ln {
                if i % 8 == 0 { byte = r.u8() }
                taken.append(byte & (1 << (i % 8)) != 0)
            }
            message = .hostSnapshot(HostSnapshotMessage(matchId: matchId, round: round, hostEpoch: epoch, phase: phase, players: players,
                                                        lootTaken: taken))
        case .leave:
            message = .leave(slot: r.u8())
        }
        // 長さが足りなかった・余っている(= 形が違う)ものは捨てる.
        guard r.ok, r.remaining == 0 else { return nil }
        return message
    }
}
