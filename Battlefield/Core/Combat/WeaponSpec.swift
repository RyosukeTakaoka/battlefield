import Foundation

/// 武器の種類. 数字(rawValue)は通信でそのまま使う.
enum WeaponKind: UInt8, CaseIterable, Codable {
    case handgun = 0
    case assaultRifle = 1
    case shotgun = 2
    case sniper = 3
}

/// 武器の数字(`docs/DESIGN.md` の「武器」の表と同じ). 全部 hitscan(撃った瞬間に線で当たりを調べる).
struct WeaponSpec: Equatable {
    var kind: WeaponKind
    var name: String
    /// 体に当たったときの威力(散弾は 1 粒あたり).
    var damage: Float
    var headMultiplier: Float
    /// 1 秒に何発撃てるか.
    var fireRate: Float
    /// 押しっぱなしで連射できるか(false は 1 回押すと 1 発).
    var automatic: Bool
    var magazine: Int
    var reloadTime: Float
    /// 弾のばらつき(度). 腰だめ / 構え.
    var spreadHip: Float
    var spreadAim: Float
    /// 威力が落ち始める距離と, 半分になる距離(nil = 落ちない).
    var falloffStart: Float?
    var falloffHalf: Float?
    /// ここより遠くには当たらない.
    var maxRange: Float
    /// 1 回に飛ぶ粒の数.
    var pellets: Int

    var fireInterval: Float { 1 / fireRate }

    /// 距離 distance(m)・頭かどうか での, 1 粒の威力(整数). 届かない距離は 0.
    func damage(distance: Float, head: Bool) -> Int {
        guard distance <= maxRange else { return 0 }
        var mult: Float = 1
        if let start = falloffStart, let half = falloffHalf, distance > start {
            mult = distance >= half ? 0.5 : mix(1, 0.5, (distance - start) / (half - start))
        }
        return Int((damage * (head ? headMultiplier : 1) * mult).rounded())
    }

    func spread(aiming: Bool) -> Float { aiming ? spreadAim : spreadHip }

    static let all: [WeaponSpec] = [
        WeaponSpec(kind: .handgun, name: "ハンドガン", damage: 18, headMultiplier: 1.5, fireRate: 4, automatic: false,
                   magazine: 12, reloadTime: 1.2, spreadHip: 1.0, spreadAim: 0.4, falloffStart: 40, falloffHalf: 80,
                   maxRange: 160, pellets: 1),
        WeaponSpec(kind: .assaultRifle, name: "アサルトライフル", damage: 14, headMultiplier: 1.5, fireRate: 9, automatic: true,
                   magazine: 25, reloadTime: 2.0, spreadHip: 1.4, spreadAim: 0.6, falloffStart: 60, falloffHalf: 120,
                   maxRange: 240, pellets: 1),
        WeaponSpec(kind: .shotgun, name: "ショットガン", damage: 9, headMultiplier: 1.25, fireRate: 1.1, automatic: false,
                   magazine: 5, reloadTime: 2.6, spreadHip: 5.5, spreadAim: 4.5, falloffStart: 12, falloffHalf: 30,
                   maxRange: 60, pellets: 8),
        WeaponSpec(kind: .sniper, name: "スナイパー", damage: 70, headMultiplier: 2.0, fireRate: 0.8, automatic: false,
                   magazine: 4, reloadTime: 3.0, spreadHip: 4.0, spreadAim: 0.1, falloffStart: nil, falloffHalf: nil,
                   maxRange: 300, pellets: 1),
    ]

    static func spec(_ kind: WeaponKind) -> WeaponSpec { all[Int(kind.rawValue)] }
}
