import Foundation

/// 同じ入力からは必ず同じ値が出る, なめらかな 1 次元ノイズ(-1〜1).
///
/// 風の息(突風)やカメラのわずかな揺れに使う. `random()` を使わないのは,
/// テストで毎回同じ結果を出すため.
struct SmoothNoise {
    var seed: UInt32

    init(seed: UInt32) { self.seed = seed }

    func value(_ t: Float) -> Float {
        let i = Int32(floor(t))
        let f = t - Float(i)
        let u = f * f * (3 - 2 * f)
        return mix(hash(i), hash(i + 1), u)
    }

    /// 周波数を変えて 3 つ重ねたもの(ゆらぎが単調にならない).
    func fractal(_ t: Float) -> Float {
        (value(t) * 0.6 + value(t * 2.17 + 13.1) * 0.28 + value(t * 4.63 + 7.7) * 0.12)
    }

    private func hash(_ i: Int32) -> Float {
        var x = UInt32(bitPattern: i) &* 0x9E37_79B1 ^ seed &* 0x85EB_CA6B
        x ^= x >> 15
        x = x &* 0x2C1B_3C6D
        x ^= x >> 12
        x = x &* 0x297A_2D39
        x ^= x >> 15
        return Float(x & 0xFFFF) / 32767.5 - 1
    }
}
