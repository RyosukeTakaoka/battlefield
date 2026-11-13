import Foundation

/// 1 コマぶんの入力(指やコントローラーから `TouchLayout` などが作る).
struct PlayerInput: Equatable {
    /// 右が +, 前が + (長さ 1 まで).
    var moveX: Float = 0
    var moveY: Float = 0
    /// 向き(絶対値). 0 で -Z, 時計回り(右へ)が +.
    var yaw: Float = 0
    /// 上向きが +.
    var pitch: Float = 0
    /// このコマでジャンプを押した.
    var jump = false
    /// 構えている(ズーム).
    var aiming = false
    /// 撃つボタンを押している.
    var fire = false
    var reload = false
    /// このコマで武器の切りかえを押した.
    var switchWeapon = false
    /// このコマで「もちかえる」を押した.
    var interact = false
}
