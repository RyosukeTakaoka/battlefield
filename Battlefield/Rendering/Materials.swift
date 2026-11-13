import RealityKit
import UIKit

extension MeshData {
    /// RealityKit のメッシュにする.
    func meshResource(name: String) throws -> MeshResource {
        var d = MeshDescriptor(name: name)
        d.positions = MeshBuffers.Positions(positions)
        d.normals = MeshBuffers.Normals(normals)
        d.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        d.primitives = .triangles(indices)
        return try MeshResource.generate(from: [d])
    }
}

extension UIColor {
    /// マップの JSON にある sRGB の色 [r, g, b].
    convenience init(srgb c: [Float], alpha: CGFloat = 1) {
        self.init(red: CGFloat(c.count > 0 ? c[0] : 1), green: CGFloat(c.count > 1 ? c[1] : 1),
                  blue: CGFloat(c.count > 2 ? c[2] : 1), alpha: alpha)
    }
}

/// 材質(マテリアル)の作り方を 1 か所にまとめる. 見た目の調整はここで行う.
@MainActor
enum Materials {
    /// 地面: 上から見た色の画像. 紙のような, つやの無い面.
    static func ground(_ texture: TextureResource) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: .white, texture: .init(texture))
        m.roughness = .init(floatLiteral: 0.95)
        m.metallic = .init(floatLiteral: 0)
        m.specular = .init(floatLiteral: 0.25)
        // 自分で組み立てたメッシュなので, 表裏の向きの約束が違っても消えないよう両面を描く.
        m.faceCulling = .none
        return m
    }

    /// 崖: 横から貼るくり返しの岩の模様.
    static func rock(_ texture: TextureResource) -> PhysicallyBasedMaterial {
        var m = ground(texture)
        m.roughness = .init(floatLiteral: 0.88)
        m.specular = .init(floatLiteral: 0.35)
        return m
    }

    /// 水面: 空が映るようにつやを出し, 少し透かして川底の色を見せる.
    /// さざ波の法線画像を毎コマずらすと流れて見える(`waterOffset`).
    static func water(color: [Float], normal: TextureResource?, offset: SIMD2<Float> = .zero) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: UIColor(srgb: color))
        m.roughness = .init(floatLiteral: 0.07)
        m.metallic = .init(floatLiteral: 0.0)
        m.specular = .init(floatLiteral: 1.0)
        m.clearcoat = .init(floatLiteral: 0.6)
        m.clearcoatRoughness = .init(floatLiteral: 0.05)
        if let normal { m.normal = .init(texture: .init(normal)) }
        m.textureCoordinateTransform = .init(offset: offset, scale: SIMD2(1, 1), rotation: 0)
        m.blending = .transparent(opacity: .init(floatLiteral: 0.84))
        m.faceCulling = .none
        return m
    }

    /// 小物(木・岩・家): 色見本の画像を共有する.
    static func props(_ atlas: TextureResource, glow: Bool = false) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: .white, texture: .init(atlas))
        m.roughness = .init(floatLiteral: 0.9)
        m.specular = .init(floatLiteral: 0.2)
        if glow {
            // 雲は光が中まで届くので, 影の側も明るい. 少し自分で光らせて近づける.
            m.emissiveColor = .init(color: UIColor(red: 0.55, green: 0.62, blue: 0.80, alpha: 1))
            m.emissiveIntensity = 0.35
        }
        return m
    }

    /// 空のドーム: 光の影響を受けない(画像の色がそのまま見える).
    static func sky(_ texture: TextureResource) -> UnlitMaterial {
        var m = UnlitMaterial()
        m.color = .init(tint: .white, texture: .init(texture))
        return m
    }

    /// 光を受けず, 色だけの板・筒(弾の線・円の壁・ひろうものの光).
    static func glow(_ color: UIColor, opacity: Float = 1) -> UnlitMaterial {
        var m = UnlitMaterial()
        m.color = .init(tint: color)
        if opacity < 1 { m.blending = .transparent(opacity: .init(floatLiteral: opacity)) }
        m.faceCulling = .none
        return m
    }

    /// キャラクターの部品: 色を変えられる, つやの無い面.
    static func character(_ color: UIColor) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: color)
        m.roughness = .init(floatLiteral: 0.8)
        m.metallic = .init(floatLiteral: 0)
        return m
    }

    /// 光を受けない, 半透明の板(風の筋・飛行機雲・影).
    static func overlay(_ texture: TextureResource?, color: UIColor, opacity: Float) -> UnlitMaterial {
        var m = UnlitMaterial()
        if let texture {
            m.color = .init(tint: color, texture: .init(texture))
        } else {
            m.color = .init(tint: color)
        }
        m.blending = .transparent(opacity: .init(floatLiteral: opacity))
        return m
    }
}
