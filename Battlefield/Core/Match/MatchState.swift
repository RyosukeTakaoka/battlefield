import Foundation

enum MatchPhase: UInt8, Equatable {
    case lobby = 0
    case countdown = 1
    case playing = 2
    case betweenRounds = 3
    case finished = 4
}

/// 試合の参加者 1 人ぶん(全員が同じ写しを持つ).
struct Participant: Equatable {
    var slot: Int
    var name: String
    var isBot: Bool
    var peerKey: UInt64
    var hp = 100
    var shield = 0
    var alive = true
    var kills = 0
    /// 0 = 生きている. 1 = 優勝, 2 = 2 位, ….
    var placement = 0
    /// 取ったラウンドの数.
    var score = 0
    /// 試合をぬけた.
    var left = false
    var spawn: Vec3 = .zero
    var spawnYaw: Float = 0
    /// キル勝負: この時刻に生き返る.
    var respawnAt: Double?
    var invulnerableUntil: Double = 0
}

/// 試合の状態の「写し」. ホストが決めたメッセージ(`apply`)だけで変わるので, 全員が同じ状態になる.
/// 時刻はすべて「ホストの時計(秒)」.
struct MatchState: Equatable {
    var matchId: UInt32 = 0
    var round = 0
    var mode = GameMode.make(kind: .roundBattle, playerCount: 2)
    var phase: MatchPhase = .lobby
    var participants: [Participant] = []
    var loot: [LootItem] = []
    var zone = Zone.empty
    var arena = Disc(x: 0, z: 0, r: 0)
    var loadoutSet = 0
    var startAt: Double = 0
    var mapId = 0
    /// このラウンドの勝者(ラウンドが終わったら).
    var roundWinner: Int?
    /// 試合の勝者(試合が終わったら).
    var matchWinner: Int?

    /// 試合の時計(秒). カウントダウン中は負の数.
    func matchTime(at now: Double) -> Float { Float(now - startAt) }

    func participant(_ slot: Int) -> Participant? {
        participants.first { $0.slot == slot }
    }

    private func index(of slot: Int) -> Int? { participants.firstIndex { $0.slot == slot } }

    var aliveCount: Int { participants.filter { $0.alive && !$0.left }.count }
    var activeCount: Int { participants.filter { !$0.left }.count }

    func isInvulnerable(_ slot: Int, at now: Double) -> Bool {
        (participant(slot)?.invulnerableUntil ?? 0) > now
    }

    func lootItem(id: Int) -> LootItem? { loot.first { $0.id == id } }

    /// 時刻だけで進むこと: カウントダウンの終わり・生き返り.
    mutating func advance(now: Double) -> [MatchEvent] {
        var events: [MatchEvent] = []
        if phase == .countdown && now >= startAt {
            phase = .playing
            events.append(.roundStarted)
        }
        for i in participants.indices {
            if let at = participants[i].respawnAt, now >= at, !participants[i].left {
                participants[i].respawnAt = nil
                participants[i].alive = true
                participants[i].hp = GameRules.maxHP
                participants[i].shield = mode.startShield
                participants[i].placement = 0
                participants[i].invulnerableUntil = at + mode.respawnInvulnerable
                events.append(.respawned(slot: participants[i].slot))
            }
        }
        return events
    }

    /// ホストから来たメッセージで写しを直す. 出来事を返す. ホスト以外の種類(playerState など)は無視する.
    mutating func apply(_ message: Message, now: Double) -> [MatchEvent] {
        switch message {
        case .startRound(let m): return applyStart(m)
        case .damage(let m): return applyDamage(m)
        case .vitals(let m):
            guard m.round == round, let i = index(of: m.slot) else { return [] }
            participants[i].hp = m.hp
            participants[i].shield = m.shield
            return [.vitalsChanged(slot: m.slot, hp: m.hp, shield: m.shield)]
        case .respawn(let m):
            guard m.round == round, let i = index(of: m.slot) else { return [] }
            participants[i].respawnAt = m.atTime
            participants[i].spawn = m.position
            participants[i].spawnYaw = m.yaw
            return []
        case .lootTaken(let m):
            guard m.round == round, let i = loot.firstIndex(where: { $0.id == m.lootId }) else { return [] }
            loot[i].taken = true
            return [.lootTaken(id: m.lootId, slot: m.slot, kind: loot[i].kind)]
        case .lootRestored(let m):
            guard m.round == round, let i = loot.firstIndex(where: { $0.id == m.lootId }) else { return [] }
            loot[i].taken = false
            loot[i].kind = m.kind
            return [.lootRestored(id: m.lootId, kind: m.kind)]
        case .roundEnd(let m): return applyRoundEnd(m)
        case .hostSnapshot(let m): return applySnapshot(m)
        case .leave(let slot):
            guard let i = index(of: slot), !participants[i].left else { return [] }
            participants[i].left = true
            participants[i].alive = false
            return [.playerLeft(slot: slot)]
        default:
            return []
        }
    }

