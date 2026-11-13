import Foundation

/// `MatchState` が変わったとき, 画面・音・演出へ知らせる出来事.
enum MatchEvent: Equatable {
    case roundStarting(round: Int, startAt: Double)
    /// カウントダウンが終わって, 戦い始め.
    case roundStarted
    case damaged(target: Int, attacker: Int, weapon: WeaponKind?, hp: Int, shield: Int, head: Bool)
    case eliminated(slot: Int, by: Int?, placement: Int)
    case respawned(slot: Int)
    case lootTaken(id: Int, slot: Int, kind: LootKind)
    case lootRestored(id: Int, kind: LootKind)
    case vitalsChanged(slot: Int, hp: Int, shield: Int)
    case roundEnded(winner: Int?, final: Bool)
    case playerLeft(slot: Int)
}
