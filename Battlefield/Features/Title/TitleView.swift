import SwiftUI

/// 文字だけのタイトル画面(M0). 「れんしゅう」と「オンライン対戦」は M3 / M7 でつなぐ.
struct TitleView: View {
    var body: some View {
        ZStack {
            Theme.sky.ignoresSafeArea()
            VStack(spacing: 18) {
                Text("石油王バトル")
                    .font(Theme.font(44))
                    .foregroundStyle(Theme.ink)
                Text("(仮の名前)")
                    .font(Theme.font(16, .bold))
                    .foregroundStyle(Theme.ink.opacity(0.7))
            }
            .paperPanel(padding: 28)
        }
    }
}
