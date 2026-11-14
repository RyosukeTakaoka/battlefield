import SwiftUI

/// 設定: 視点の感度・上下反対・左きき・音・画質・名前.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ZStack {
            SkyBackground()
            VStack(spacing: 12) {
                HStack {
                    BackButton { model.saveSettings(); model.screen = .title }
                    Spacer()
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("せってい").font(Theme.font(32))
                        row("視点の感度  \(String(format: "%.1f", model.settings.lookSensitivity))") {
                            Slider(value: $model.settings.lookSensitivity, in: 0.5...2.0, step: 0.1)
                        }
                        Toggle("ねらいの助け(照準の近くの敵へ 弾を寄せる)", isOn: $model.settings.aimAssist)
                        Toggle("視点の上下を反対にする", isOn: $model.settings.invertY)
                        Toggle("左きき(ボタンを左に)", isOn: $model.settings.leftHanded)
                        row("音の大きさ") { Slider(value: $model.settings.soundVolume, in: 0...1) }
                        row("画質(つぎの試合から)") {
                            Picker("画質", selection: $model.settings.quality) {
                                ForEach(GameSettings.Quality.allCases) { q in Text(q.label).tag(q) }
                            }
                            .pickerStyle(.segmented)
                        }
                        row("名前(空なら Game Center の名前)") {
                            TextField("名前", text: $model.settings.playerName).textFieldStyle(.roundedBorder).frame(maxWidth: 280)
                        }
                        Toggle("通信のようすを画面に出す(確かめる用)", isOn: $model.settings.showNetStats)
                    }
                    .font(Theme.font(17, .bold)).foregroundStyle(Theme.ink)
                    .paperPanel(padding: 22).frame(maxWidth: 520)
                }
            }
            .padding(16)
        }
        .onChange(of: model.settings) { _, _ in model.saveSettings() }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            content()
        }
    }
}
