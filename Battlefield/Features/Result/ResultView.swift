import SwiftUI

/// 結果: 順位・キル・取ったラウンド. ホストは「もう一度」.
struct ResultView: View {
    let controller: BattleController

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            if let r = controller.result {
                VStack(spacing: 12) {
                    Text(r.iWon ? "勝ち!" : (r.winnerName.map { "\($0) の勝ち" } ?? "おしまい"))
                        .font(Theme.font(42)).foregroundStyle(r.iWon ? Theme.gold : Theme.ink)
                    Text(r.modeText).font(Theme.font(14, .bold)).foregroundStyle(Theme.ink.opacity(0.6))
                    ScrollView {
                    VStack(spacing: 6) {
                        ForEach(r.rows) { row in
                            HStack(spacing: 10) {
                                Text("\(row.placement) 位").font(Theme.font(18)).frame(width: 52, alignment: .leading)
                                Circle().fill(Color(uiColor: CharacterRig.colors[row.id % CharacterRig.colors.count])).frame(width: 12, height: 12)
                                Text(row.name + (row.isMe ? "(あなた)" : "")).font(Theme.font(17)).lineLimit(1)
                                Spacer()
                                Label("\(row.kills)", systemImage: "scope").font(Theme.font(15, .bold))
                                if r.modeText == "ラウンド戦" { Text("\(row.score) 点").font(Theme.font(15, .bold)) }
                            }
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 10).fill(row.isMe ? Theme.gold.opacity(0.3) : .clear))
                        }
                    }
                    .foregroundStyle(Theme.ink).frame(width: 380)
                    }
                    .frame(maxHeight: 230)
                    HStack(spacing: 16) {
                        if controller.isHost {
                            Button { controller.rematch() } label: { Label("もう一度", systemImage: "arrow.clockwise") }
                                .buttonStyle(PaperButtonStyle(color: Theme.coral, size: 22))
                        } else {
                            Text("ホストの「もう一度」を待っています").font(Theme.font(13, .bold)).foregroundStyle(Theme.ink.opacity(0.6))
                        }
                        Button("やめる") { controller.leave() }.buttonStyle(PaperButtonStyle(color: Theme.sky, size: 20))
                    }
                }
                .paperPanel(padding: 24, corner: 26)
            }
        }
    }
}
