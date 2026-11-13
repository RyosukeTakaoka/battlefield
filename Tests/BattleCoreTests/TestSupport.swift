import XCTest
@testable import BattleCore

/// テスト用の小さな高さマップ. f(x, z) で高さを決める.
func makeHeightfield(cols: Int = 41, rows: Int = 41, cell: Float = 2, originX: Float = -40, originZ: Float = 40,
                     _ f: (Float, Float) -> Float) -> Heightfield {
    var h: [Float] = []
    for r in 0..<rows {
        for c in 0..<cols {
            h.append(f(originX + Float(c) * cell, originZ - Float(r) * cell))
        }
    }
    return Heightfield(cols: cols, rows: rows, originX: originX, originZ: originZ, cell: cell, heights: h)
}

/// `PPHF` 形式のバイト列を作る(build_arena.py と同じ形式の読み込みを確かめるため).
func pphfData(cols: Int, rows: Int, originX: Float, originZ: Float, cell: Float, heights: [Float]) -> Data {
    var d = Data("PPHF".utf8)
    func u32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
    func f32(_ v: Float) { u32(v.bitPattern) }
    u32(1); u32(UInt32(cols)); u32(UInt32(rows))
    f32(originX); f32(originZ); f32(cell)
    let lo = heights.min() ?? 0, hi = max(heights.max() ?? 1, lo + 1e-3)
    f32(lo); f32(hi)
    for h in heights {
        var q = UInt16(((h - lo) / (hi - lo) * 65535).rounded()).littleEndian
        withUnsafeBytes(of: &q) { d.append(contentsOf: $0) }
    }
    return d
}

/// 試験用の世界: 高さ 2 m の平らな陸(x: -40〜40, z: -40〜40).
/// x > 30 は海(-5 m), z > 20 は急な坂(傾き 2 = 約 63°)になる.
func makeWorld(obstacles: [MapData.Obstacle] = [], loot: [[Float]] = []) -> ArenaWorld {
    let hf = makeHeightfield(cols: 81, rows: 81, cell: 1, originX: -40, originZ: 40) { x, z in
        if x > 30 { return -5 }
        if z > 20 { return 2 + (z - 20) * 2 }
        return 2
    }
    var map = MapData(id: "test", name: "test")
    map.obstacles = obstacles
    map.loot = loot
    return ArenaWorld(map: map, terrain: hf)
}

/// 入力を dt 刻みで seconds 秒ぶん与えて進める.
func simulate(_ state: inout PlayerState, input: PlayerInput, world: ArenaWorld, seconds: Float, dt: Float = GameRules.tick) {
    let n = Int((seconds / dt).rounded())
    for _ in 0..<n { CharacterMotor.step(&state, input: input, world: world, dt: dt) }
}

func standingPlayer(_ x: Float = 0, _ z: Float = 0, yaw: Float = 0) -> PlayerState {
    var p = PlayerState(position: Vec3(x, 2, z), yaw: yaw)
    p.isGrounded = true
    return p
}

/// リポジトリの `Battlefield/Resources` の場所(テストのファイルの位置から決める).
let resourcesURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Battlefield/Resources")

/// 本物の島(`island.json` + `island.height`)を読む.
func loadIsland() throws -> ArenaWorld {
    let map = try MapData.decode(from: Data(contentsOf: resourcesURL.appendingPathComponent("Maps/island.json")))
    let hf = try Heightfield(data: Data(contentsOf: resourcesURL.appendingPathComponent("Maps/island.height")))
    return ArenaWorld(map: map, terrain: hf)
}

/// 1 台の中で, ホストと「写し」を動かす小さな道具(通信は通さない). 返ってきたメッセージを順に apply する.
final class MatchHarness {
    var state = MatchState()
    var host: HostLogic
    var now: Double = 100
    var messages: [Message] = []
    var events: [MatchEvent] = []
    let world: ArenaWorld

    init(world: ArenaWorld, seed: UInt64 = 7) {
        self.world = world
        host = HostLogic(world: world, seed: seed)
    }

    static func roster(_ n: Int) -> [RosterEntry] {
        (0..<n).map { RosterEntry(slot: $0, peerKey: UInt64(1000 + $0), name: "P\($0)", isBot: false) }
    }

