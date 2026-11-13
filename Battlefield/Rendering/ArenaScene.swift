import Foundation
import RealityKit
import UIKit

/// 島の景色(地形・崖・水・小物・空のドーム)と, ひろうもの・安全地帯の見た目.
/// 組み立ては `build` で 1 回だけ(Airplane の `CourseScene` と同じやり方: 高さマップからメッシュを作り, 小物は区画ごとに 1 つへまとめる).
@MainActor
final class ArenaScene {
    static let skyRadius: Float = 2600
    /// 地形の区画: 4 × 4, 1 つ 128 m. 地面の絵は 2 × 2 枚(1 枚 256 m 四方).
    static let chunkSize: Float = 128
    static let tileSize: Float = 256

    let root = Entity()
    let world: ArenaWorld
    private var skyDome: Entity?
    private var zoneEntity: ModelEntity?
    private var lootRoot = Entity()
    private var lootEntities: [Int: ModelEntity] = [:]
    private var lootBase: [Int: Vec3] = [:]

    private init(world: ArenaWorld) { self.world = world }

    // MARK: - 組み立て

    static func build(world: ArenaWorld, assets: AssetLibrary, quality: GameSettings.Quality,
                      progress: @escaping (Double) -> Void) async throws -> ArenaScene {
        let scene = ArenaScene(world: world)
        let map = world.map
        let uv = assets.detectUVOrigin()
        progress(0.05)

        // 小物の形(USDZ から頂点を取り出す).
        var propMeshes: [String: [MeshData]] = [:]
        for name in Set(map.props.map(\.name)) {
            if let variants = try? assets.propMeshes(name) {
                propMeshes[name] = variants.map { MeshData(positions: $0.positions, normals: $0.normals, uvs: $0.uvs, indices: $0.indices) }
            }
        }
        progress(0.15)

        // 区画のメッシュは重いので, 画面を止めないよう裏で作る(裏の処理には 書き換えない値だけ渡す).
        struct Cell { var cx: Int; var cz: Int }
        let cells = (0..<4).flatMap { cx in (0..<4).map { Cell(cx: cx, cz: $0) } }
        let terrain = world.terrain
        let lighter = quality == .standard
        let meshes = propMeshes
        let props = map.props
        let size = chunkSize, tile = tileSize
        let built: [(TerrainMesher.Chunk, MeshData)] = await Task.detached(priority: .userInitiated) {
            cells.map { c in
                let xMin = -256 + Float(c.cx) * size, xMax = xMin + size
                let zMax = 256 - Float(c.cz) * size, zMin = zMax - size
                let col = c.cx / 2, row = c.cz / 2
                let image = TerrainMesher.ImageRect(xMin: -256 + Float(col) * tile, xMax: -256 + Float(col + 1) * tile,
                                                    zMin: 256 - Float(row + 1) * tile, zMax: 256 - Float(row) * tile)
                let chunk = TerrainMesher.chunk(terrain, xMin: xMin, xMax: xMax, zMin: zMin, zMax: zMax, image: image,
                                                splitRock: true, uv: uv)
                var inside = props.filter { $0.position.x >= xMin && $0.position.x < xMax && $0.position.z >= zMin && $0.position.z < zMax }
                // かるい画質: 草と茂みを半分にする(木・岩・建物はそのまま).
                if lighter {
                    var n = 0
                    inside = inside.filter { p in
                        guard p.name == "GrassTuft" || p.name == "Bush" else { return true }
                        n += 1
                        return n % 2 == 0
                    }
                }
                return (chunk, TerrainMesher.props(inside, meshes: meshes))
            }
        }.value
        progress(0.5)

        let rockTexture = try? assets.texture("Rock_valley", ext: "jpg")
        let atlas = try assets.texture("PropAtlas", ext: "png")
        let propMaterial = Materials.props(atlas, glow: false)
        for (i, (chunk, propMesh)) in built.enumerated() {
            let c = cells[i]
            let col = c.cx / 2, row = c.cz / 2
            let groundTex = try assets.texture("island_\(row * 2 + col)", ext: "jpg")
            let entity = Entity()
            entity.name = "Chunk_\(i)"
            entity.addChild(ModelEntity(mesh: try chunk.ground.meshResource(name: "Ground_\(i)"), materials: [Materials.ground(groundTex)]))
            if !chunk.rock.isEmpty, let rockTexture {
                entity.addChild(ModelEntity(mesh: try chunk.rock.meshResource(name: "Rock_\(i)"), materials: [Materials.rock(rockTexture)]))
            }
            if !propMesh.isEmpty {
                entity.addChild(ModelEntity(mesh: try propMesh.meshResource(name: "Props_\(i)"), materials: [propMaterial]))
            }
            scene.root.addChild(entity)
            progress(0.5 + 0.35 * Double(i + 1) / Double(built.count))
            await Task.yield()
        }

        // 海.
        let waterNormal = try? assets.texture("Water_Normal", ext: "png", semantic: .normal)
        let sea = TerrainMesher.flatWater(half: 1200, y: map.waterY)
        let seaEntity = ModelEntity(mesh: try sea.meshResource(name: "Sea"),
                                    materials: [Materials.water(color: [0.12, 0.42, 0.62], normal: waterNormal)])
        scene.root.addChild(seaEntity)

        try scene.addSky(assets: assets, texture: map.sky)
        scene.addZone()
        scene.root.addChild(scene.lootRoot)
        progress(1.0)
        return scene
    }

