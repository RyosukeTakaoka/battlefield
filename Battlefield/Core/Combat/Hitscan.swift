import Foundation

/// 撃った線の当たり判定(人・地面・障害物). 描画や通信を知らない.
///
/// 撃ち方は 2 段階(`docs/DESIGN.md`):
///  1. カメラから画面のまん中へ線をのばして「ねらった点」を出す.
///  2. 自分の胸から, ねらった点へ(ばらつきを足して)線をのばす. これが本当の弾.
enum Hitscan {
    /// 人の形: 体 = カプセル(半径 0.35, 足もと +0.35〜+1.05 なので上は 1.4 m まで), 頭 = 球(半径 0.25, 足もと +1.62).
    static let bodyRadius: Float = 0.35
    static let bodyBottom: Float = 0.35
    static let bodyTop: Float = 1.05
    static let headRadius: Float = 0.25
    static let headHeight: Float = 1.62
    /// 弾が出る胸の高さ.
    static let chestHeight: Float = 1.35
    /// ねらった点が見つからないときの遠さ.
    static let farAim: Float = 300

    struct Target: Equatable {
        var slot: Int
        /// 足もと.
        var feet: Vec3
    }

    enum HitKind: Equatable {
        case none
        case ground
        case obstacle
        case player(slot: Int, head: Bool)
    }

    struct ShotResult: Equatable {
        var origin: Vec3
        var end: Vec3
        var kind: HitKind
        var distance: Float
    }

    // MARK: 形との交差

    /// 線と球. 当たる距離(線の始まりが球の中なら nil).
    static func raySphere(origin o: Vec3, direction d: Vec3, center c: Vec3, radius r: Float) -> Float? {
        let oc = o - c
        let b = oc.dot(d)
        let h = b * b - (oc.dot(oc) - r * r)
        guard h >= 0 else { return nil }
        let t = -b - h.squareRoot()
        return t >= 0 ? t : nil
    }

    /// 線とカプセル(a〜b を結ぶ線分から半径 r).
    static func rayCapsule(origin o: Vec3, direction d: Vec3, a: Vec3, b: Vec3, radius r: Float) -> Float? {
        let ba = b - a, oa = o - a
        let baba = ba.dot(ba), bard = ba.dot(d), baoa = ba.dot(oa)
        let rdoa = d.dot(oa), oaoa = oa.dot(oa)
        let aa = baba - bard * bard
        let bb = baba * rdoa - baoa * bard
        let cc = baba * oaoa - baoa * baoa - r * r * baba
        var best: Float?
        func consider(_ t: Float?) { if let t, best == nil || t < best! { best = t } }
        if aa > 1e-8 {
            let h = bb * bb - aa * cc
            if h >= 0 {
                let t = (-bb - h.squareRoot()) / aa
                let y = baoa + t * bard
                if t >= 0 && y > 0 && y < baba { consider(t) }
            }
        }
        consider(raySphere(origin: o, direction: d, center: a, radius: r))
        consider(raySphere(origin: o, direction: d, center: b, radius: r))
        return best
    }

    // MARK: 線をのばす

    /// origin から direction(長さ 1)へ maxRange まで. 世界と人のうち いちばん近い当たりを返す.
    static func trace(world: ArenaWorld, origin: Vec3, direction: Vec3, maxRange: Float, targets: [Target]) -> ShotResult {
        var bestT = maxRange
        var kind = HitKind.none
        if let hit = world.raycast(origin: origin, direction: direction, maxDistance: maxRange) {
            bestT = hit.distance
            kind = hit.surface == .terrain ? .ground : .obstacle
        }
        for t in targets {
            let a = t.feet + Vec3(0, bodyBottom, 0), b = t.feet + Vec3(0, bodyTop, 0)
            let head = t.feet + Vec3(0, headHeight, 0)
            let bodyT = rayCapsule(origin: origin, direction: direction, a: a, b: b, radius: bodyRadius)
            let headT = raySphere(origin: origin, direction: direction, center: head, radius: headRadius)
            if let ht = headT, ht < bestT, ht <= (bodyT ?? .infinity) + 0.001 {
                bestT = ht
                kind = .player(slot: t.slot, head: true)
            } else if let bt = bodyT, bt < bestT {
                bestT = bt
                kind = .player(slot: t.slot, head: false)
            }
        }
        return ShotResult(origin: origin, end: origin + direction * bestT, kind: kind, distance: bestT)
    }

    /// カメラの位置と向きから「ねらった点」を出す(自分は targets に入れない).
    static func aimPoint(world: ArenaWorld, cameraPosition: Vec3, cameraDirection: Vec3, targets: [Target]) -> Vec3 {
        trace(world: world, origin: cameraPosition, direction: cameraDirection, maxRange: farAim, targets: targets).end
    }

    /// 向き direction のまわりに, 最大 spreadDegrees 度ずらす(円の中で一様).
    static func perturbed(_ direction: Vec3, spreadDegrees: Float, rng: inout SeededRandom) -> Vec3 {
        guard spreadDegrees > 0 else { return direction }
        let helper: Vec3 = abs(direction.y) < 0.99 ? .up : .right
        let u = direction.cross(helper).normalized()
        let v = direction.cross(u).normalized()
        let radius = tan(spreadDegrees * .pi / 180) * rng.nextFloat().squareRoot()
        let phi = rng.nextFloat() * 2 * .pi
        return (direction + (u * cos(phi) + v * sin(phi)) * radius).normalized()
    }

    /// 1 回撃つ(散弾なら pellets 粒). 胸から, ねらった点へ.
    static func fire(world: ArenaWorld, shooterFeet: Vec3, aimPoint: Vec3, targets: [Target], spec: WeaponSpec,
                     aiming: Bool, rng: inout SeededRandom) -> [ShotResult] {
        let chest = shooterFeet + Vec3(0, chestHeight, 0)
        let base = (aimPoint - chest).normalized(or: .forward)
        let spread = spec.spread(aiming: aiming)
        return (0..<spec.pellets).map { _ in
            let dir = perturbed(base, spreadDegrees: spread, rng: &rng)
            return trace(world: world, origin: chest, direction: dir, maxRange: spec.maxRange, targets: targets)
        }
    }
}
