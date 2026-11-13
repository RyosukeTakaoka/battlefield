import Foundation

/// ボットの強さ(`docs/DESIGN.md` の「Bots」: 反応の遅れ・ねらいの誤差・振り向く速さ).
struct BotDifficulty: Equatable {
    var reaction: Double
    /// ねらいの誤差(度).
    var aimError: Float
    /// 振り向く速さ(ラジアン/秒).
    var turnRate: Float

    static let easy = BotDifficulty(reaction: 0.6, aimError: 7, turnRate: 3)
    static let normal = BotDifficulty(reaction: 0.35, aimError: 4, turnRate: 5)
    static let hard = BotDifficulty(reaction: 0.2, aimError: 2, turnRate: 8)
}

/// ホストが動かすボット(全員ぶん). 人と同じ `CharacterMotor`(動き)・`Hitscan`(当たり)を使う.
/// 状態は 3 つ: さがす(ひろうものへ) → すすむ(円の中心・敵へ) → たたかう(見える敵がいるとき).
///
/// 使い方: ラウンドが始まったら `reset(match:)`, 毎コマ `update` を呼ぶ. 返ったメッセージを `NetSession.submitBot` へ.
/// `observe(events:)` に, 画面と同じ出来事を渡す(武器をひろった・生き返った).
struct BotRunner {
    private struct Bot {
        var slot: Int
        var player: PlayerState
        var loadout: Loadout
        var rng: SeededRandom
        var goal: Vec3?
        var goalSetAt: Double = -100
        var lootTarget: Int?
        var enemy: Int?
        var firstSeen: Double?
        var strafeSign: Float = 1
        var strafeUntil: Double = 0
        var aimOffset = SIMD2<Float>(0, 0)
        var aimOffsetUntil: Double = 0
        var stuckSince: Double?
        var lastPos: Vec3
        var lastPosCheck: Double = 0
        var detour: (until: Double, sign: Float)?
        var triggerHeld = false
        var nextState: Double = 0
        var nextDecision: Double = 0
        var seq: UInt16 = 0
        var shotId: UInt16 = 0
        var lastShotTime: Double = -10
    }

    let world: ArenaWorld
    var difficulty: BotDifficulty
    private var bots: [Int: Bot] = [:]
    private var accumulator: Float = 0
    private var seed: UInt64
    private var lastRound: (UInt32, Int)?
    private var lastWandering: [Int: Vec3] = [:]

    init(world: ArenaWorld, difficulty: BotDifficulty = .normal, seed: UInt64 = 1) {
        self.world = world
        self.difficulty = difficulty
        self.seed = seed
    }

    var botSlots: [Int] { bots.keys.sorted() }
    func position(of slot: Int) -> Vec3? { bots[slot]?.player.position }
    func loadout(of slot: Int) -> Loadout? { bots[slot]?.loadout }

    /// ラウンドの始まり: ボットを出発点に立たせ, 武器を持たせる.
    mutating func reset(match: MatchState) {
        bots = [:]
        lastRound = (match.matchId, match.round)
        let weapons = match.mode.sharedLoadout ? GameMode.weapons(forSet: match.loadoutSet) : [.handgun, nil]
        for p in match.participants where p.isBot && !p.left {
            var st = PlayerState(position: p.spawn, yaw: p.spawnYaw)
            st.isGrounded = true
            bots[p.slot] = Bot(slot: p.slot, player: st, loadout: Loadout(weapons: weapons),
                               rng: SeededRandom(seed: seed &+ UInt64(p.slot) &* 7919 &+ UInt64(match.round) &* 104_729),
                               lastPos: p.spawn)
        }
    }

    /// 画面と同じ出来事を受けとる(武器をひろった・生き返った).
    mutating func observe(events: [MatchEvent], match: MatchState, now: Double) {
        for e in events {
            switch e {
            case .lootTaken(_, let slot, let kind):
                if var b = bots[slot], let w = kind.weapon {
                    b.loadout.pickUp(w, now: now)
                    bots[slot] = b
                }
            case .respawned(let slot):
                if var b = bots[slot], let p = match.participant(slot) {
                    b.player.position = p.spawn
                    b.player.yaw = p.spawnYaw
                    b.player.velocity = .zero
                    b.player.isGrounded = true
                    b.loadout.reset(to: [.handgun, nil])
                    b.lootTarget = nil
                    b.enemy = nil
                    bots[slot] = b
                }
            default:
                break
            }
        }
    }

