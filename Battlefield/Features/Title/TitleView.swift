import SwiftUI

/// タイトル: 「オンライン対戦」「れんしゅう」「せってい」.
struct TitleView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            SkyBackground()
            VStack(spacing: 22) {
                VStack(spacing: 4) {
                    Text("石油王バトル")
                        .font(Theme.font(54))
                        .foregroundStyle(Theme.ink)
                    Text("(仮の名前)")
                        .font(Theme.font(14, .bold))
                        .foregroundStyle(Theme.ink.opacity(0.6))
                }
                HStack(spacing: 20) {
                    Button { model.startOnline() } label: {
                        Label("オンライン対戦", systemImage: "person.2.wave.2.fill")
                    }
                    .buttonStyle(PaperButtonStyle(color: Theme.coral, size: 26))
                    .disabled(!model.auth.canPlayOnline)
                    .opacity(model.auth.canPlayOnline ? 1 : 0.5)

                    Button { model.screen = .practice } label: {
                        Label("れんしゅう", systemImage: "figure.run")
                    }
                    .buttonStyle(PaperButtonStyle(color: Theme.sky, size: 26))
                }
                statusLine
                Button { model.screen = .settings } label: {
                    Label("せってい", systemImage: "gearshape.fill")
                }
                .buttonStyle(PaperButtonStyle(color: Theme.leaf, size: 18))
            }
            .paperPanel(padding: 30, corner: 28)
        }
    }

    @ViewBuilder private var statusLine: some View {
        switch model.auth.state {
        case .checking:
            Text("Game Center を確かめています…").font(Theme.font(14, .bold)).foregroundStyle(Theme.ink.opacity(0.6))
        case .signedIn:
            Text("\(model.auth.displayName) でログイン中").font(Theme.font(14, .bold)).foregroundStyle(Theme.leaf)
        case .signedOut, .restricted:
            Text(model.auth.message ?? "オンライン対戦は使えません").font(Theme.font(13, .bold))
                .foregroundStyle(Theme.coral).multilineTextAlignment(.center).frame(maxWidth: 420)
        }
    }
}
