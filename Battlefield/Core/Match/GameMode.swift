import Foundation

/// 円(上から見た中心と半径). 戦う場所・安全地帯に使う.
struct Disc: Equatable {
    var x: Float
    var z: Float
    var r: Float

    func contains(x px: Float, z pz: Float) -> Bool {
        let dx = px - x, dz = pz - z
        return dx * dx + dz * dz <= r * r
    }

    static func lerp(_ a: Disc, _ b: Disc, _ t: Float) -> Disc {
        Disc(x: mix(a.x, b.x, t), z: mix(a.z, b.z, t), r: mix(a.r, b.r, t))
    }
}

/// 安全地帯の 1 段階: wait 秒待ち, shrink 秒かけて 始めの半径 × endFraction の円へ. そのあいだ 外にいると 1 秒ごとに dps のダメージ.
struct ZoneStage: Equatable {
    var wait: Float
    var shrink: Float
    var endFraction: Float
    var dps: Int
}

/// ルール 3 つの「数字の表」(`docs/DESIGN.md` の「3 つのルール」). ルールごとの `if` を散らさず, ここの値を読む.
struct GameMode: Equatable {
    enum Kind: UInt8, CaseIterable {
        /// ラウンド戦: 2〜4 人. せまい場所. 最後の 1 人がラウンドを取り, 先に 3 ラウンド取った人の勝ち.
        case roundBattle = 0
        /// キル勝負: 2〜4 人. やられても 3 秒で復活. 先に N キル.
        case killRace = 1
        /// バトルロイヤル: 2〜8 人. 最後の 1 人.
        case battleRoyale = 2
    }

    var kind: Kind
    var playerCount: Int
    /// 始めの円(戦う場所)の半径. バトルロイヤルの 5 人以上は島全体.
    var arenaRadius: Float
    /// バトルロイヤルで, 島全体(`MapData.spawns` を使う)か.
    var islandWide: Bool
    var startShield: Int
    var respawns: Bool
    var respawnDelay: Double = 3
    var respawnInvulnerable: Double = 2
    /// ラウンド戦: 全員 同じ武器の組で始める.
    var sharedLoadout: Bool
    var lootHasWeapons: Bool
    /// ひろった物が また出るまで(nil = 出ない).
    var lootRespawnDelay: Double?
    var winScore: Int
    var maxRounds: Int
    var killTarget: Int
    var timeLimit: Double?
    var stages: [ZoneStage]
    /// 段階の無いルールで, 円の外に出たときのダメージ.
    var outsideDPS: Int
    /// 円の外の出発点の並べ方(半径 × この割合の円の上).
    var spawnFraction: Float
    /// 円の中に必要な置き場の数(バトルロイヤル小で場所を選ぶとき).
    var minLootInArena: Int

    /// ラウンドのあいだ(秒)と, 始まる前のカウントダウン(秒).
    static let betweenRounds: Double = 4
    static let firstCountdown: Double = 5
    static let laterCountdown: Double = 3

    static func defaultKind(playerCount: Int) -> Kind { playerCount <= 4 ? .roundBattle : .battleRoyale }

    static func make(kind: Kind, playerCount n: Int) -> GameMode {
        switch kind {
        case .roundBattle:
            return GameMode(kind: kind, playerCount: n, arenaRadius: 60, islandWide: false, startShield: 25, respawns: false,
                            sharedLoadout: true, lootHasWeapons: false, lootRespawnDelay: nil, winScore: 3, maxRounds: 12,
                            killTarget: 0, timeLimit: nil,
                            stages: [ZoneStage(wait: 25, shrink: 35, endFraction: 10.0 / 60, dps: 5),
                                     ZoneStage(wait: 10, shrink: 15, endFraction: 0, dps: 12)],
                            outsideDPS: 0, spawnFraction: 0.85, minLootInArena: 6)
        case .killRace:
            return GameMode(kind: kind, playerCount: n, arenaRadius: 80, islandWide: false, startShield: 0, respawns: true,
                            sharedLoadout: false, lootHasWeapons: true, lootRespawnDelay: 20, winScore: 0, maxRounds: 1,
                            killTarget: n <= 2 ? 10 : 15, timeLimit: 300, stages: [], outsideDPS: 5, spawnFraction: 0.85,
                            minLootInArena: 6)
        case .battleRoyale:
            let big = n >= 5
            let radius: Float = big ? 210 : (n == 2 ? 90 : 120)
            let stages: [ZoneStage]
            if big {
                stages = [ZoneStage(wait: 45, shrink: 30, endFraction: 120.0 / 210, dps: 2),
                          ZoneStage(wait: 30, shrink: 30, endFraction: 70.0 / 210, dps: 4),
                          ZoneStage(wait: 25, shrink: 25, endFraction: 35.0 / 210, dps: 7),
                          ZoneStage(wait: 20, shrink: 20, endFraction: 12.0 / 210, dps: 10),
                          ZoneStage(wait: 15, shrink: 20, endFraction: 0, dps: 15)]
            } else {
                stages = [ZoneStage(wait: 30, shrink: 25, endFraction: 120.0 / 210, dps: 2),
                          ZoneStage(wait: 20, shrink: 20, endFraction: 70.0 / 210, dps: 4),
                          ZoneStage(wait: 20, shrink: 20, endFraction: 35.0 / 210, dps: 7),
                          ZoneStage(wait: 15, shrink: 15, endFraction: 12.0 / 210, dps: 10),
                          ZoneStage(wait: 10, shrink: 15, endFraction: 0, dps: 15)]
            }
            return GameMode(kind: kind, playerCount: n, arenaRadius: radius, islandWide: big, startShield: 0, respawns: false,
                            sharedLoadout: false, lootHasWeapons: true, lootRespawnDelay: nil, winScore: 0, maxRounds: 1,
                            killTarget: 0, timeLimit: nil, stages: stages, outsideDPS: 0, spawnFraction: big ? 0.85 : 0.9,
                            minLootInArena: big ? 0 : (n == 2 ? 12 : 16))
        }
    }

    /// ラウンド戦の武器の組(`loadoutSet` 1〜5. 0 = ハンドガンだけ).
    static let roundBattleSets: [[WeaponKind?]] = [
        [.assaultRifle, .handgun],
        [.shotgun, .handgun],
        [.sniper, .handgun],
        [.assaultRifle, .shotgun],
        [.handgun, nil],
    ]

    /// その組で始めるときの武器.
    static func weapons(forSet set: Int) -> [WeaponKind?] {
        guard set >= 1, set <= roundBattleSets.count else { return [.handgun, nil] }
        return roundBattleSets[set - 1]
    }

    var totalZoneDuration: Float { stages.reduce(0) { $0 + $1.wait + $1.shrink } }
}
