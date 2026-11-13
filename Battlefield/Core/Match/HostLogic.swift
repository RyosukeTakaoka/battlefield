import Foundation

/// 参加者の名簿 1 人ぶん(試合の始めと, ラウンドのあいだに ホストが使う).
struct RosterEntry: Equatable {
    var slot: Int
    var peerKey: UInt64
    var name: String
    var isBot: Bool
    var score = 0
}

/// ホスト(参加者の 1 人で, サーバーの代わり)だけが動かす部分. ダメージ・ひろうもの・円・ラウンドの勝ち負けを決める.
///
/// 使い方: メッセージが届いたら `handle`, 毎コマ `tick` を呼ぶ. 返ってきたメッセージは
/// **自分の `MatchState` にも同じ `apply` で反映し**, 全員へ送る(道を 1 本にする).
/// この型は試合の状態を持たず(渡された `state` を読むだけ), ホストだけの記憶(最後に確かめた位置・申し出の時刻など)を持つ.
struct HostLogic {
    let world: ArenaWorld
    var rng: SeededRandom
    /// ホストが替わるたびに 1 増える.
    var hostEpoch = 0

    /// ホストが最後に見た, その人の位置と武器(`playerState` から).
    struct Observed: Equatable {
        var position: Vec3
        var weapon: WeaponKind
        var lastClaim: Double = -1000
    }
    private(set) var observed: [Int: Observed] = [:]

    private var roundKey: (UInt32, Int)?
    private var zoneTick = 0
    private var nextRoundAt: Double?
    private var lootRestores: [(at: Double, id: Int)] = []
    private var respawnCandidates: [(position: Vec3, yaw: Float)] = []
    private var lastSnapshot: Double = -1000
    /// 試合の中で一度でも起きた「同じ申し出」を捨てるため: 撃った人ごとの最後の shotId.
    private var lastShotId: [Int: UInt16] = [:]

    init(world: ArenaWorld, seed: UInt64) {
        self.world = world
        rng = SeededRandom(seed: seed)
    }

    // MARK: - 状態をたどる道具

    private struct Scratch {
        var s: MatchState
        var out: [Message] = []
        let now: Double
        mutating func emit(_ m: Message) {
            out.append(m)
            _ = s.apply(m, now: now)
        }
    }

    // MARK: - 試合・ラウンドの始まり

    /// 試合を始める(ラウンド 0). 返ったメッセージを全員へ送り, 自分にも `apply` する.
    mutating func beginMatch(matchId: UInt32, kind: GameMode.Kind, roster: [RosterEntry], now: Double) -> [Message] {
        observed = [:]
        lastShotId = [:]
        nextRoundAt = nil
        let m = makeStartRound(matchId: matchId, round: 0, kind: kind, roster: roster, previousSet: 0,
                               startAt: now + GameMode.firstCountdown)
        return [.startRound(m)]
    }

    private mutating func startNextRound(_ sc: inout Scratch) {
        let s = sc.s
        let roster = s.participants.filter { !$0.left }.map {
            RosterEntry(slot: $0.slot, peerKey: $0.peerKey, name: $0.name, isBot: $0.isBot, score: $0.score)
        }
        let m = makeStartRound(matchId: s.matchId, round: s.round + 1, kind: s.mode.kind, roster: roster,
                               previousSet: s.loadoutSet, startAt: sc.now + GameMode.laterCountdown)
        sc.emit(.startRound(m))
    }

