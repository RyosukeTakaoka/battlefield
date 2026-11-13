import SwiftUI

/// 「れんしゅう」: ルール・ボットの数・強さをえらぶ(通信なし. 自分がホストで 相手は全部ボット).
struct PracticeSetupView: View {
    @Environment(AppModel.self) private var model
    @State private var kind: GameMode.Kind = .roundBattle
    @State private var bots = 3
    @State private var level = 1

    private var botRange: ClosedRange<Int> {
        switch kind {
        case .roundBattle, .killRace: return 1...3        // 自分を入れて 2〜4 人
        case .battleRoyale: return 1...(GameRules.maxPlayers - 1)     // 2〜16 人
        }
    }

    var body: some View {
        ZStack {
            SkyBackground()
            VStack(spacing: 16) {
                HStack {
                    BackButton { model.screen = .title }
                    Spacer()
                }
                Text("れんしゅう").font(Theme.font(34)).foregroundStyle(Theme.ink)
                HStack(spacing: 12) {
                    ForEach(GameMode.Kind.allCases, id: \.rawValue) { k in
                        Button { kind = k; bots = min(max(bots, botRange.lowerBound), botRange.upperBound) } label: {
                            VStack(spacing: 4) {
                                Text(Self.title(k)).font(Theme.font(20))
                                Text(Self.detail(k)).font(Theme.font(12, .bold)).opacity(0.8)
                            }
                            .frame(width: 190, height: 84)
                            .foregroundStyle(kind == k ? .white : Theme.ink)
                            .background(RoundedRectangle(cornerRadius: 16).fill(kind == k ? Theme.coral : Theme.paper))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.ink, lineWidth: 2.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack(spacing: 24) {
                    Stepper("ボット \(bots) 体", value: $bots, in: botRange).font(Theme.font(18)).frame(width: 220)
                    Picker("強さ", selection: $level) {
                        Text("やさしい").tag(0)
                        Text("ふつう").tag(1)
                        Text("つよい").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 280)
                }
                .foregroundStyle(Theme.ink)
                Button {
                    model.settings.botLevel = level
                    model.startPractice(kind: kind, bots: bots)
                } label: {
                    Label("はじめる", systemImage: "play.fill")
                }
                .buttonStyle(PaperButtonStyle(color: Theme.coral, size: 26))
            }
            .paperPanel(padding: 24, corner: 28)
            .padding(.horizontal, 20)
        }
        .onAppear {
            kind = model.settings.practiceKind
            level = model.settings.botLevel
            bots = min(max(model.settings.practiceBots, botRange.lowerBound), botRange.upperBound)
        }
    }

    static func title(_ k: GameMode.Kind) -> String {
        switch k {
        case .roundBattle: return "ラウンド戦"
        case .killRace: return "キル勝負"
        case .battleRoyale: return "バトルロイヤル"
        }
    }

    static func detail(_ k: GameMode.Kind) -> String {
        switch k {
        case .roundBattle: return "2〜4 人・先に 3 ラウンド"
        case .killRace: return "2〜4 人・復活あり"
        case .battleRoyale: return "2〜16 人・最後の 1 人"
        }
    }
}
