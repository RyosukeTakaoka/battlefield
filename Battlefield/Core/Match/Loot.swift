import Foundation

/// ひろうものの種類. 数字(rawValue)は通信でそのまま使う.
enum LootKind: UInt8, CaseIterable {
    case shield = 0
    case medkit = 1
    case assaultRifle = 2
    case shotgun = 3
    case sniper = 4
    case handgun = 5

    var weapon: WeaponKind? {
        switch self {
        case .assaultRifle: return .assaultRifle
        case .shotgun: return .shotgun
        case .sniper: return .sniper
        case .handgun: return .handgun
        default: return nil
        }
    }

    static let shieldAmount = 25
    static let medkitAmount = 50
    /// 自動でひろう距離(m). ホストが確かめる距離はこれより少しゆるい.
    static let autoPickupRange: Float = 1.5
    static let hostPickupRange: Float = 4
}

/// 置き場 1 か所. `id` は `MapData.loot` の番号.
struct LootItem: Equatable {
    var id: Int
    var kind: LootKind
    var taken = false
}

enum LootTable {
    /// 割合: 武器 45%(ライフル 40 / ショットガン 35 / スナイパー 25)・シールド 30%・救急 25%.
    /// 武器の出ないルール(ラウンド戦)は シールド 50%・救急 50%.
    static func roll(rng: inout SeededRandom, withWeapons: Bool) -> LootKind {
        let r = rng.nextFloat()
        if !withWeapons { return r < 0.5 ? .shield : .medkit }
        if r < 0.45 {
            let w = rng.nextFloat()
            return w < 0.40 ? .assaultRifle : (w < 0.75 ? .shotgun : .sniper)
        }
        return r < 0.75 ? .shield : .medkit
    }
}