    private mutating func applyStart(_ m: StartRoundMessage) -> [MatchEvent] {
        let fresh = m.round == 0 || m.matchId != matchId
        let old = participants
        participants = m.players.map { info in
            var p = Participant(slot: info.slot, name: info.name, isBot: info.isBot, peerKey: info.peerKey)
            if !fresh, let prev = old.first(where: { $0.slot == info.slot }) { p.kills = prev.kills }
            p.score = info.score
            p.spawn = info.spawn
            p.spawnYaw = info.spawnYaw
            return p
        }
        // 開始のメッセージにいない人は, ぬけた人.
        if !fresh {
            for prev in old where !participants.contains(where: { $0.slot == prev.slot }) {
                var p = prev
                p.left = true
                p.alive = false
                participants.append(p)
            }
            participants.sort { $0.slot < $1.slot }
        }
        matchId = m.matchId
        round = m.round
        mapId = m.mapId
        mode = GameMode.make(kind: m.mode, playerCount: m.players.count)
        for i in participants.indices where !participants[i].left {
            participants[i].shield = mode.startShield
        }
        arena = m.arena
        loadoutSet = m.loadoutSet
        startAt = m.startAt
        zone = Zone(initial: m.arena, ends: m.zones, stages: mode.stages, outsideDPS: mode.outsideDPS)
        loot = m.loot.map { LootItem(id: $0.id, kind: $0.kind) }
        phase = .countdown
        roundWinner = nil
        matchWinner = nil
        return [.roundStarting(round: m.round, startAt: m.startAt)]
    }

    private mutating func applyDamage(_ m: DamageMessage) -> [MatchEvent] {
        guard m.round == round, let i = index(of: m.target) else { return [] }
        participants[i].hp = m.hp
        participants[i].shield = m.shield
        var events: [MatchEvent] = [.damaged(target: m.target, attacker: m.attacker, weapon: m.weapon, hp: m.hp, shield: m.shield,
                                             head: m.head)]
        if m.killed && participants[i].alive {
            participants[i].alive = false
            if !mode.respawns { participants[i].placement = m.alive + 1 }
            var by: Int?
            if m.attacker != m.target, let a = index(of: m.attacker) {
                participants[a].kills += 1
                by = m.attacker
            }
            events.append(.eliminated(slot: m.target, by: by, placement: participants[i].placement))
        }
        return events
    }

    private mutating func applyRoundEnd(_ m: RoundEndMessage) -> [MatchEvent] {
        guard m.round == round else { return [] }
        for (i, r) in m.results.enumerated() where i < participants.count {
            participants[i].placement = r.placement
            participants[i].kills = r.kills
            participants[i].score = r.score
        }
        roundWinner = m.winner
        phase = m.final ? .finished : .betweenRounds
        if m.final {
            // ラウンド戦は点がいちばん多い人. ほかは そのラウンド(=試合)の勝者.
            if mode.kind == .roundBattle, let top = participants.filter({ !$0.left }).max(by: { $0.score < $1.score }),
               participants.filter({ $0.score == top.score && !$0.left }).count == 1 {
                matchWinner = top.slot
            } else {
                matchWinner = m.winner
            }
        }
        return [.roundEnded(winner: m.winner, final: m.final)]
    }

    /// 2 秒ごとの全体の写し. 取りこぼしを直す(ホストが替わった直後にも送る).
    private mutating func applySnapshot(_ m: HostSnapshotMessage) -> [MatchEvent] {
        guard m.matchId == matchId, m.round == round else { return [] }
        for (i, p) in m.players.enumerated() where i < participants.count {
            participants[i].hp = p.hp
            participants[i].shield = p.shield
            participants[i].kills = p.kills
            participants[i].score = p.score
            if !mode.respawns { participants[i].placement = p.placement }
        }
        for (i, taken) in m.lootTaken.enumerated() where i < loot.count { loot[i].taken = taken }
        return []
    }
}
