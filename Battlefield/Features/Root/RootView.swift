import SwiftUI

/// 画面の切り替え. どの画面を出すかは `AppModel.screen` で決まる.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            switch model.screen {
            case .title:
                TitleView().transition(.opacity)
            case .practice:
                PracticeSetupView().transition(.move(edge: .trailing).combined(with: .opacity))
            case .game:
                if let game = model.game {
                    GameScreen(controller: game)
                        .id(ObjectIdentifier(game))
                        .transition(.opacity)
                }
            case .settings:
                SettingsView().transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: model.screen)
        .alert("お知らせ", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.notice ?? "")
        }
    }
}
