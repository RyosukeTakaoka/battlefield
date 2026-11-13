import Foundation

/// 描画用のメッシュの材料(頂点・法線・UV・三角形). RealityKit に依存しない形で持つ.
struct MeshData: Equatable {
    var positions: [Vec3] = []
    var normals: [Vec3] = []
    var uvs: [SIMD2<Float>] = []
    var indices: [UInt32] = []

    var isEmpty: Bool { indices.isEmpty }
    var triangleCount: Int { indices.count / 3 }

    /// 別のメッシュを, 拡大 → Y 軸まわりに回転 → 移動 してから足す(小物をまとめるとき).
    mutating func append(_ other: MeshData, translation: Vec3, yaw: Float, scale: Vec3) {
        let c = cos(yaw), s = sin(yaw)
        let base = UInt32(positions.count)
        positions.reserveCapacity(positions.count + other.positions.count)
        for p in other.positions {
            let q = p * scale
            positions.append(Vec3(c * q.x + s * q.z, q.y, -s * q.x + c * q.z) + translation)
        }
        for n in other.normals {
            let q = n / scale
            normals.append(Vec3(c * q.x + s * q.z, q.y, -s * q.x + c * q.z).normalized(or: .up))
        }
        uvs += other.uvs
        indices += other.indices.map { $0 + base }
    }
}

/// 高さマップから地形・水面のメッシュを作る(Airplane の `TerrainMesher` を, 四角い区画用に直したもの).
enum TerrainMesher {
    /// 面の法線の上向き成分がこれより小さい(=急な)面は「崖」の材質にする.
    /// 歩ける坂の限り(`GameRules.walkableNormalY`)と同じ値.
    static let rockSlopeNY: Float = 0.62
    /// 崖の岩の模様 1 枚が覆う長さ(m).
    static let rockTile: Float = 9

    struct Chunk {
        var ground: MeshData
        var rock: MeshData
    }

    /// UV の v を画像の下から数えるか(USD と同じ)上から数えるか.
    /// RealityKit の約束は実行時に確かめる(`AssetLibrary.detectUVOrigin`).
    struct UVConvention {
        var originAtBottom = true
        func v(_ fromBottom: Float) -> Float { originAtBottom ? fromBottom : 1 - fromBottom }
    }

    /// 地面の画像 1 枚が覆う四角(x と z の範囲).
    struct ImageRect: Equatable {
        var xMin: Float, xMax: Float, zMin: Float, zMax: Float
    }

    /// 四角い 1 区画(x: xMin〜xMax, z: zMin〜zMax)の地形.
    /// `image` は地面の絵 1 枚が覆う範囲. 区画の UV はその中での位置になる(区画が絵の一部を使う).
    static func chunk(_ hf: Heightfield, xMin: Float, xMax: Float, zMin: Float, zMax: Float,
                      image: ImageRect, splitRock: Bool, uv: UVConvention) -> Chunk {
        let c0 = clamp(Int(((xMin - hf.originX) / hf.cell).rounded()), 0, hf.cols - 1)
        let c1 = clamp(Int(((xMax - hf.originX) / hf.cell).rounded()), 0, hf.cols - 1)
        let r0 = clamp(Int(((hf.originZ - zMax) / hf.cell).rounded()), 0, hf.rows - 1)
        let r1 = clamp(Int(((hf.originZ - zMin) / hf.cell).rounded()), 0, hf.rows - 1)
        let cols = c1 - c0 + 1
        let rows = r1 - r0 + 1
        var ground = MeshData()
        ground.positions.reserveCapacity(cols * rows)
        let imgW = max(image.xMax - image.xMin, 1e-3), imgH = max(image.zMax - image.zMin, 1e-3)
        for r in r0...r1 {
            let z = hf.originZ - Float(r) * hf.cell
            for c in c0...c1 {
                let x = hf.originX + Float(c) * hf.cell
                ground.positions.append(Vec3(x, hf.sample(col: c, row: r), z))
                ground.normals.append(hf.normal(col: c, row: r))
                ground.uvs.append(SIMD2((x - image.xMin) / imgW, uv.v((z - image.zMin) / imgH)))
            }
        }
        var rock = MeshData()
        var groundIndices: [UInt32] = []
        groundIndices.reserveCapacity((cols - 1) * (rows - 1) * 6)
        for rr in 0..<(rows - 1) {
            for c in 0..<(cols - 1) {
                let a = UInt32(rr * cols + c), b = a + 1
                let d = a + UInt32(cols), e = d + 1
                // 上から見て反時計回り(法線が上を向く)の順.
                for tri in [[a, b, d], [b, e, d]] {
                    let p0 = ground.positions[Int(tri[0])], p1 = ground.positions[Int(tri[1])], p2 = ground.positions[Int(tri[2])]
                    let fn = (p1 - p0).cross(p2 - p0).normalized(or: .up)
                    if splitRock && fn.y < rockSlopeNY {
                        let useX = abs(fn.x) > abs(fn.z)
                        let base = UInt32(rock.positions.count)
                        for i in tri {
                            let p = ground.positions[Int(i)]
                            rock.positions.append(p)
                            rock.normals.append(ground.normals[Int(i)])
                            rock.uvs.append(SIMD2((useX ? p.z : p.x) / rockTile, p.y / rockTile))
                        }
                        rock.indices += [base, base + 1, base + 2]
                    } else {
                        groundIndices += tri
                    }
                }
            }
        }
        ground.indices = groundIndices
        return Chunk(ground: ground, rock: rock)
    }

    /// 海の平らな水面(高さ y. 中心 (0, 0) から 四方に half だけ).
    static func flatWater(half: Float, y: Float = 0) -> MeshData {
        var m = MeshData()
        for z in [-half, half] {
            for x in [-half, half] {
                m.positions.append(Vec3(x, y, z))
                m.normals.append(.up)
                m.uvs.append(SIMD2(x / 24, -z / 24))
            }
        }
        m.indices = gridIndices(cols: 2, rows: 2)
        return m
    }

    /// 小物をまとめて 1 つのメッシュにする. meshes は [種類: [形ごとのメッシュ]].
    static func props(_ instances: [PropInstance], meshes: [String: [MeshData]]) -> MeshData {
        var out = MeshData()
        for inst in instances {
            guard let variants = meshes[inst.name], !variants.isEmpty else { continue }
            out.append(variants[min(inst.variant, variants.count - 1)], translation: inst.position, yaw: inst.yaw,
                       scale: inst.scale)
        }
        return out
    }

    /// 行が z の減る向き(前)へ並ぶ格子の三角形(法線が上を向く順).
    static func gridIndices(cols: Int, rows: Int) -> [UInt32] {
        var idx: [UInt32] = []
        idx.reserveCapacity((cols - 1) * (rows - 1) * 6)
        for r in 0..<(rows - 1) {
            for c in 0..<(cols - 1) {
                let a = UInt32(r * cols + c), b = a + 1
                let d = a + UInt32(cols), e = d + 1
                idx += [a, b, d, b, e, d]
            }
        }
        return idx
    }
}