    /// 毎コマ. `now` はホストの時計(秒). `humans` は人間の最新の位置(足もと). 返すのは, ホストが全員へ送るもの.
    mutating func update(now: Double, dt: Float, match: MatchState, humans: [Int: Vec3]) -> [Message] {
        // ラウンドが替わったら作り直す.
        if lastRound == nil || lastRound! != (match.matchId, match.round) { reset(match: match) }
        guard match.phase == .playing else { return [] }
        accumulator += dt
        var out: [Message] = []
        while accumulator >= GameRules.tick {
            accumulator -= GameRules.tick
            let tickNow = now - Double(accumulator)
            out += tick(now: tickNow, match: match, humans: humans)
        }
        return out
    }

    private mutating func tick(now: Double, match: MatchState, humans: [Int: Vec3]) -> [Message] {
        var out: [Message] = []
        // みんなの位置(ボットは自分たちの最新).
        var positions = humans
        for (slot, b) in bots { positions[slot] = b.player.position }
        for slot in bots.keys.sorted() {
            guard var b = bots[slot], let part = match.participant(slot), part.alive, !part.left else { continue }
            let (input, shots) = think(&b, part: part, match: match, positions: positions, now: now)
            CharacterMotor.step(&b.player, input: input, world: world, dt: GameRules.tick)
            b.loadout.update(now: now)
            out += shots
            if now >= b.nextState {
                b.nextState = now + 0.05
                b.seq &+= 1
                var flags: PlayerFlags = [.alive]
                if b.player.isGrounded { flags.insert(.grounded) }
                if input.aiming { flags.insert(.aiming) }
                if b.loadout.isReloading { flags.insert(.reloading) }
                if now - b.lastShotTime < 0.15 { flags.insert(.firing) }
                out.append(.playerState(PlayerStateMessage(slot: slot, seq: b.seq, timeMs: UInt32(clamping: Int((now * 1000).rounded())),
                                                           position: b.player.position, yaw: b.player.yaw, pitch: b.player.pitch,
                                                           velocity: b.player.velocity, flags: flags,
                                                           weapon: b.loadout.current ?? .handgun)))
            }
            bots[slot] = b
        }
        return out
    }

    // MARK: - 考える

