import XCTest
@testable import BattleCore

/// テスト用の「にせの通信」で, 何台ぶんもの `NetSession` をつなぐ(`docs/NETCODE.md` §2).
/// 遅れ・抜け(信頼なしだけ)・順番の入れかわり(信頼なしだけ)を作る. 信頼ありは 遅れるが, 送った人ごとに順番どおり届く.
/// 各台の「自分の時計」は 本当の時間に skew を足したもの(ずれた時計でも 時計合わせが効くか確かめるため).
final class Cluster {
    struct Packet {
        var at: Double
        var order: Int
        var from: Int
        var to: Int
        var data: Data
    }

    var sessions: [NetSession]
    var alive: [Bool]
    var skew: [Double]
    /// 本当の時間(秒).
    var now: Double = 50
    var latency: ClosedRange<Double> = 0.05...0.15
    var loss: Double = 0
    var rng: SeededRandom
    private var queue: [Packet] = []
    private var order = 0
    private var lastReliable: [Int: Double] = [:]
    /// 試合中, 各台が「自分の姿」として送るもの(既定: 出発点にじっと立っている. weapon = スナイパー).
    var snapshotFor: (Cluster, Int) -> LocalSnapshot? = { c, i in
        guard let slot = c.sessions[i].mySlot, let p = c.sessions[i].match.participant(slot), p.alive else { return nil }
        var state = PlayerState(position: p.spawn, yaw: p.spawnYaw)
        state.isGrounded = true
        return LocalSnapshot(player: state, flags: [.grounded, .alive], weapon: .sniper)
    }
    var droppedUnreliable = 0

    init(world: ArenaWorld, keys: [UInt64], skew: [Double]? = nil, seed: UInt64 = 5) {
        sessions = keys.enumerated().map { NetSession(world: world, myKey: $0.element, name: "P\($0.element)", seed: seed &+ UInt64($0.offset)) }
        alive = Array(repeating: true, count: keys.count)
        self.skew = skew ?? Array(repeating: 0, count: keys.count)
        rng = SeededRandom(seed: seed)
    }

    func local(_ i: Int) -> Double { now + skew[i] }

    func connectAll() {
        for i in sessions.indices {
            let others = sessions.indices.filter { $0 != i }
            enqueue(from: i, sessions[i].begin(peers: others, now: local(i)))
        }
    }

    func enqueue(from i: Int, _ outs: [Outgoing]) {
        for o in outs {
            let targets = o.to ?? sessions.indices.filter { $0 != i && alive[$0] }
            for j in targets where j != i && alive[j] {
                var lat = rng.float(in: Float(latency.lowerBound)...Float(latency.upperBound))
                var at = now + Double(lat)
                if o.reliable {
                    let key = i * 100 + j
                    at = max(at, (lastReliable[key] ?? 0) + 1e-6)
                    lastReliable[key] = at
                } else {
                    if Double(rng.nextFloat()) < loss { droppedUnreliable += 1; continue }
                    lat = rng.float(in: Float(latency.lowerBound)...Float(latency.upperBound))     // 順番が入れかわる
                    at = now + Double(lat)
                }
                order += 1
                queue.append(Packet(at: at, order: order, from: i, to: j, data: o.data))
            }
        }
    }

    func step(_ dt: Double = 1.0 / 60) {
        now += dt
        let due = queue.filter { $0.at <= now }.sorted { ($0.at, $0.order) < ($1.at, $1.order) }
        queue.removeAll { $0.at <= now }
        for p in due where alive[p.to] {
            enqueue(from: p.to, sessions[p.to].receive(p.data, from: p.from, now: local(p.to)))
        }
        for i in sessions.indices where alive[i] {
            enqueue(from: i, sessions[i].tick(now: local(i), local: snapshotFor(self, i)))
        }
    }

    func run(_ seconds: Double, dt: Double = 1.0 / 60) {
        let end = now + seconds
        while now < end - 1e-9 { step(min(dt, end - now)) }
    }

    func run(until condition: () -> Bool, timeout: Double = 60) {
        let end = now + timeout
        while !condition() && now < end { step() }
    }

    /// 通信を切る(アプリを消した・電波が切れた). 残りの人に「切れた」と伝わる.
    func kill(_ i: Int) {
        alive[i] = false
        queue.removeAll { $0.to == i || $0.from == i }
        for j in sessions.indices where alive[j] {
            enqueue(from: j, sessions[j].peerChanged(i, connected: false, now: local(j)))
        }
    }

    func send(_ i: Int, _ message: Message) {
        enqueue(from: i, sessions[i].send(message, now: local(i)))
    }

    func startMatch(host: Int, kind: GameMode.Kind? = nil, bots: Int = 0) {
        enqueue(from: host, sessions[host].startMatch(kind: kind, bots: bots, now: local(host)))
    }

    var hostIndex: Int? { sessions.indices.first { alive[$0] && sessions[$0].isHost } }

    func spawn(_ slot: Int, in i: Int) -> Vec3 { sessions[i].match.participant(slot)!.spawn }

    /// slot の人(の端末)が, target をスナイパーの頭で撃つ(1 発でたおせる).
    func shoot(from slot: Int, to target: Int, shotId: UInt16 = 1) {
        guard let i = sessions.indices.first(where: { alive[$0] && sessions[$0].mySlot == slot }) else { return }
        let a = spawn(slot, in: i), t = spawn(target, in: i)
        send(i, .hitClaim(HitClaimMessage(shotId: shotId, attacker: slot, target: target, weapon: .sniper, head: true, pellets: 1,
                                          distance: (a - t).length)))
    }

    /// 生きているほかの人を 全員たおす(1 秒おきに 1 人).
    func win(slot: Int, shotId: inout UInt16) {
        guard let i = sessions.indices.first(where: { alive[$0] && sessions[$0].mySlot == slot }) else { return }
        for p in sessions[i].match.participants where p.slot != slot && p.alive && !p.left {
            shoot(from: slot, to: p.slot, shotId: shotId)
            shotId &+= 1
            run(1.0)
        }
    }

    /// 全員の写し(MatchState)が同じか(まだ ほかの人の状態が飛んでいるあいだは待つ).
    func replicasAgree(_ among: [Int]? = nil) -> Bool {
        let idx = among ?? sessions.indices.filter { alive[$0] }
        guard let first = idx.first else { return true }
        let ref = sessions[first].match
        return idx.allSatisfy { sessions[$0].match.participants == ref.participants && sessions[$0].match.phase == ref.phase
            && sessions[$0].match.round == ref.round && sessions[$0].match.matchId == ref.matchId }
    }
}
