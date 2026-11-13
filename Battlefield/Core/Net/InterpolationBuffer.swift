import Foundation

/// 相手 1 人の, 画面に出す姿(補間したもの).
struct RemotePose: Equatable {
    var position: Vec3
    var yaw: Float
    var pitch: Float
    var velocity: Vec3
    var flags: PlayerFlags
    var weapon: WeaponKind
}

/// 相手の動きを なめらかに見せる(`docs/NETCODE.md` §7).
/// 届いた `playerState` を時刻順にためて, 「今 - 100 ms」の姿を 前後の 2 つから補間する.
struct InterpolationBuffer {
    struct Sample: Equatable {
        var t: Double
        var seq: UInt16
        var pose: RemotePose
    }

    private(set) var samples: [Sample] = []

    /// 画面に出す時刻を「今」よりどれだけ前にするか(秒). 送る間隔の 2 倍.
    static let renderDelay = 0.1
    /// 新しいものが来ないとき, 最後の速度でのばす長さの上限(秒).
    static let maxExtrapolation = 0.25
    /// これより大きく飛んだら補間しない(m).
    static let teleportDistance: Float = 5
    /// ためておく長さ(秒).
    static let history = 1.0

    var latest: Sample? { samples.last }

    /// 届いたものを足す. 古い(または同じ)番号のものは捨てる(順番が入れかわっても戻らない).
    mutating func add(_ m: PlayerStateMessage) {
        if let last = samples.last, Int16(bitPattern: m.seq &- last.seq) <= 0 { return }
        samples.append(Sample(t: Double(m.timeMs) / 1000, seq: m.seq,
                              pose: RemotePose(position: m.position, yaw: m.yaw, pitch: m.pitch, velocity: m.velocity,
                                               flags: m.flags, weapon: m.weapon)))
        if let newest = samples.last?.t {
            while samples.count > 2, samples[0].t < newest - Self.history { samples.removeFirst() }
        }
    }

    mutating func clear() { samples = [] }

    /// 時刻 t(ホストの時計. すでに「今 - 100 ms」にしたもの)の姿.
    func pose(at t: Double) -> RemotePose? {
        guard let first = samples.first, let last = samples.last else { return nil }
        if t <= first.t { return first.pose }
        if t >= last.t {
            let dt = Float(min(t - last.t, Self.maxExtrapolation))
            var p = last.pose
            p.position.x += p.velocity.x * dt
            p.position.z += p.velocity.z * dt
            if !p.flags.contains(.grounded) { p.position.y += p.velocity.y * dt }
            return p
        }
        var i = 0
        while i + 1 < samples.count, samples[i + 1].t <= t { i += 1 }
        let a = samples[i], b = samples[i + 1]
        if (b.pose.position - a.pose.position).length > Self.teleportDistance { return a.pose }
        let k = Float((t - a.t) / max(b.t - a.t, 1e-6))
        return RemotePose(position: mix(a.pose.position, b.pose.position, k),
                          yaw: a.pose.yaw + wrapAngle(b.pose.yaw - a.pose.yaw) * k,
                          pitch: mix(a.pose.pitch, b.pose.pitch, k),
                          velocity: mix(a.pose.velocity, b.pose.velocity, k),
                          flags: k < 0.5 ? a.pose.flags : b.pose.flags,
                          weapon: k < 0.5 ? a.pose.weapon : b.pose.weapon)
    }
}