    private mutating func think(_ b: inout Bot, part: Participant, match: MatchState, positions: [Int: Vec3], now: Double)
        -> (PlayerInput, [Message]) {
        var input = PlayerInput()
        var messages: [Message] = []
        let eye = b.player.eye
        let t = match.matchTime(at: now)
        let circle = match.zone.circle(at: t)
        let outside = !circle.contains(x: b.player.position.x, z: b.player.position.z)

        // 4 回/秒: 敵をさがす・行き先を決める.
        if now >= b.nextDecision {
            b.nextDecision = now + 0.25
            decide(&b, match: match, positions: positions, circle: circle, outside: outside, now: now)
        }

        // 動く向き.
        var moveYaw = b.player.yaw
        var speedScale: Float = 1
        let enemyPos = b.enemy.flatMap { positions[$0] }

        if let e = enemyPos {
            // たたかう: 敵のほうを向き, 横に動きながら 撃つ.
            let to = e + Vec3(0, 1.3, 0) - eye
            let wantYaw = atan2(to.x, -to.z)
            let flat = (to.x * to.x + to.z * to.z).squareRoot()
            let wantPitch = atan2(to.y, max(flat, 0.1))
            if b.firstSeen == nil { b.firstSeen = now }
            if now >= b.aimOffsetUntil {
                b.aimOffsetUntil = now + 0.5
                let err = difficulty.aimError * .pi / 180
                b.aimOffset = SIMD2(b.rng.float(in: -err...err), b.rng.float(in: -err...err) * 0.6)
            }
            turn(&b, toYaw: wantYaw + b.aimOffset.x, pitch: wantPitch + b.aimOffset.y, rate: difficulty.turnRate)
            let dist = to.length
            if now >= b.strafeUntil {
                b.strafeUntil = now + Double(b.rng.float(in: 0.6...1.6))
                b.strafeSign = b.rng.nextFloat() < 0.5 ? -1 : 1
            }
            input.moveX = b.strafeSign * 0.8
            let spec = b.loadout.currentSpec
            let ideal: Float = spec?.kind == .shotgun ? 10 : (spec?.kind == .sniper ? 45 : 22)
            input.moveY = dist > ideal + 6 ? 1 : (dist < ideal - 8 ? -0.6 : 0)
            input.aiming = dist > 35
            moveYaw = b.player.yaw
            // 撃つ: 反応の遅れが過ぎて, だいたい向いているとき.
            let angleErr = abs(wrapAngle(wantYaw - b.player.yaw)) + abs(wantPitch - b.player.pitch)
            let ready = (now - (b.firstSeen ?? now)) >= difficulty.reaction && angleErr < 0.12
            let hold = ready && b.loadout.currentAmmo > 0 && !b.loadout.isReloading
            // 1 回押すと 1 発の武器は, 押す・はなすをくりかえす.
            let pressed = hold && !(b.triggerHeld && b.loadout.currentSpec?.automatic == false)
            if b.loadout.pullTrigger(held: pressed, now: now) {
                messages += fire(&b, match: match, positions: positions, now: now)
            }
            b.triggerHeld = pressed
            if b.loadout.currentAmmo == 0 { b.loadout.startReload(now: now) }
        } else {
            b.firstSeen = nil
            b.triggerHeld = false
            _ = b.loadout.pullTrigger(held: false, now: now)
            if b.loadout.currentAmmo < (b.loadout.currentSpec?.magazine ?? 0) / 2 { b.loadout.startReload(now: now) }
            var goal = b.goal ?? circle.center3(world)
            if outside { goal = circle.center3(world) }
            let to = goal - b.player.position
            let flat = (to.x * to.x + to.z * to.z).squareRoot()
            if flat > 1.2 {
                moveYaw = atan2(to.x, -to.z)
                input.moveY = 1
            } else {
                b.goal = nil
            }
            // 地面を見るように, 少しずつ前へ向く.
            turn(&b, toYaw: moveYaw, pitch: 0, rate: 6)
            speedScale = 1
            // ひろうものに着いたら, 申し出る.
            if let id = b.lootTarget, id < world.map.loot.count {
                let spot = vec(world.map.loot[id])
                if (spot - b.player.position).length < LootKind.autoPickupRange + 0.5 {
                    messages.append(.pickupRequest(PickupRequestMessage(lootId: id, slot: b.slot)))
                    b.lootTarget = nil
                    b.goal = nil
                }
            }
        }

        // 行きづまり: 0.6 秒たっても進まない → ジャンプして, 横へまわりこむ.
        if now - b.lastPosCheck >= 0.6 {
            let moved = (b.player.position - b.lastPos).horizontal.length
            let wanted = input.moveY != 0 ? GameRules.runSpeed * 0.6 * 0.5 : 0
            if input.moveY != 0 && moved < wanted * 0.4 {
                b.detour = (now + 1.2, b.rng.nextFloat() < 0.5 ? -1 : 1)
                input.jump = true
            }
            b.lastPos = b.player.position
            b.lastPosCheck = now
        }
        if let d = b.detour, now < d.until {
            moveYaw = b.player.yaw + d.sign * 1.1
            input.moveY = 1
            input.moveX = 0
            turn(&b, toYaw: moveYaw, pitch: 0, rate: 6)
        }

        input.yaw = b.player.yaw
        input.pitch = b.player.pitch
        if b.player.position.y < GameRules.killY { input.moveY = 0 }
        _ = speedScale
        return (input, messages)
    }

    private func turn(_ b: inout Bot, toYaw: Float, pitch: Float, rate: Float) {
        let maxStep = rate * GameRules.tick
        b.player.yaw += clamp(wrapAngle(toYaw - b.player.yaw), -maxStep, maxStep)
        b.player.pitch += clamp(pitch - b.player.pitch, -maxStep, maxStep)
    }

