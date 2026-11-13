import SwiftUI

/// 石油王バトル(仮の名前). 友だちと撃ち合う 3D シューティング.
/// 画面は SwiftUI, 3D は RealityKit, ルール・動き・通信の中身は `Core/`(描画から独立).
@main
struct BattlefieldApp: App {
    var body: some Scene {
        WindowGroup {
            TitleView()
                .preferredColorScheme(.light)
                .statusBarHidden()
                .persistentSystemOverlays(.hidden)
        }
    }
}
