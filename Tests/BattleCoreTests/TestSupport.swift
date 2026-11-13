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