    private mutating func makeStartRound(matchId: UInt32, round: Int, kind: GameMode.Kind, roster: [RosterEntry],
                                         previousSet: Int, startAt: Double) -> StartRoundMessage {
        let n = roster.count
        let mode = GameMode.make(kind: kind, playerCount: n)
        let map = world.map
        var arena = Circle(x: 0, z: 0, r: mode.arenaRadius)
        var spawns: [(position: Vec3, yaw: Float)] = []

        func faceCenter(_ p: Vec3, _ cx: Float, _ cz: Float) -> Float { atan2(cx - p.x, -(cz - p.z)) }

        switch kind {
        case .roundBattle, .killRace:
            if !map.pois.isEmpty {
                let poi = map.pois[(kind == .roundBattle ? round : Int(matchId) + round) % map.pois.count]
                arena = Circle(x: poi.center.x, z: poi.center.z, r: mode.arenaRadius)
            }
        case .battleRoyale:
            if !mode.islandWide { arena = chooseSmallArena(mode: mode, count: n) }
        }

        if mode.islandWide {
            // 島のふちの出発点から, 人数ぶんを同じ間かくでえらぶ.
            let all = map.spawns
            let offset = rng.int(below: max(all.count, 1))
            for i in 0..<n where !all.isEmpty {
                let sp = all[(offset + i * all.count / max(n, 1)) % all.count]
                let pos = Vec3(sp[0], world.terrainHeight(x: sp[0], z: sp[1]), sp[1])
                spawns.append((pos, faceCenter(pos, 0, 0)))
            }
        } else {
            for _ in 0..<8 {
                let offset = rng.float(in: 0...(2 * .pi))
                if let found = world.arenaSpawns(centerX: arena.x, centerZ: arena.z, radius: arena.r, count: n,
                                                 fraction: mode.spawnFraction, angleOffset: offset) {
                    spawns = found
                    break
                }
            }
            if spawns.count < n {
                // どうしても見つからないときは, 島のふちの出発点を使う(まず起きない).
                for i in 0..<n where !map.spawns.isEmpty {
                    let sp = map.spawns[(i * map.spawns.count / max(n, 1)) % map.spawns.count]
                    let pos = Vec3(sp[0], world.terrainHeight(x: sp[0], z: sp[1]), sp[1])
                    spawns.append((pos, faceCenter(pos, arena.x, arena.z)))
                }
            }
        }
        if kind == .killRace {
            respawnCandidates = world.arenaSpawns(centerX: arena.x, centerZ: arena.z, radius: arena.r, count: 8,
                                                  fraction: mode.spawnFraction) ?? spawns
        } else {
            respawnCandidates = []
        }
        spawns.shuffle(using: &rng)

        var players: [PlayerSlotInfo] = []
        for (i, r) in roster.enumerated() {
            let fallback: (position: Vec3, yaw: Float) = (Vec3(arena.x, world.terrainHeight(x: arena.x, z: arena.z), arena.z), 0)
            let sp = i < spawns.count ? spawns[i] : fallback
            players.append(PlayerSlotInfo(slot: r.slot, peerKey: r.peerKey, isBot: r.isBot, score: r.score, spawn: sp.position,
                                          spawnYaw: sp.yaw, name: r.name))
        }

        var set = 0
        if mode.sharedLoadout {
            repeat { set = 1 + rng.int(below: GameMode.roundBattleSets.count) } while set == previousSet
        }

        // 円: 段階ごとの終わりの円(いまの円の中の, 陸の上).
        var zones: [Circle] = []
        var prev = arena
        for st in mode.stages {
            let r = arena.r * st.endFraction
            let c = pickZoneCenter(inside: prev, radius: r, onLand: !mode.stages.isEmpty)
            let end = Circle(x: c.0, z: c.1, r: r)
            zones.append(end)
            prev = end
        }

        // ひろうもの: 円の中の置き場だけ.
        var loot: [LootSpawn] = []
        for (id, p) in map.loot.enumerated() where p.count >= 3 {
            let inside = mode.islandWide || arena.contains(x: p[0], z: p[2])
            if inside { loot.append(LootSpawn(id: id, kind: LootTable.roll(rng: &rng, withWeapons: mode.lootHasWeapons))) }
        }

        return StartRoundMessage(matchId: matchId, round: round, mode: kind, mapId: 0, startAt: startAt, arena: arena,
                                 loadoutSet: set, players: players, zones: zones, loot: loot)
    }

