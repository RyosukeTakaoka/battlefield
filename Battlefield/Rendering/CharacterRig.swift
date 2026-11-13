import Foundation
import RealityKit
import UIKit

/// 人形(箱を組んだもの). 骨のアニメーションは使わず, 部品の向きを式で動かす(Airplane の `CarpetRig` と同じ考え方).
/// 歩き = あしを sin で前後に / うで = 視線の上下に合わせて 武器を上下 / やられた = うしろへたおれる.
/// 色は slot ごとに 16 色(16 人まで 全員ちがう色). 色だけに頼らないよう, 頭の上の形も 4 種類で変える.
@MainActor
final class CharacterRig {
    let root = Entity()
    private let tilt = Entity()
    private let legL = Entity(), legR = Entity()
    private let armL = Entity(), armR = Entity()
    private let gun = ModelEntity()
    private let flashEntity = ModelEntity()
    private var phase: Float = 0
    private var fall: Float = 0
    private var flashLeft: Float = 0
    private var currentWeapon: WeaponKind?

    static let colors: [UIColor] = [
        UIColor(red: 0.95, green: 0.35, blue: 0.30, alpha: 1), UIColor(red: 0.25, green: 0.55, blue: 0.95, alpha: 1),
        UIColor(red: 0.95, green: 0.80, blue: 0.20, alpha: 1), UIColor(red: 0.35, green: 0.78, blue: 0.40, alpha: 1),
        UIColor(red: 0.70, green: 0.40, blue: 0.90, alpha: 1), UIColor(red: 1.00, green: 0.55, blue: 0.15, alpha: 1),
        UIColor(red: 0.30, green: 0.85, blue: 0.85, alpha: 1), UIColor(red: 0.95, green: 0.50, blue: 0.75, alpha: 1),
        UIColor(red: 0.55, green: 0.35, blue: 0.20, alpha: 1), UIColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1),
        UIColor(red: 0.25, green: 0.25, blue: 0.30, alpha: 1), UIColor(red: 0.60, green: 0.85, blue: 0.20, alpha: 1),
        UIColor(red: 0.15, green: 0.30, blue: 0.70, alpha: 1), UIColor(red: 0.75, green: 0.15, blue: 0.20, alpha: 1),
        UIColor(red: 1.00, green: 0.80, blue: 0.60, alpha: 1), UIColor(red: 0.45, green: 0.60, blue: 0.55, alpha: 1),
    ]

    init(slot: Int) {
        let color = Self.colors[slot % Self.colors.count]
        let dark = Self.shade(color, 0.7)
        let skin = UIColor(red: 0.96, green: 0.80, blue: 0.66, alpha: 1)
        func box(_ size: SIMD3<Float>, _ c: UIColor, at p: Vec3, in parent: Entity) {
            let e = ModelEntity(mesh: .generateBox(size: size, cornerRadius: min(size.x, size.z) * 0.15), materials: [Materials.character(c)])
            e.position = p
            parent.addChild(e)
        }
        root.addChild(tilt)
        // あし(つけねを軸に回す).
        for (leg, x) in [(legL, Float(-0.11)), (legR, Float(0.11))] {
            leg.position = Vec3(x, 0.7, 0)
            box(SIMD3(0.16, 0.7, 0.18), dark, at: Vec3(0, -0.35, 0), in: leg)
            tilt.addChild(leg)
        }
        box(SIMD3(0.46, 0.62, 0.26), color, at: Vec3(0, 1.01, 0), in: tilt)
        box(SIMD3(0.26, 0.26, 0.26), skin, at: Vec3(0, 1.62, 0), in: tilt)
        // 頭の上の形(slot で変える).
        switch slot % 4 {
        case 0: box(SIMD3(0.30, 0.06, 0.30), dark, at: Vec3(0, 1.80, 0), in: tilt)            // 平らな帽子
        case 1: box(SIMD3(0.16, 0.22, 0.16), dark, at: Vec3(0, 1.88, 0), in: tilt)            // たかい帽子
        case 2: box(SIMD3(0.06, 0.20, 0.06), color, at: Vec3(0, 1.88, 0), in: tilt)           // アンテナ
        default: break
        }
        // うで(かたを軸に回す). 右うでが武器を持つ.
        for (arm, x) in [(armL, Float(-0.29)), (armR, Float(0.29))] {
            arm.position = Vec3(x, 1.28, 0)
            box(SIMD3(0.12, 0.55, 0.12), color, at: Vec3(0, -0.27, 0), in: arm)
            tilt.addChild(arm)
        }
        gun.position = Vec3(0, -0.6, 0)
        armR.addChild(gun)
        flashEntity.model = ModelComponent(mesh: .generateSphere(radius: 0.09), materials: [Materials.glow(UIColor(red: 1, green: 0.85, blue: 0.4, alpha: 1))])
        flashEntity.isEnabled = false
        armR.addChild(flashEntity)
        setWeapon(.handgun)
    }

    private static func shade(_ c: UIColor, _ k: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: r * k, green: g * k, blue: b * k, alpha: a)
    }

    /// 武器の見た目(箱 1 つ. 種類で長さと色を変える).
    private func setWeapon(_ w: WeaponKind) {
        guard currentWeapon != w else { return }
        currentWeapon = w
        let (length, thick, color): (Float, Float, UIColor) = {
            switch w {
            case .handgun: return (0.22, 0.07, UIColor(white: 0.25, alpha: 1))
            case .assaultRifle: return (0.62, 0.08, UIColor(red: 0.25, green: 0.28, blue: 0.2, alpha: 1))
            case .shotgun: return (0.55, 0.1, UIColor(red: 0.4, green: 0.25, blue: 0.15, alpha: 1))
            case .sniper: return (0.85, 0.07, UIColor(red: 0.2, green: 0.2, blue: 0.3, alpha: 1))
            }
        }()
        gun.model = ModelComponent(mesh: .generateBox(size: SIMD3(thick, length, thick)), materials: [Materials.character(color)])
        gun.position = Vec3(0, -0.5 - length / 2, 0)
        flashEntity.position = Vec3(0, -0.5 - length - 0.05, 0)
    }

    func muzzleFlash() { flashLeft = 0.06 }

    /// 毎コマ. position は足もと. speed は水平の速さ(m/s).
    func update(position: Vec3, yaw: Float, pitch: Float, speed: Float, grounded: Bool, alive: Bool, weapon: WeaponKind, dt: Float) {
        root.position = position
        root.orientation = simd_quatf(angle: -yaw, axis: Vec3(0, 1, 0))
        setWeapon(weapon)
        // たおれる.
        fall += ((alive ? 0 : 1) - fall) * approach(8, dt)
        tilt.orientation = simd_quatf(angle: fall * .pi / 2, axis: Vec3(1, 0, 0))
        tilt.position = Vec3(0, 0, fall * 0.3)
        // 歩き.
        let moving = alive && grounded && speed > 0.3
        phase += dt * (5 + speed * 1.2)
        let swing: Float = moving ? sin(phase) * min(0.9, 0.35 + speed * 0.08) : 0
        legL.orientation = simd_quatf(angle: swing, axis: Vec3(1, 0, 0))
        legR.orientation = simd_quatf(angle: -swing, axis: Vec3(1, 0, 0))
        if !grounded && alive {                          // ジャンプ中はあしを少し曲げる
            legL.orientation = simd_quatf(angle: -0.5, axis: Vec3(1, 0, 0))
            legR.orientation = simd_quatf(angle: 0.35, axis: Vec3(1, 0, 0))
        }
        // うで: 右は武器を前へ(視線の上下に合わせる), 左はそえる.
        if alive {
            armR.orientation = simd_quatf(angle: .pi / 2 + pitch, axis: Vec3(1, 0, 0))
            armL.orientation = simd_quatf(angle: .pi / 2.3 + pitch * 0.9, axis: Vec3(1, 0, 0)) * simd_quatf(angle: 0.25, axis: Vec3(0, 0, 1))
        } else {
            armR.orientation = simd_quatf(angle: 0.3, axis: Vec3(1, 0, 0))
            armL.orientation = simd_quatf(angle: -0.3, axis: Vec3(1, 0, 0))
        }
        if flashLeft > 0 {
            flashLeft -= dt
            flashEntity.isEnabled = flashLeft > 0
        }
    }
}
