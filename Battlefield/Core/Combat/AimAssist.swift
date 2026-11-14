import Foundation

/// ねらいの助け(タッチ画面は 細かくねらいにくいので, 少しだけ手伝う). 描画を知らない.
///
/// 1. **弾の引きよせ**: 照準のすぐ近く(角度で `GameRules.aimAssistDegrees` まで. ただし 遠いほど せまい)に
///    見えている敵がいれば, ねらった点を その敵の胸(頭の方が近ければ頭)にする. ばらつきは そのまま残る.
/// 2. **視点のブレーキ**: 照準が敵の近く(`aimFrictionDegrees`)にあるあいだは, 視点の動きを少し遅くする.
/// かべの向こうの敵には 効かない(胸から線が通るときだけ).
enum AimAssist {
    struct Result: Equatable {
        var point: Vec3
        /// 引きよせた敵(なければ nil).
        var target: Int?
    }

    /// 照準の線(カメラの位置・向き)と 点 のあいだの角度(度).
    static func angle(from origin: Vec3, direction: Vec3, to point: Vec3) -> Float {
        let to = (point - origin).normalized(or: direction)
        return acos(clamp(direction.dot(to), -1, 1)) * 180 / .pi
    }

    /// 距離 d で 助けが効く角度(度): ふだんは `degrees`, 遠いときは 「横に `aimAssistRadius` m」まで.
    static func cone(degrees: Float, distance d: Float) -> Float {
        min(degrees, atan(GameRules.aimAssistRadius / max(d, 0.1)) * 180 / .pi)
    }

    /// 撃つときの ねらった点(助けつき). 助ける相手がいなければ, ふつうの `Hitscan.aimPoint`.
    static func aimPoint(world: ArenaWorld, cameraPosition cam: Vec3, cameraDirection dir: Vec3, shooterFeet: Vec3,
                         targets: [Hitscan.Target], maxRange: Float, degrees: Float = GameRules.aimAssistDegrees) -> Result {
        let plain = Hitscan.aimPoint(world: world, cameraPosition: cam, cameraDirection: dir, targets: targets)
        guard degrees > 0 else { return Result(point: plain, target: nil) }
        let chestOrigin = shooterFeet + Vec3(0, Hitscan.chestHeight, 0)
        var best: (angle: Float, point: Vec3, slot: Int)?
        for t in targets {
            let chest = t.feet + Vec3(0, 1.0, 0)
            let head = t.feet + Vec3(0, Hitscan.headHeight, 0)
            let d = (chest - chestOrigin).length
            guard d <= maxRange, (chest - cam).dot(dir) > 0 else { continue }
            let limit = cone(degrees: degrees, distance: d)
            let aChest = angle(from: cam, direction: dir, to: chest)
            let aHead = angle(from: cam, direction: dir, to: head)
            let (a, p) = aHead < aChest ? (aHead, head) : (aChest, chest)
            guard a <= limit, best == nil || a < best!.angle else { continue }
            // 胸から その点まで, かべや地面に さえぎられていない.
            let toP = p - chestOrigin
            if let hit = world.raycast(origin: chestOrigin, direction: toP.normalized(), maxDistance: toP.length),
               hit.distance < toP.length - 0.3 { continue }
            best = (a, p, t.slot)
        }
        guard let b = best else { return Result(point: plain, target: nil) }
        return Result(point: b.point, target: b.slot)
    }

    /// 視点の動きに かける数(1 = そのまま). 照準の近くに敵がいれば `aimFriction`.
    static func lookScale(cameraPosition cam: Vec3, cameraDirection dir: Vec3, targets: [Hitscan.Target], maxRange: Float) -> Float {
        for t in targets {
            let chest = t.feet + Vec3(0, 1.0, 0)
            let d = (chest - cam).length
            guard d <= maxRange, (chest - cam).dot(dir) > 0 else { continue }
            if angle(from: cam, direction: dir, to: chest) <= cone(degrees: GameRules.aimFrictionDegrees, distance: d) * 1.5 {
                return GameRules.aimFriction
            }
        }
        return 1
    }
}
