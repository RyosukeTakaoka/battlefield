import Foundation

/// ホストの時計と, 自分の時計の「ずれ」を見つもる(`docs/NETCODE.md` §6).
///
/// ping を送った自分の時刻 t0, ホストが答えに入れた時刻 h, 受け取った自分の時刻 t1 から
/// 往復 rtt = t1 - t0, ずれ = h + rtt/2 - t1. 直近 8 回のうち rtt がいちばん小さい回を使う(速く届いた回がいちばん正確).
struct ClockSync: Equatable {
    struct Sample: Equatable {
        var rtt: Double
        var offset: Double
    }

    private(set) var samples: [Sample] = []
    /// 今使っているずれ(ホストの時計 - 自分の時計).
    private(set) var offset: Double
    private var target: Double
    private(set) var hasSample = false

    static let keep = 8
    /// これより大きく違うときは, なめらかにせず すぐ合わせる.
    static let jumpThreshold = 0.5
    /// ずれを直すのにかける秒数.
    static let smoothing = 1.0

    init(offset: Double = 0) {
        self.offset = offset
        target = offset
    }

    mutating func addSample(sent: Double, received: Double, hostTime: Double) {
        let rtt = max(received - sent, 0)
        samples.append(Sample(rtt: rtt, offset: hostTime + rtt / 2 - received))
        if samples.count > Self.keep { samples.removeFirst(samples.count - Self.keep) }
        target = samples.min { $0.rtt < $1.rtt }!.offset
        if !hasSample || abs(target - offset) > Self.jumpThreshold { offset = target }
        hasSample = true
    }

    /// 毎コマ: 使っているずれを, 見つもりへなめらかに近づける.
    mutating func update(dt: Double) {
        guard hasSample else { return }
        offset += (target - offset) * min(1, dt / Self.smoothing)
    }

    /// ホストが替わったとき: 今のずれを覚えたまま, 新しい見つもりを集め直す.
    mutating func restart() {
        samples = []
        hasSample = false
    }

    func hostTime(local: Double) -> Double { local + offset }
}
