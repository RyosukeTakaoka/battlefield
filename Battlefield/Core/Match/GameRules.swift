import Foundation

/// ゲームの数字を 1 か所にまとめたもの(`docs/DESIGN.md` の表と同じ).
/// 数字を変えたら, 設計書の表も同じコミットで直すこと.
enum GameRules {
    // MARK: 試合
    /// このゲームが耐えられる人数(Game Center の上限 16 人に合わせた. 実際の上限は起動時に Game Center に聞き, 小さい方を使う).
    static let maxPlayers = 16
    /// 物理を進める固定の刻み(秒).
    static let tick: Float = 1.0 / 60

    // MARK: ねらいの助け(`AimAssist`)
    /// 照準からこの角度(度)までの敵へ 弾を引きよせる.
    static let aimAssistDegrees: Float = 3
    /// ただし 遠いときは 「照準から横に この長さ(m)」まで(遠くの敵を勝手に当てないため).
    static let aimAssistRadius: Float = 0.9
    /// 照準が敵の近く(この角度. 度)にあるあいだ, 視点の動きを この割合にする.
    static let aimFrictionDegrees: Float = 4
    static let aimFriction: Float = 0.5

    // MARK: ホストの確かめ
    /// 当たりの申し出が かたまって届いてもよい数(`HostLogic` の連射の確かめ).
    static let claimBurst = 3

    // MARK: 体力
    static let maxHP = 100
    static let maxShield = 50

    // MARK: プレイヤーの体と動き
    static let playerRadius: Float = 0.4
    static let playerHeight: Float = 1.8
    /// 目の高さ.
    static let eyeHeight: Float = 1.6
    static let runSpeed: Float = 6.0
    /// 構えているときの速さ.
    static let aimSpeed: Float = 3.5
    static let jumpSpeed: Float = 6.5
    static let gravity: Float = 18
    /// 空中で横の操作がどれだけ効くか(0〜1. 1 秒あたり 10 倍して近づく割合にする).
    static let airControl: Float = 0.3
    /// 登れる坂: 地面の法線の y がこれ以上.
    static let walkableNormalY: Float = 0.62
    /// そのまま乗り越えられる段差の高さ.
    static let stepHeight: Float = 0.5
    /// 地面がこれより低い所(水)には入れない.
    static let minGroundY: Float = -1.0
    /// 下り坂で地面にはりつく距離.
    static let groundSnap: Float = 0.3
    /// 落ちたらやられる高さ(島の外へ出たときのための保険).
    static let killY: Float = -30
}