    /// バトルロイヤル(小)の始めの円: 島の中に おさまり, 置き場と出発点が足りる場所.
    private mutating func chooseSmallArena(mode: GameMode, count: Int) -> Circle {
        let r = mode.arenaRadius
        let maxDist = max(0, 188 - r)
        var best = Circle(x: 0, z: 0, r: r)
        for _ in 0..<60 {
            let a = rng.float(in: 0...(2 * .pi))
            let d = maxDist * rng.nextFloat().squareRoot()
            let c = Circle(x: d * cos(a), z: d * sin(a), r: r)
            let lootCount = world.map.loot.filter { $0.count >= 3 && c.contains(x: $0[0], z: $0[2]) }.count
            guard lootCount >= mode.minLootInArena else { continue }
            if world.arenaSpawns(centerX: c.x, centerZ: c.z, radius: r, count: count, fraction: mode.spawnFraction) != nil {
                return c
            }
            best = c
        }
        return best
    }

    private mutating func pickZoneCenter(inside prev: Circle, radius: Float, onLand: Bool) -> (Float, Float) {
        let room = max(prev.r - radius, 0) * 0.85
        for _ in 0..<30 {
            let a = rng.float(in: 0...(2 * .pi))
            let d = room * rng.nextFloat().squareRoot()
            let x = prev.x + d * cos(a), z = prev.z + d * sin(a)
            if !onLand || world.terrainHeight(x: x, z: z) > 1.5 { return (x, z) }
        }
        return (prev.x, prev.z)
    }

    // MARK: - 届いたメッセージ

    /// `sender` は そのメッセージを送ってきた人の slot(ボットはホストが自分で出すので, ホストの slot ではなくボットの slot を渡す).
    mutating func handle(_ message: Message, sender: Int, state: MatchState, now: Double) -> [Message] {
        var sc = Scratch(s: state, now: now)
        _ = sc.s.advance(now: now)
        switch message {
        case .playerState(let m):
            guard m.slot == sender else { return [] }
            var o = observed[m.slot] ?? Observed(position: m.position, weapon: m.weapon)
            o.position = m.position
            o.weapon = m.weapon
            observed[m.slot] = o
        case .hitClaim(let c):
            guard c.attacker == sender else { return [] }
            processClaim(c, &sc)
        case .pickupRequest(let r):
            guard r.slot == sender else { return [] }
            processPickup(r, &sc)
        default:
            break
        }
        return sc.out
    }

    /// ボットなど, 通信を通らない人の位置をホストが直接知らせる.
    mutating func observe(slot: Int, position: Vec3, weapon: WeaponKind) {
        var o = observed[slot] ?? Observed(position: position, weapon: weapon)
        o.position = position
        o.weapon = weapon
        observed[slot] = o
    }

    private mutating func processClaim(_ c: HitClaimMessage, _ sc: inout Scratch) {
        let s = sc.s
        let now = sc.now
        guard s.phase == .playing, c.attacker != c.target,
              let a = s.participant(c.attacker), let t = s.participant(c.target),
              a.alive, t.alive, !a.left, !t.left,
              !s.isInvulnerable(c.target, at: now),
              var oa = observed[c.attacker], let ot = observed[c.target],
              oa.weapon == c.weapon else { return }
        // 同じ申し出が 2 回届いても 1 回だけ.
        if let last = lastShotId[c.attacker], last == c.shotId { return }
        let spec = WeaponSpec.spec(c.weapon)
        guard c.pellets >= 1, c.pellets <= spec.pellets,
              c.distance >= 0, c.distance <= spec.maxRange * 1.1,
              now - oa.lastClaim >= Double(spec.fireInterval) * 0.7 else { return }
        // ホストが知っている 2 人の距離と, 大きくずれていない.
        let known = (oa.position - ot.position).length
        guard abs(c.distance - known) <= 5 else { return }
        let per = spec.damage(distance: c.distance, head: c.head)
        guard per > 0 else { return }
        oa.lastClaim = now
        observed[c.attacker] = oa
        lastShotId[c.attacker] = c.shotId
        applyDamage(&sc, target: c.target, attacker: c.attacker, weapon: c.weapon, amount: per * c.pellets, head: c.head,
                    isZone: false)
    }

