import Foundation

// 通信のメッセージ(`docs/NETCODE.md` §4). ここでは Swift の値. バイト列への変換は `Net/Messages.swift`.

struct HelloMessage: Equatable {
    var protocolVersion: UInt8
    var peerKey: UInt64
    var name: String
}

/// 開始のメッセージにある, 参加者 1 人ぶん.
struct PlayerSlotInfo: Equatable {
    var slot: Int
    /// ボットは 0.
    var peerKey: UInt64
    var isBot: Bool
    var score: Int
    var spawn: Vec3
    var spawnYaw: Float
    var name: String
}

struct LootSpawn: Equatable {
    var id: Int
    var kind: LootKind
}

struct StartRoundMessage: Equatable {
    var matchId: UInt32
    var round: Int
    var mode: GameMode.Kind
    var mapId: Int
    /// ホストの時計(秒)で, この時刻に試合の時計が 0 になる(= 戦い始め).
    var startAt: Double
    var arena: Circle
    /// 0 = ハンドガンだけ, 1〜5 = ラウンド戦の武器の組.
    var loadoutSet: Int
    var players: [PlayerSlotInfo]
    var zones: [Circle]
    var loot: [LootSpawn]
}

/// 自分の状態(信頼なし. 1 秒に 20 回).
struct PlayerStateMessage: Equatable {
    var slot: Int
    var seq: UInt16
    /// 送った人の「ホストの時計」(ms).
    var timeMs: UInt32
    var position: Vec3
    var yaw: Float
    var pitch: Float
    var velocity: Vec3
    var flags: PlayerFlags
    var weapon: WeaponKind
}

struct PlayerFlags: OptionSet, Equatable {
    let rawValue: UInt8
    static let grounded = PlayerFlags(rawValue: 1 << 0)
    static let firing = PlayerFlags(rawValue: 1 << 1)
    static let reloading = PlayerFlags(rawValue: 1 << 2)
    static let aiming = PlayerFlags(rawValue: 1 << 3)
    static let alive = PlayerFlags(rawValue: 1 << 4)
}

struct ShotFxMessage: Equatable {
    struct Shot: Equatable {
        var end: Vec3
        /// 0 何にも / 1 地面 / 2 障害物 / 3 人
        var hitKind: UInt8
    }
    var slot: Int
    var weapon: WeaponKind
    var origin: Vec3
    var shots: [Shot]
}

struct HitClaimMessage: Equatable {
    var shotId: UInt16
    var attacker: Int
    var target: Int
    var weapon: WeaponKind
    var head: Bool
    var pellets: Int
    var distance: Float
}

struct DamageMessage: Equatable {
    /// 円のダメージ.
    static let zoneAttacker = 255
    /// 切断(やられた扱い).
    static let disconnectAttacker = 254

    var round: Int
    var target: Int
    var attacker: Int
    var weapon: WeaponKind?
    /// ダメージのあとの「今の値」.
    var hp: Int
    var shield: Int
    var head: Bool
    var killed: Bool
    /// このあと生きている人数.
    var alive: Int
}

struct VitalsMessage: Equatable {
    var round: Int
    var slot: Int
    var hp: Int
    var shield: Int
}

struct RespawnMessage: Equatable {
    var round: Int
    var slot: Int
    var position: Vec3
    var yaw: Float
    /// ホストの時計(秒). この時刻に生き返る.
    var atTime: Double
}

struct PickupRequestMessage: Equatable {
    var lootId: Int
    var slot: Int
}

struct LootTakenMessage: Equatable {
    var round: Int
    var lootId: Int
    var slot: Int
}

struct LootRestoredMessage: Equatable {
    var round: Int
    var lootId: Int
    var kind: LootKind
}

struct RoundEndMessage: Equatable {
    struct Result: Equatable {
        var placement: Int
        var kills: Int
        var score: Int
    }
    var matchId: UInt32
    var round: Int
    var winner: Int?
    var final: Bool
    /// slot 順.
    var results: [Result]
}

struct HostSnapshotMessage: Equatable {
    struct Player: Equatable {
        var hp: Int
        var shield: Int
        var kills: Int
        /// 0 = 生きている.
        var placement: Int
        var score: Int
    }
    var matchId: UInt32
    var round: Int
    var hostEpoch: Int
    var phase: MatchPhase
    var players: [Player]
    /// ひろうものの取られた印(startRound の loot の順).
    var lootTaken: [Bool]
}

enum Message: Equatable {
    case hello(HelloMessage)
    case startRound(StartRoundMessage)
    case playerState(PlayerStateMessage)
    case shotFx(ShotFxMessage)
    case ping(clientMs: UInt32)
    case pong(clientMs: UInt32, hostMs: UInt32)
    case hitClaim(HitClaimMessage)
    case damage(DamageMessage)
    case vitals(VitalsMessage)
    case respawn(RespawnMessage)
    case pickupRequest(PickupRequestMessage)
    case lootTaken(LootTakenMessage)
    case lootRestored(LootRestoredMessage)
    case roundEnd(RoundEndMessage)
    case hostSnapshot(HostSnapshotMessage)
    case leave(slot: Int)

    /// ホストだけが出してよい種類.
    var isHostOnly: Bool {
        switch self {
        case .startRound, .damage, .vitals, .respawn, .lootTaken, .lootRestored, .roundEnd, .hostSnapshot, .pong: return true
        default: return false
        }
    }

    /// かならず届いてほしい種類(信頼あり).
    var isReliable: Bool {
        switch self {
        case .playerState, .shotFx, .ping, .pong: return false
        default: return true
        }
    }
}
