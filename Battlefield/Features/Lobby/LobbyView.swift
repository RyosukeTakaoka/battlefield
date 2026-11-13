import SwiftUI

/// ロビー(オンライン): 集まった人の名簿. ホストだけが ルールをえらんで「はじめる」.
struct LobbyView: View {
    @Bindable var controller: BattleController

    private var humans: Int { controller.lobbyPlayers.count }
    private var total: Int { humans + controller.lobbyBots }
    private var kindAllowed: Bool {
        switch controller.lobbyKind {
        case .roundBattle, .killRace: return total <= 4
        case .battleRoyale: return total <= GameRules.maxPlayers
        }
    }
    private var canStart: Bool { total >= 2 && kindAllowed }

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 14) {
                Text("ロビー").font(Theme.font(30)).foregroundStyle(Theme.ink)
                Text("\(humans) 人 + ボット \(controller.lobbyBots) 体(最大 \(GameRules.maxPlayers) 人)")
                    .font(Theme.font(13, .bold)).foregroundStyle(Theme.ink.opacity(0.6))
                ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(controller.lobbyPlayers.enumerated()), id: \.offset) { _, p in
                        HStack(spacing: 8) {
                            Image(systemName: p.isHost ? "crown.fill" : "person.fill")
                                .foregroundStyle(p.isHost ? Theme.gold : Theme.ink.opacity(0.5))
                            Text(p.name + (p.isMe ? "(あなた)" : "")).font(Theme.font(18))
                            Spacer()
                            if p.isHost { Text("ホスト").font(Theme.font(12, .bold)).foregroundStyle(Theme.ink.opacity(0.6)) }
                        }
                    }
                    if controller.lobbyBots > 0 {
                        Text("+ ボット \(controller.lobbyBots) 体").font(Theme.font(15, .bold)).foregroundStyle(Theme.ink.opacity(0.6))
                    }
                }
                .foregroundStyle(Theme.ink)
                .frame(width: 330)
                }
                .frame(maxHeight: 190)

                if controller.isHost {
                    Picker("ルール", selection: $controller.lobbyKind) {
                        ForEach(GameMode.Kind.allCases, id: \.rawValue) { k in Text(PracticeSetupView.title(k)).tag(k) }
                    }
                    .pickerStyle(.segmented).frame(width: 360)
                    Stepper("ボット \(controller.lobbyBots) 体", value: $controller.lobbyBots, in: 0...max(0, GameRules.maxPlayers - humans))
                        .font(Theme.font(16)).foregroundStyle(Theme.ink).frame(width: 260)
                    if !kindAllowed {
                        Text("このルールは 4 人までです").font(Theme.font(13, .bold)).foregroundStyle(Theme.coral)
                    } else if total < 2 {
                        Text("あと 1 人 (またはボット) が必要です").font(Theme.font(13, .bold)).foregroundStyle(Theme.coral)
                    }
                    Button { controller.hostStart() } label: { Label("はじめる", systemImage: "play.fill") }
                        .buttonStyle(PaperButtonStyle(color: Theme.coral, size: 24))
                        .disabled(!canStart).opacity(canStart ? 1 : 0.5)
                } else {
                    Text("ホストが はじめるのを待っています…").font(Theme.font(16, .bold)).foregroundStyle(Theme.ink.opacity(0.7))
                }
                Button("やめる") { controller.leave() }.buttonStyle(PaperButtonStyle(color: Theme.sky, size: 17))
            }
            .paperPanel(padding: 24, corner: 26)
            .onAppear { applyDefaultKind() }
            .onChange(of: humans) { _, _ in applyDefaultKind() }
        }
    }

    /// 何もえらばなければ: 2〜4 人 = ラウンド戦, 5 人以上 = バトルロイヤル.
    private func applyDefaultKind() {
        if total > 4 { controller.lobbyKind = .battleRoyale }
    }
}