    private mutating func processPickup(_ r: PickupRequestMessage, _ sc: inout Scratch) {
        let s = sc.s
        guard s.phase == .playing, let p = s.participant(r.slot), p.alive, !p.left,
              let item = s.lootItem(id: r.lootId), !item.taken,
              r.lootId >= 0, r.lootId < world.map.loot.count,
              let pos = observed[r.slot]?.position else { return }
        let spot = vec(world.map.loot[r.lootId])
        guard (spot - pos).length <= LootKind.hostPickupRange else { return }
        switch item.kind {
        case .shield: guard p.shield < GameRules.maxShield else { return }
        case .medkit: guard p.hp < GameRules.maxHP else { return }
        default: break
        }
        sc.emit(.lootTaken(LootTakenMessage(round: s.round, lootId: r.lootId, slot: r.slot)))
        switch item.kind {
        case .shield:
            sc.emit(.vitals(VitalsMessage(round: s.round, slot: r.slot, hp: p.hp,
                                          shield: min(p.shield + LootKind.shieldAmount, GameRules.maxShield))))
        case .medkit:
            sc.emit(.vitals(VitalsMessage(round: s.round, slot: r.slot, hp: min(p.hp + LootKind.medkitAmount, GameRules.maxHP),
                                          shield: p.shield)))
        default: break
        }
        if let delay = s.mode.lootRespawnDelay { lootRestores.append((sc.now + delay, r.lootId)) }
    }

    // MARK: - ダメージ・終わり

    /// `evaluate` が false のときは, 終わりの判定をしない(円のダメージを全員に与えてから, まとめて判定するため).
    private mutating func applyDamage(_ sc: inout Scratch, target: Int, attacker: Int, weapon: WeaponKind?, amount: Int,
                                      head: Bool, isZone: Bool, evaluate: Bool = true) {
        guard let t = sc.s.participant(target), t.alive, !t.left else { return }
        var shield = t.shield, hp = t.hp
        if isZone {
            hp -= amount
        } else {
            let absorbed = min(shield, amount)
            shield -= absorbed
            hp -= amount - absorbed
        }
        hp = max(hp, 0)
        let killed = hp == 0
        let aliveAfter = sc.s.aliveCount - (killed ? 1 : 0)
        sc.emit(.damage(DamageMessage(round: sc.s.round, target: target, attacker: attacker, weapon: weapon, hp: hp,
                                      shield: shield, head: head, killed: killed, alive: aliveAfter)))
        if killed {
            if sc.s.mode.respawns, sc.s.phase == .playing {
                let spot = pickRespawn(sc.s, forSlot: target)
                sc.emit(.respawn(RespawnMessage(round: sc.s.round, slot: target, position: spot.position, yaw: spot.yaw,
                                                atTime: sc.now + sc.s.mode.respawnDelay)))
            }
            if evaluate { evaluateEnd(&sc) }
        }
    }

    /// キル勝負の復活場所: 生きている敵からいちばん遠い候補.
    private func pickRespawn(_ s: MatchState, forSlot slot: Int) -> (position: Vec3, yaw: Float) {
        let enemies = s.participants.filter { $0.slot != slot && $0.alive && !$0.left }.compactMap { observed[$0.slot]?.position }
        let candidates = respawnCandidates.isEmpty ? [(s.participant(slot)?.spawn ?? .zero, Float(0))] : respawnCandidates
        var best = candidates[0]
        var bestScore: Float = -1
        for c in candidates {
            let d = enemies.map { ($0 - c.position).length }.min() ?? 1000
            if d > bestScore { bestScore = d; best = c }
        }
        return (best.position, best.yaw)
    }

