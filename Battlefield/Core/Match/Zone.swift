import Foundation

/// 安全地帯. 「試合の時計」だけで円が決まる(試合中に円のための通信はしない).
struct Zone: Equatable {
    var initial: Circle
    /// 各段階の終わりの円(ホストが開始のときに全部決めて配る).
    var ends: [Circle]
    var stages: [ZoneStage]
    /// 段階の無いルールの, 円の外のダメージ.
    var outsideDPS: Int

    static let empty = Zone(initial: Circle(x: 0, z: 0, r: 0), ends: [], stages: [], outsideDPS: 0)

    /// 試合の時計 t(秒. 始まりが 0)での円.
    func circle(at t: Float) -> Circle {
        var prev = initial
        var t0: Float = 0
        for (i, st) in stages.enumerated() where i < ends.count {
            let end = ends[i]
            if t < t0 + st.wait { return prev }
            if t < t0 + st.wait + st.shrink {
                return Circle.lerp(prev, end, (t - t0 - st.wait) / max(st.shrink, 1e-3))
            }
            prev = end
            t0 += st.wait + st.shrink
        }
        return prev
    }

    /// 時刻 t の, 円の外のダメージ(1 秒あたり).
    func dps(at t: Float) -> Int {
        guard !stages.isEmpty else { return outsideDPS }
        var t0: Float = 0
        for st in stages {
            if t < t0 + st.wait + st.shrink { return st.dps }
            t0 += st.wait + st.shrink
        }
        return stages.last!.dps
    }

    func isOutside(x: Float, z: Float, at t: Float) -> Bool {
        !circle(at: t).contains(x: x, z: z)
    }

    /// 今, 何段階目か(0 から. 段階の無いルールは 0). 画面の表示用.
    func stageIndex(at t: Float) -> Int {
        var t0: Float = 0
        for (i, st) in stages.enumerated() {
            if t < t0 + st.wait + st.shrink { return i }
            t0 += st.wait + st.shrink
        }
        return max(stages.count - 1, 0)
    }

    /// 次に円が動き(せばまり)始めるまで / せばまり終わるまでの秒数(画面の表示用). 終わったら nil.
    func timeUntilChange(at t: Float) -> (shrinking: Bool, seconds: Float)? {
        var t0: Float = 0
        for st in stages {
            if t < t0 + st.wait { return (false, t0 + st.wait - t) }
            if t < t0 + st.wait + st.shrink { return (true, t0 + st.wait + st.shrink - t) }
            t0 += st.wait + st.shrink
        }
        return nil
    }
}
