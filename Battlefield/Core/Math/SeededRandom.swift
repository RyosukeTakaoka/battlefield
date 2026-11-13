import Foundation

/// 種(seed)から決まる乱数(SplitMix64). 同じ種からは, どの端末でも同じ順に同じ値が出る.
///
/// ひろうものの中身・武器の組・弾のばらつきなど, 「みんなで同じにしたい」「テストで毎回同じにしたい」ところに使う.
/// `RandomNumberGenerator` にも合わせてあるので `shuffled(using:)` なども使える.
struct SeededRandom: RandomNumberGenerator {
    private(set) var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0 以上 1 より小さい値.
    mutating func nextFloat() -> Float {
        Float(next() >> 40) / Float(1 << 24)
    }

    /// lo 以上 hi 以下(hi は含まなくてよい)の値.
    mutating func float(in range: ClosedRange<Float>) -> Float {
        range.lowerBound + nextFloat() * (range.upperBound - range.lowerBound)
    }

    /// 0 以上 n より小さい整数(n が 0 以下なら 0).
    mutating func int(below n: Int) -> Int {
        n > 0 ? Int(next() % UInt64(n)) : 0
    }
}