    /// ラウンド(または試合)の終わりを見る.
    private mutating func evaluateEnd(_ sc: inout Scratch) {
        guard sc.s.phase == .playing else { return }
        let s = sc.s
        switch s.mode.kind {
        case .roundBattle, .battleRoyale:
            if s.aliveCount <= 1 {
                finishRound(&sc, winner: s.participants.first { $0.alive && !$0.left }?.slot)
            }
        case .killRace:
            if let top = s.participants.max(by: { $0.kills < $1.kills }), top.kills >= s.mode.killTarget {
                finishRound(&sc, winner: top.slot)
            } else if let limit = s.mode.timeLimit, Double(s.matchTime(at: sc.now)) >= limit {
                let maxKills = s.participants.map(\.kills).max() ?? 0
                let leaders = s.participants.filter { $0.kills == maxKills && !$0.left }
                if leaders.count == 1 { finishRound(&sc, winner: leaders[0].slot) }     // 同点なら次の 1 キルまで続ける
            }
        }
    }

    private mutating func finishRound(_ sc: inout Scratch, winner: Int?) {
        let s = sc.s
        var scores = s.participants.map(\.score)
        if s.mode.kind == .roundBattle, let w = winner, let i = s.participants.firstIndex(where: { $0.slot == w }) {
            scores[i] += 1
        }
        var final: Bool
        switch s.mode.kind {
        case .roundBattle:
            final = (scores.max() ?? 0) >= s.mode.winScore
            if !final && s.round + 1 >= s.mode.maxRounds {
                let top = scores.max() ?? 0
                final = scores.filter { $0 == top }.count == 1       // 同点なら もう 1 ラウンド
            }
        default:
            final = true
        }
        if s.activeCount <= 1 { final = true }
        // 順位: 終わった試合は 点(キル)の多い順, ラウンドの途中は そのラウンドの順位.
        var placements = s.participants.map(\.placement)
        if let w = winner, let i = s.participants.firstIndex(where: { $0.slot == w }), s.mode.kind != .killRace {
            placements[i] = 1
        }
        if final && s.mode.kind != .battleRoyale {
            let keys = s.participants.enumerated().map { (i: $0.offset, score: scores[$0.offset], kills: $0.element.kills) }
            let ranked = keys.sorted { ($0.score, $0.kills, -$0.i) > ($1.score, $1.kills, -$1.i) }
            for (rank, k) in ranked.enumerated() { placements[k.i] = rank + 1 }
        }
        let results = s.participants.enumerated().map {
            RoundEndMessage.Result(placement: placements[$0.offset], kills: $0.element.kills, score: scores[$0.offset])
        }
        sc.emit(.roundEnd(RoundEndMessage(matchId: s.matchId, round: s.round, winner: winner, final: final, results: results)))
        nextRoundAt = final ? nil : sc.now + GameMode.betweenRounds
    }

    // MARK: - 時間で進むこと

    mutating func tick(state: MatchState, now: Double) -> [Message] {
        var sc = Scratch(s: state, now: now)
        _ = sc.s.advance(now: now)

        if sc.s.phase == .betweenRounds, let at = nextRoundAt, now >= at {
            nextRoundAt = nil
            startNextRound(&sc)
            return sc.out
        }
        guard sc.s.phase == .playing else { return sc.out }

        let key = (sc.s.matchId, sc.s.round)
        if roundKey == nil || roundKey! != key {
            roundKey = key
            zoneTick = 0
            lootRestores = []
            lastShotId = [:]
        }
        let t = sc.s.matchTime(at: now)

        // 1 秒ごとの円のダメージ.
        while Float(zoneTick + 1) <= t, sc.s.phase == .playing {
            zoneTick += 1
            let at = Float(zoneTick)
            let dps = sc.s.zone.dps(at: at)
            guard dps > 0 else { continue }
            for p in sc.s.participants where p.alive && !p.left {
                let pos = observed[p.slot]?.position ?? p.spawn
                if sc.s.zone.isOutside(x: pos.x, z: pos.z, at: at) {
                    applyDamage(&sc, target: p.slot, attacker: DamageMessage.zoneAttacker, weapon: nil, amount: dps, head: false,
                                isZone: true, evaluate: false)
                }
            }
            evaluateEnd(&sc)            // 同じ瞬間にやられた人が 2 人いても, 全員に当ててから勝ち負けを決める
        }

        // ひろった物が また出る.
        if sc.s.phase == .playing {
            let due = lootRestores.filter { $0.at <= now }
            lootRestores.removeAll { $0.at <= now }
            for d in due {
                guard let item = sc.s.lootItem(id: d.id) else { continue }
                let kind = LootTable.roll(rng: &rng, withWeapons: sc.s.mode.lootHasWeapons)
                _ = item
                sc.emit(.lootRestored(LootRestoredMessage(round: sc.s.round, lootId: d.id, kind: kind)))
            }
        }

        evaluateEnd(&sc)

        if now - lastSnapshot >= 2 {
            lastSnapshot = now
            sc.emit(.hostSnapshot(makeSnapshot(sc.s)))
        }
        return sc.out
    }