    private func addSky(assets: AssetLibrary, texture: String) throws {
        let dome = try assets.model("SkyDome")
        let tex = try assets.texture(texture, ext: "png")
        Self.forEachModel(in: dome) { $0.model?.materials = [Materials.sky(tex)] }
        dome.scale = SIMD3(repeating: Self.skyRadius)
        root.addChild(dome)
        skyDome = dome
    }

    private static func forEachModel(in entity: Entity, _ body: (ModelEntity) -> Void) {
        if let m = entity as? ModelEntity { body(m) }
        for child in entity.children { forEachModel(in: child, body) }
    }

    // MARK: - 安全地帯

    /// 内向きの半透明の筒(半径 1 の筒を 拡大して使う).
    private func addZone() {
        var wall = MeshData()
        let n = 72
        let y0: Float = -30, y1: Float = 140
        for i in 0...n {
            let a = Float(i) / Float(n) * 2 * .pi
            let x = cos(a), z = sin(a)
            wall.positions += [Vec3(x, y0, z), Vec3(x, y1, z)]
            wall.normals += [Vec3(-x, 0, -z), Vec3(-x, 0, -z)]
            wall.uvs += [SIMD2(Float(i) / Float(n), 0), SIMD2(Float(i) / Float(n), 1)]
        }
        for i in 0..<n {
            let a = UInt32(i * 2)
            wall.indices += [a, a + 1, a + 2, a + 1, a + 3, a + 2]
        }
        guard let mesh = try? wall.meshResource(name: "ZoneWall") else { return }
        let e = ModelEntity(mesh: mesh, materials: [Materials.glow(UIColor(red: 0.62, green: 0.3, blue: 1.0, alpha: 1), opacity: 0.22)])
        e.isEnabled = false
        root.addChild(e)
        zoneEntity = e
    }

    func setZone(_ circle: Disc?) {
        guard let e = zoneEntity else { return }
        guard let c = circle, c.r > 0.5 else { e.isEnabled = false; return }
        e.isEnabled = true
        e.position = Vec3(c.x, 0, c.z)
        e.scale = Vec3(c.r, 1, c.r)
    }

    // MARK: - ひろうもの

    static func lootColor(_ kind: LootKind) -> UIColor {
        switch kind {
        case .shield: return UIColor(red: 0.3, green: 0.6, blue: 1.0, alpha: 1)
        case .medkit: return UIColor(red: 0.3, green: 0.95, blue: 0.45, alpha: 1)
        case .assaultRifle: return UIColor(red: 1.0, green: 0.6, blue: 0.15, alpha: 1)
        case .shotgun: return UIColor(red: 1.0, green: 0.3, blue: 0.25, alpha: 1)
        case .sniper: return UIColor(red: 0.75, green: 0.4, blue: 1.0, alpha: 1)
        case .handgun: return UIColor(white: 0.85, alpha: 1)
        }
    }

    /// ラウンドの始まり(または 取られた物が また出たとき): 置き場の見た目を作り直す.
    func setLoot(_ items: [LootItem]) {
        for e in lootEntities.values { e.removeFromParent() }
        lootEntities = [:]
        lootBase = [:]
        for item in items {
            guard item.id < world.map.loot.count else { continue }
            let base = vec(world.map.loot[item.id])
            let color = Self.lootColor(item.kind)
            let isWeapon = item.kind.weapon != nil
            let size = isWeapon ? SIMD3<Float>(0.9, 0.2, 0.28) : SIMD3<Float>(0.45, 0.45, 0.45)
            let e = ModelEntity(mesh: .generateBox(size: size), materials: [Materials.glow(color)])
            // 遠くからも見つけやすい細い光の柱.
            let beam = ModelEntity(mesh: .generateBox(size: SIMD3(0.07, 7, 0.07)), materials: [Materials.glow(color, opacity: 0.35)])
            beam.position = Vec3(0, 3.5, 0)
            e.addChild(beam)
            e.position = base
            lootRoot.addChild(e)
            lootEntities[item.id] = e
            lootBase[item.id] = base
        }
    }

    // MARK: - 毎コマ

    func update(camera: Vec3, time: Float, loot: [LootItem], zone: Disc?) {
        skyDome?.position = camera
        setZone(zone)
        for item in loot {
            guard let e = lootEntities[item.id], let base = lootBase[item.id] else { continue }
            let near = (base - camera).horizontal.lengthSquared < 220 * 220
            let visible = !item.taken && near
            if e.isEnabled != visible { e.isEnabled = visible }
            guard visible else { continue }
            e.position = base + Vec3(0, 0.25 + sin(time * 2 + Float(item.id)) * 0.12, 0)
            e.orientation = simd_quatf(angle: time * 1.6 + Float(item.id), axis: Vec3(0, 1, 0))
        }
    }
}
