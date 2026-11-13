import Foundation
import RealityKit
import UIKit

/// USDZ モデルと画像を読み込み, 使い回す.
///
/// Blender で作ったファイル(`Tools/blender/`)はアプリの中にそのまま入っている.
/// Xcode はフォルダの中身をアプリの一番上の階層にまとめてコピーするので,
/// ファイル名だけで探せる.
@MainActor
final class AssetLibrary {
    enum AssetError: Error, LocalizedError {
        case missing(String)
        var errorDescription: String? {
            switch self { case .missing(let name): return "\(name) が見つかりません" }
        }
    }

    private var textures: [String: TextureResource] = [:]
    private var models: [String: Entity] = [:]
    private var propMeshCache: [String: [PropMesh]] = [:]

    /// 小物 1 種類の, 形 1 つぶんの頂点データ(区画ごとに 1 つへまとめるときに使う).
    struct PropMesh {
        var positions: [SIMD3<Float>]
        var normals: [SIMD3<Float>]
        var uvs: [SIMD2<Float>]
        var indices: [UInt32]

        mutating func append(_ other: PropMesh) {
            let base = UInt32(positions.count)
            positions += other.positions
            normals += other.normals
            uvs += other.uvs
            indices += other.indices.map { $0 + base }
        }
    }

    // MARK: - 画像

    func texture(_ name: String, ext: String, semantic: TextureResource.Semantic = .color) throws -> TextureResource {
        let key = "\(name).\(ext)"
        if let t = textures[key] { return t }
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else { throw AssetError.missing(key) }
        let t = try TextureResource.load(contentsOf: url, withName: key, options: .init(semantic: semantic))
        textures[key] = t
        return t
    }