    func makeSnapshot(_ s: MatchState) -> HostSnapshotMessage {
        HostSnapshotMessage(matchId: s.matchId, round: s.round, hostEpoch: hostEpoch, phase: s.phase,
                            players: s.participants.map {
                                .init(hp: $0.hp, shield: $0.shield, kills: $0.kills, placement: $0.placement, score: $0.score)
                            },
                            lootTaken: s.loot.map(\.taken))
    }

    // MARK: - ホストの引きつぎ

    /// 前のホストが切れたあと, 全員が持っている `MatchState` の写しから 新しいホストとして続ける(`docs/NETCODE.md` §8).
    mutating func adopt(state s: MatchState, epoch: Int, now: Double) {
        hostEpoch = epoch
        roundKey = (s.matchId, s.round)
        zoneTick = max(0, Int(s.matchTime(at: now)))
        lastSnapshot = -1000
        lootRestores = []
        if s.phase == .betweenRounds { nextRoundAt = now + GameMode.betweenRounds }
        if let delay = s.mode.lootRespawnDelay {
            for item in s.loot where item.taken { lootRestores.append((now + delay, item.id)) }
        }
        if s.mode.kind == .killRace {
            respawnCandidates = world.arenaSpawns(centerX: s.arena.x, centerZ: s.arena.z, radius: s.arena.r, count: 8,
                                                  fraction: s.mode.spawnFraction) ?? []
        }
    }

    // MARK: - ぬけた人

    /// だれかが切れた・ぬけた. その人をやられた扱いにし, 残りが 1 人なら終わらせる.
    mutating func playerLeft(slot: Int, state: MatchState, now: Double) -> [Message] {
        var sc = Scratch(s: state, now: now)
        _ = sc.s.advance(now: now)
        guard let p = sc.s.participant(slot), !p.left else { return [] }
        if p.alive {
            let aliveAfter = sc.s.aliveCount - 1
            sc.emit(.damage(DamageMessage(round: sc.s.round, target: slot, attacker: DamageMessage.disconnectAttacker, weapon: nil,
                                          hp: 0, shield: 0, head: false, killed: true, alive: aliveAfter)))
        }
        sc.emit(.leave(slot: slot))
        if sc.s.phase == .playing {
            evaluateEnd(&sc)
        } else if (sc.s.phase == .betweenRounds || sc.s.phase == .countdown), sc.s.activeCount <= 1 {
            // 残りが 1 人: その人の勝ちで試合を終える.
            let winner = sc.s.participants.first { !$0.left }?.slot
            let results = sc.s.participants.enumerated().map {
                RoundEndMessage.Result(placement: $0.element.slot == winner ? 1 : 2, kills: $0.element.kills, score: $0.element.score)
            }
            sc.emit(.roundEnd(RoundEndMessage(matchId: sc.s.matchId, round: sc.s.round, winner: winner, final: true, results: results)))
            nextRoundAt = nil
        }
        return sc.out
    }
}
