import Foundation

/// 設定画面で変えられる値. UserDefaults に JSON で保存する(Airplane と同じ方式).
struct GameSettings: Codable, Equatable {
    enum Quality: String, Codable, CaseIterable, Identifiable {
        case high
        case standard
        var id: String { rawValue }
        var label: String { self == .high ? "きれい" : "かるい" }
    }

    var quality: Quality = .high
    /// 視点の感度(0.5〜2.0).
    var lookSensitivity: Double = 1.0
    var invertY = false
    var leftHanded = false
    var soundVolume: Double = 0.8
    /// 空なら Game Center の名前を使う.
    var playerName = ""
    /// 「れんしゅう」で最後にえらんだルール(`GameMode.Kind.rawValue`)・ボットの数・強さ(0 やさしい / 1 ふつう / 2 つよい).
    var practiceKindRaw = 0
    var practiceBots = 3
    var botLevel = 1
    /// 通信のようす(人数・時計のずれ)を画面に出す(確かめる用).
    var showNetStats = false
    /// ねらいの助け(照準の近くの敵へ 弾を引きよせる・視点を少し遅くする).
    var aimAssist = true

    var practiceKind: GameMode.Kind { GameMode.Kind(rawValue: UInt8(practiceKindRaw)) ?? .roundBattle }

    var botDifficulty: BotDifficulty {
        switch botLevel {
        case 0: return .easy
        case 2: return .hard
        default: return .normal
        }
    }

    private static let key = "Battlefield.settings"

    init() {}

    /// 新しい項目が無い保存も読めるように, 無い項目は既定の値にする.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GameSettings()
        quality = try c.decodeIfPresent(Quality.self, forKey: .quality) ?? d.quality
        lookSensitivity = try c.decodeIfPresent(Double.self, forKey: .lookSensitivity) ?? d.lookSensitivity
        invertY = try c.decodeIfPresent(Bool.self, forKey: .invertY) ?? d.invertY
        leftHanded = try c.decodeIfPresent(Bool.self, forKey: .leftHanded) ?? d.leftHanded
        soundVolume = try c.decodeIfPresent(Double.self, forKey: .soundVolume) ?? d.soundVolume
        playerName = try c.decodeIfPresent(String.self, forKey: .playerName) ?? d.playerName
        practiceKindRaw = try c.decodeIfPresent(Int.self, forKey: .practiceKindRaw) ?? d.practiceKindRaw
        practiceBots = try c.decodeIfPresent(Int.self, forKey: .practiceBots) ?? d.practiceBots
        botLevel = try c.decodeIfPresent(Int.self, forKey: .botLevel) ?? d.botLevel
        showNetStats = try c.decodeIfPresent(Bool.self, forKey: .showNetStats) ?? d.showNetStats
        aimAssist = try c.decodeIfPresent(Bool.self, forKey: .aimAssist) ?? d.aimAssist
    }

    static func load() -> GameSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(GameSettings.self, from: data) else { return GameSettings() }
        return s
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}