    /// 敵・ひろうもの・行き先をえらぶ.
    private mutating func decide(_ b: inout Bot, match: MatchState, positions: [Int: Vec3], circle: Disc, outside: Bool, now: Double) {
        let eye = b.player.eye
        // 見える敵のうち いちばん近い(線がさえぎられていない).
        var best: (slot: Int, dist: Float)?
        for p in match.participants where p.slot != b.slot && p.alive && !p.left {
            guard let pos = positions[p.slot] else { continue }
            let d = (pos - b.player.position).length
            guard d < 80, best == nil || d < best!.dist else { continue }
            let chest = pos + Vec3(0, Hitscan.chestHeight, 0)
            let dir = (chest - eye).normalized()
            let hit = Hitscan.trace(world: world, origin: eye, direction: dir, maxRange: d + 2,
                                    targets: [Hitscan.Target(slot: p.slot, feet: pos)])
            if case .player(let s, _) = hit.kind, s == p.slot { best = (p.slot, d) }
        }
        if let e = best {
            if b.enemy != e.slot { b.firstSeen = nil }
            b.enemy = e.slot
            return
        }
        b.enemy = nil

        // ひろうもの: 近くの(40 m 以内)まだあるもの. 体力が減っていれば 救急, 武器が弱ければ 武器.
        let me = match.participant(b.slot)
        var bestLoot: (id: Int, score: Float)?
        for item in match.loot where !item.taken && item.id < world.map.loot.count {
            let spot = vec(world.map.loot[item.id])
            let d = (spot - b.player.position).horizontal.length
            guard d < 40, circle.contains(x: spot.x, z: spot.z) else { continue }
            var want: Float = 0.3
            switch item.kind {
            case .medkit: want = (me?.hp ?? 100) < 70 ? 1.2 : 0.2
            case .shield: want = (me?.shield ?? 0) < 25 ? 0.9 : 0.2
            default: want = (b.loadout.hasFreeSlot || b.loadout.current == .handgun) ? 1.0 : 0.1
            }
            let score = want * 40 - d
            if want >= 0.5, bestLoot == nil || score > bestLoot!.score { bestLoot = (item.id, score) }
        }
        if let l = bestLoot {
            b.lootTarget = l.id
            b.goal = vec(world.map.loot[l.id])
            b.goalSetAt = now
            return
        }
        b.lootTarget = nil

        // すすむ: 円の外なら 中心へ. 中なら, 敵をさがして近づく(せまい場所のルールは すぐ出会う).
        if outside { b.goal = circle.center3(world); return }
        if b.goal == nil || now - b.goalSetAt > 8 {
            let enemies = match.participants.filter { $0.slot != b.slot && $0.alive && !$0.left }.compactMap { positions[$0.slot] }
            if let near = enemies.min(by: { ($0 - b.player.position).length < ($1 - b.player.position).length }),
               b.rng.nextFloat() < 0.7 {
                b.goal = near
            } else {
                let a = b.rng.float(in: 0...(2 * .pi))
                let r = circle.r * 0.7 * b.rng.nextFloat().squareRoot()
                b.goal = Vec3(circle.x + r * cos(a), 0, circle.z + r * sin(a))
            }
            b.goalSetAt = now
        }
    }

    /// 撃つ: 胸から, ねらった点へ. 当たったものを hitClaim にまとめて, 見た目(shotFx)といっしょに返す.
    private mutating func fire(_ b: inout Bot, match: MatchState, positions: [Int: Vec3], now: Double) -> [Message] {
        guard let spec = b.loadout.currentSpec else { return [] }
        b.lastShotTime = now
        let targets = match.participants.filter { $0.slot != b.slot && $0.alive && !$0.left }.compactMap { p -> Hitscan.Target? in
            positions[p.slot].map { Hitscan.Target(slot: p.slot, feet: $0) }
        }
        let look = b.player.lookDirection
        let aim = b.player.eye + look * 60
        let results = Hitscan.fire(world: world, shooterFeet: b.player.position, aimPoint: aim, targets: targets, spec: spec,
                                   aiming: false, rng: &b.rng)
        var out: [Message] = [.shotFx(ShotFxMessage(slot: b.slot, weapon: spec.kind, origin: results.first?.origin ?? b.player.eye,
                                                    shots: results.map { r in
            var kind: UInt8 = 0
            switch r.kind {
            case .none: kind = 0
            case .ground: kind = 1
            case .obstacle: kind = 2
            case .player: kind = 3
            }
            return .init(end: r.end, hitKind: kind)
        }))]
        // 当たった人ごとに まとめる.
        var perTarget: [Int: (pellets: Int, head: Bool, distance: Float)] = [:]
        for r in results {
            if case .player(let slot, let head) = r.kind {
                var cur = perTarget[slot] ?? (0, false, r.distance)
                cur.pellets += 1
                cur.head = cur.head || head
                cur.distance = min(cur.distance, r.distance)
                perTarget[slot] = cur
            }
        }
        for (slot, hit) in perTarget.sorted(by: { $0.key < $1.key }) {
            b.shotId &+= 1
            out.append(.hitClaim(HitClaimMessage(shotId: b.shotId, attacker: b.slot, target: slot, weapon: spec.kind, head: hit.head,
                                                 pellets: hit.pellets, distance: hit.distance)))
        }
        return out
    }
}

private extension Disc {
    /// 円の中心(高さは 地面).
    func center3(_ world: ArenaWorld) -> Vec3 { Vec3(x, world.terrainHeight(x: x, z: z), z) }
}
