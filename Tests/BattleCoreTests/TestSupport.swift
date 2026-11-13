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
