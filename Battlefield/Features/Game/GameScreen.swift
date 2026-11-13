import SwiftUI

/// ゲーム画面: 3D の景色 + 指の操作 + 数字の表示 + ロビー・結果・切断のパネル.
struct GameScreen: View {
    @Environment(AppModel.self) private var model
    let controller: BattleController
    @State private var confirmLeave = false

    private var inMatch: Bool { controller.phase == .match }

    var body: some View {
        ZStack {
            GameView(controller: controller).ignoresSafeArea()

            if controller.loadState == .ready {
                if inMatch {
                    TouchControlsView(controller: controller).ignoresSafeArea()
                    ControlButtonsOverlay(controller: controller, leftHanded: model.settings.leftHanded,
                                          showInteract: controller.hud.pickupPrompt != nil)
                    HUDView(controller: controller)
                    leaveButton
                }
                switch controller.phase {
                case .connecting:
                    StatusPanel(text: "つながっています…", showLeave: true, controller: controller)
                case .lobby:
                    LobbyView(controller: controller)
                case .finished:
                    ResultView(controller: controller)
                case .disconnected(let text):
                    StatusPanel(text: text, showLeave: true, controller: controller)
                case .loading, .match:
                    EmptyView()
                }
            }
            loadingLayer
        }
        .task { await controller.load() }
        .confirmationDialog("試合をやめますか?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("やめる", role: .destructive) { controller.leave() }
            Button("つづける", role: .cancel) {}
        }
    }

    private var leaveButton: some View {
        VStack {
            HStack {
                Spacer()
                Button { confirmLeave = true } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .heavy)).foregroundStyle(.white)
                        .frame(width: 34, height: 34).background(Circle().fill(.black.opacity(0.45)))
                }
            }
            .padding(.trailing, 14).padding(.top, 150)
            Spacer()
        }
    }

    @ViewBuilder private var loadingLayer: some View {
        switch controller.loadState {
        case .loading(let p):
            ZStack {
                SkyBackground()
                VStack(spacing: 14) {
                    Text("島をつくっています…").font(Theme.font(26)).foregroundStyle(Theme.ink)
                    ProgressView(value: p).frame(width: 260).tint(Theme.coral)
                }
                .paperPanel(padding: 26)
            }
        case .failed(let message):
            ZStack {
                SkyBackground()
                VStack(spacing: 14) {
                    Text("読み込めませんでした").font(Theme.font(24)).foregroundStyle(Theme.coral)
                    Text(message).font(Theme.font(13, .bold)).foregroundStyle(Theme.ink)
                    Button("もどる") { controller.leave() }.buttonStyle(PaperButtonStyle(color: Theme.sky, size: 20))
                }
                .paperPanel(padding: 26)
            }
        case .ready:
            EmptyView()
        }
    }
}

/// 「つながっています」「通信が切れました」など 1 行のパネル.
struct StatusPanel: View {
    let text: String
    let showLeave: Bool
    let controller: BattleController

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 16) {
                Text(text).font(Theme.font(22)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
                if showLeave {
                    Button("もどる") { controller.leave() }.buttonStyle(PaperButtonStyle(color: Theme.sky, size: 20))
                }
            }
            .paperPanel(padding: 26)
            .frame(maxWidth: 480)
        }
    }
}