    func cgImage(_ name: String, ext: String) -> CGImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext),
              let image = UIImage(contentsOfFile: url.path) else { return nil }
        return image.cgImage
    }

    // MARK: - モデル

    /// USDZ を読み込む. 2 回目からは複製を返す(元のデータは共有されるので軽い).
    func model(_ name: String) throws -> Entity {
        if let m = models[name] { return m.clone(recursive: true) }
        let entity = try Entity.load(named: name, in: .main)
        models[name] = entity
        return entity.clone(recursive: true)
    }

    /// 小物の USDZ から, 形ごとの頂点データを取り出す.
    ///
    /// Blender の書き出しでは, ファイルの中に `<種類>_0`, `<種類>_1`, … という
    /// 名前で形違いが並ぶ.
    func propMeshes(_ name: String) throws -> [PropMesh] {
        if let m = propMeshCache[name] { return m }
        let parts = try extractMeshes("Prop_\(name)")
        var byVariant: [Int: PropMesh] = [:]
        for (entityName, mesh) in parts {
            let k = Self.variantIndex(of: entityName, prefix: name)
            byVariant[k, default: PropMesh(positions: [], normals: [], uvs: [], indices: [])].append(mesh)
        }
        let sorted = byVariant.keys.sorted().compactMap { byVariant[$0] }
        guard !sorted.isEmpty else { throw AssetError.missing("Prop_\(name) の形") }
        propMeshCache[name] = sorted
        return sorted
    }

    /// USDZ の中のメッシュを, 名前ごとに取り出す(じゅうたんの帯など).
    func namedMeshes(_ file: String) throws -> [(String, PropMesh)] {
        let parts = try extractMeshes(file)
        guard !parts.isEmpty else { throw AssetError.missing(file) }
        return parts
    }

    /// USDZ の中のメッシュを全部まとめて 1 つの頂点データにする(リングなど).
    func mergedMesh(_ file: String) throws -> MeshData {
        var out = PropMesh(positions: [], normals: [], uvs: [], indices: [])
        for (_, m) in try extractMeshes(file) { out.append(m) }
        guard !out.indices.isEmpty else { throw AssetError.missing(file) }
        return MeshData(positions: out.positions, normals: out.normals, uvs: out.uvs, indices: out.indices)
    }

    /// USDZ を読み, 中のメッシュの頂点を「ゲームの座標」で取り出す.
    ///
    /// Blender の Z 上 → Y 上の変換は親の変換に入っているので, 一番上から見た
    /// 変換をかける(メッシュだけ取り出すと, 向きが 90° ずれてしまう).
    /// 戻り値は (メッシュを持つエンティティかその親の名前, 頂点データ) の列.
    private func extractMeshes(_ file: String) throws -> [(String, PropMesh)] {
        let root = try Entity.load(named: file, in: .main)
        var out: [(String, PropMesh)] = []
        func visit(_ e: Entity) {
            if let model = e.components[ModelComponent.self] {
                let matrix = e.transformMatrix(relativeTo: root)
                var mesh = PropMesh(positions: [], normals: [], uvs: [], indices: [])
                for instance in model.mesh.contents.instances {
                    guard let m = model.mesh.contents.models[instance.model] else { continue }
                    let full = matrix * instance.transform
                    let normalMatrix = simd_float3x3(SIMD3(full.columns.0.x, full.columns.0.y, full.columns.0.z),
                                                     SIMD3(full.columns.1.x, full.columns.1.y, full.columns.1.z),
                                                     SIMD3(full.columns.2.x, full.columns.2.y, full.columns.2.z))
                    for part in m.parts {
                        let base = UInt32(mesh.positions.count)
                        let pos = part.positions.elements
                        mesh.positions += pos.map { p in
                            let v = full * SIMD4<Float>(p, 1)
                            return SIMD3(v.x, v.y, v.z)
                        }
                        if let n = part.normals?.elements, n.count == pos.count {
                            mesh.normals += n.map { simd_normalize(normalMatrix * $0) }
                        } else {
                            mesh.normals += Array(repeating: SIMD3<Float>(0, 1, 0), count: pos.count)
                        }
                        if let uv = part.textureCoordinates?.elements, uv.count == pos.count {
                            mesh.uvs += uv
                        } else {
                            mesh.uvs += Array(repeating: SIMD2<Float>(0.5, 0.5), count: pos.count)
                        }
                        if let idx = part.triangleIndices?.elements {
                            mesh.indices += idx.map { $0 + base }
                        }
                    }
                }
                if !mesh.indices.isEmpty { out.append((Self.meshName(of: e), mesh)) }
            }
            e.children.forEach(visit)
        }
        visit(root)
        return out
    }

    /// メッシュの名前(名前の無いエンティティなら親の名前).
    private static func meshName(of entity: Entity) -> String {
        var e: Entity? = entity
        while let current = e {
            if !current.name.isEmpty { return current.name }
            e = current.parent
        }
        return ""
    }

    /// RealityKit が UV の v を「画像の下から」数えるか「上から」数えるかを確かめる.
    ///
    /// 空のドーム(SkyDome.usdz)は Blender で「真上の頂点の v = 1(下から数える約束)」
    /// として作ってある. 読み込んだ後の真上の頂点の v が 0.5 より大きければ「下から」.
    /// 自分で作るメッシュ(地形)の UV をこれに合わせるので, どちらの約束でも
    /// 地面の画像が正しい向きに貼られる.
    func detectUVOrigin() -> TerrainMesher.UVConvention {
        // 空のドームは あとで空にも使うので, 読んだものを とっておく(`model` が覚える). 2 回読まない.
        guard let root = try? model("SkyDome") else { return .init() }
        var topY = -Float.greatestFiniteMagnitude
        var topV: Float = 1
        func visit(_ e: Entity) {
            if let model = e.components[ModelComponent.self] {
                let matrix = e.transformMatrix(relativeTo: root)
                for instance in model.mesh.contents.instances {
                    guard let m = model.mesh.contents.models[instance.model] else { continue }
                    let full = matrix * instance.transform
                    for part in m.parts {
                        guard let uvs = part.textureCoordinates?.elements else { continue }
                        for (i, p) in part.positions.elements.enumerated() where i < uvs.count {
                            let y = (full * SIMD4<Float>(p, 1)).y
                            if y > topY { topY = y; topV = uvs[i].y }
                        }
                    }
                }
            }
            e.children.forEach(visit)
        }
        visit(root)
        return .init(originAtBottom: topV > 0.5)
    }

    /// 名前 "<種類>_<番号>" から番号を取り出す(見つからなければ 0).
    private static func variantIndex(of name: String, prefix: String) -> Int {
        guard name.hasPrefix(prefix + "_") else { return 0 }
        return Int(name.dropFirst(prefix.count + 1).prefix { $0.isNumber }) ?? 0
    }
}
