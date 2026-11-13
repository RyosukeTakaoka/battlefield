import GameKit
import Observation
import SwiftUI

/// 画面の行き来と, 試合の始まり・終わり(Airplane の `AppModel` と同じ役目).
@MainActor
@Observable
final class AppModel {
    enum Screen: Equatable {
        case title
        case practice
        case game
        case settings
    }

    var screen: Screen = .title
    var settings = GameSettings.load()
    let auth = GameCenterAuth()
    @ObservationIgnored let matchmaking = Matchmaking()
    private(set) var game: BattleController?
    /// 画面に出す お知らせ(エラーなど).
    var notice: String?

    private var launched = false

    func onLaunch() {
        guard !launched else { return }
        launched = true
        auth.onSignedIn = { [weak self] in self?.matchmaking.registerInviteListener() }
        matchmaking.onMatch = { [weak self] match in self?.beginOnline(match: match) }
        matchmaking.onError = { [weak self] text in self?.notice = text }
        auth.start()
    }

    func saveSettings() { settings.save() }

    var playerName: String { settings.playerName.isEmpty ? auth.displayName : settings.playerName }

    // MARK: - 試合を始める

    /// 「れんしゅう」: 自分がホストで, 相手は全部ボット.
    func startPractice(kind: GameMode.Kind, bots: Int) {
        guard game == nil else { return }
        settings.practiceKindRaw = Int(kind.rawValue)
        settings.practiceBots = bots
        saveSettings()
        let controller = BattleController(mode: .practice(kind: kind, bots: bots, difficulty: settings.botDifficulty),
                                          settings: settings, playerName: playerName)
        present(controller)
    }

    /// 「オンライン対戦」: Game Center の人あつめの画面を出す. 人がそろったら `beginOnline`.
    func startOnline() {
        guard game == nil, auth.canPlayOnline else { return }
        matchmaking.present()
    }

    private func beginOnline(match: GKMatch) {
        guard game == nil else {
            match.disconnect()
            return
        }
        let transport = GameKitTransport(match: match)
        let controller = BattleController(mode: .online, settings: settings, playerName: playerName, transport: transport)
        present(controller)
    }

    private func present(_ controller: BattleController) {
        controller.onExit = { [weak self] in self?.exitGame() }
        game = controller
        screen = .game
    }

    private func exitGame() {
        game = nil
        screen = .title
    }
}
