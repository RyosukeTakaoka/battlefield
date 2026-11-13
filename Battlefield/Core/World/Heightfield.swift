import Foundation

/// 高さマップ(格子状に並んだ地面の高さ). 形式は `build_courses.py` の説明を参照.
///
/// 行 r は z = originZ - r × cell, 列 c は x = originX + c × cell.
/// (紙飛行機は -Z へ進むので, 行が増えるほど先へ進む.)
struct Heightfield: Equatable {
    let cols: Int
    let rows: Int
    let originX: Float
    let originZ: Float
    let cell: Float
    let heights: [Float]

    enum LoadError: Error { case badHeader, truncated }

    init(cols: Int, rows: Int, originX: Float, originZ: Float, cell: Float, heights: [Float]) {
        precondition(heights.count == cols * rows)
        self.cols = cols
        self.rows = rows
        self.originX = originX
        self.originZ = originZ
        self.cell = cell
        self.heights = heights
    }

    init(data: Data) throws {
        let headerSize = 4 + 4 * 3 + 4 * 5
        guard data.count >= headerSize, data.prefix(4) == Data("PPHF".utf8) else { throw LoadError.badHeader }
        func u32(_ offset: Int) -> UInt32 {
            data.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) }
        }
        func f32(_ offset: Int) -> Float { Float(bitPattern: u32(offset)) }
        let version = u32(4)
        guard version == 1 else { throw LoadError.badHeader }
        let cols = Int(u32(8)), rows = Int(u32(12))
        let ox = f32(16), oz = f32(20), cell = f32(24), lo = f32(28), hi = f32(32)
        guard data.count >= headerSize + cols * rows * 2 else { throw LoadError.truncated }
        let scale = (hi - lo) / 65535
        var heights = [Float](repeating: 0, count: cols * rows)
        data.withUnsafeBytes { raw in
            for i in 0..<(cols * rows) {
                let q = UInt16(littleEndian: raw.loadUnaligned(fromByteOffset: headerSize + i * 2, as: UInt16.self))
                heights[i] = lo + Float(q) * scale
            }
        }
        self.init(cols: cols, rows: rows, originX: ox, originZ: oz, cell: cell, heights: heights)
    }

    var minX: Float { originX }
    var maxX: Float { originX + Float(cols - 1) * cell }
    var maxZ: Float { originZ }
    var minZ: Float { originZ - Float(rows - 1) * cell }

    func contains(x: Float, z: Float) -> Bool {
        x >= minX && x <= maxX && z <= maxZ && z >= minZ
    }

    /// 格子の点そのものの高さ(範囲外は端の値).
    func sample(col: Int, row: Int) -> Float {
        heights[clamp(row, 0, rows - 1) * cols + clamp(col, 0, cols - 1)]
    }

    /// (x, z) の高さ. まわりの 4 点から補間する.
    func height(x: Float, z: Float) -> Float {
        let fx = clamp((x - originX) / cell, 0, Float(cols - 1))
        let fz = clamp((originZ - z) / cell, 0, Float(rows - 1))
        let c0 = min(Int(fx), cols - 2), r0 = min(Int(fz), rows - 2)
        let tx = fx - Float(c0), tz = fz - Float(r0)
        let h00 = sample(col: c0, row: r0), h10 = sample(col: c0 + 1, row: r0)
        let h01 = sample(col: c0, row: r0 + 1), h11 = sample(col: c0 + 1, row: r0 + 1)
        return mix(mix(h00, h10, tx), mix(h01, h11, tx), tz)
    }

    /// 地面の法線(上向き). 地形のメッシュの陰影に使う.
    func normal(col: Int, row: Int) -> Vec3 {
        let hl = sample(col: col - 1, row: row), hr = sample(col: col + 1, row: row)
        // 行が増えると z は減る(前へ進む)ので, z の正の向きは「行を戻る」方向.
        let hBack = sample(col: col, row: row - 1), hFront = sample(col: col, row: row + 1)
        let dhdx = (hr - hl) / (2 * cell)
        let dhdz = (hBack - hFront) / (2 * cell)
        return Vec3(-dhdx, 1, -dhdz).normalized(or: .up)
    }
}
