import Foundation

/// 1 人の体の状態(位置・速さ・向き). HP やシールドは `MatchState` が持つ.
struct PlayerState: Equatable {
    /// 足もと.
    var position: Vec3
    var velocity: Vec3 = .zero
    /// 向き(0 で -Z, 時計回りが +).
    var yaw: Float = 0
    /// 上向きが +.
    var pitch: Float = 0
    var isGrounded = false

    init(position: Vec3, yaw: Float = 0) {
        self.position = position
        self.yaw = yaw
    }

    /// 前向きの水平な単位ベクトル.
    var forward: Vec3 { Vec3(sin(yaw), 0, -cos(yaw)) }
    /// 右向きの水平な単位ベクトル.
    var right: Vec3 { Vec3(cos(yaw), 0, sin(yaw)) }
    /// 目の位置.
    var eye: Vec3 { position + Vec3(0, GameRules.eyeHeight, 0) }
    /// 視線の向き(pitch まで含める).
    var lookDirection: Vec3 {
        let c = cos(pitch)
        return Vec3(sin(yaw) * c, sin(pitch), -cos(yaw) * c)
    }
}