    func apply(_ msgs: [Message]) {
        for m in msgs {
            events += state.apply(m, now: now)
            messages.append(m)
        }
    }

    /// 試合を始めて, 戦い始め(カウントダウンの直後)まで進める.
    func begin(_ kind: GameMode.Kind, players n: Int, matchId: UInt32 = 1) {
        apply(host.beginMatch(matchId: matchId, kind: kind, roster: Self.roster(n), now: now))
        advance(to: state.startAt + 0.05)
    }

    func advance(to t: Double, step: Double = 0.1) {
        while now < t - 1e-9 {
            now = min(now + step, t)
            events += state.advance(now: now)
            apply(host.tick(state: state, now: now))
        }
    }

    /// 人の位置と武器をホストに知らせる(playerState のかわり).
    func place(_ slot: Int, _ x: Float, _ z: Float, weapon: WeaponKind = .sniper) {
        host.observe(slot: slot, position: Vec3(x, world.terrainHeight(x: x, z: z), z), weapon: weapon)
    }

    @discardableResult
    func claim(from a: Int, to t: Int, weapon: WeaponKind = .sniper, head: Bool = true, pellets: Int = 1, distance: Float,
               shotId: UInt16 = 1) -> [Message] {
        let m = Message.hitClaim(HitClaimMessage(shotId: shotId, attacker: a, target: t, weapon: weapon, head: head, pellets: pellets,
                                                 distance: distance))
        let out = host.handle(m, sender: a, state: state, now: now)
        apply(out)
        return out
    }

    @discardableResult
    func pickup(slot: Int, loot: Int) -> [Message] {
        let out = host.handle(.pickupRequest(PickupRequestMessage(lootId: loot, slot: slot)), sender: slot, state: state, now: now)
        apply(out)
        return out
    }

    func hp(_ slot: Int) -> Int { state.participant(slot)!.hp }
    func shield(_ slot: Int) -> Int { state.participant(slot)!.shield }
    func alive(_ slot: Int) -> Bool { state.participant(slot)!.alive }
}

/// ホスト + ボットだけで試合を動かす小さな道具(人間は 0 人以上). 毎コマ ボットを動かし, 出したメッセージをホストへ通す.
final class BotMatch {
    let h: MatchHarness
    var runner: BotRunner
    var humans: [Int: Vec3] = [:]
    private var eventIndex = 0
    var hits = 0

    init(world: ArenaWorld, kind: GameMode.Kind, roster: [RosterEntry], seed: UInt64 = 7, difficulty: BotDifficulty = .normal) {
        h = MatchHarness(world: world, seed: seed)
        runner = BotRunner(world: world, difficulty: difficulty, seed: seed)
        h.apply(h.host.beginMatch(matchId: 1, kind: kind, roster: roster, now: h.now))
    }

    static func allBots(_ n: Int) -> [RosterEntry] {
        (0..<n).map { RosterEntry(slot: $0, peerKey: 0, name: "ボット\($0)", isBot: true) }
    }

    func step(_ dt: Double = 1.0 / 60) {
        h.now += dt
        h.events += h.state.advance(now: h.now)
        h.apply(h.host.tick(state: h.state, now: h.now))
        let fresh = Array(h.events[eventIndex...])
        eventIndex = h.events.count
        runner.observe(events: fresh, match: h.state, now: h.now)
        for m in runner.update(now: h.now, dt: Float(dt), match: h.state, humans: humans) {
            switch m {
            case .playerState(let s):
                h.host.observe(slot: s.slot, position: s.position, weapon: s.weapon)
            case .hitClaim(let c):
                let out = h.host.handle(m, sender: c.attacker, state: h.state, now: h.now)
                if !out.isEmpty { hits += 1 }
                h.apply(out)
            case .pickupRequest(let r):
                h.apply(h.host.handle(m, sender: r.slot, state: h.state, now: h.now))
            default:
                break
            }
        }
    }

    func run(_ seconds: Double) {
        let end = h.now + seconds
        while h.now < end - 1e-9 { step() }
    }

    func run(until condition: () -> Bool, timeout: Double) {
        let end = h.now + timeout
        while !condition() && h.now < end { step() }
    }
}
