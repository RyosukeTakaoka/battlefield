import Foundation

/// 画面の指の動きを「移動・視点・ボタン」に分ける(`docs/DESIGN.md` §3「Input」). UIKit を知らない.
///
/// - ボタンの上で始まった指 = そのボタン(撃つボタンは, 押したまま動かすと視点も動く)
/// - 画面の左半分で始まった指 = 移動スティック(さわった所が中心. `stickRadius` で最大)
/// - 右半分 = 視点(動いた量 × 感度). 左ききの設定では 左右が入れかわる
/// 指は 1 本ずつ id で追うので, 2 本・3 本を同時に使える.
struct TouchLayout {
    enum Button: CaseIterable, Hashable {
        case fire, aim, jump, reload, switchWeapon, interact
    }

    struct Point: Equatable {
        var x: Float
        var y: Float
    }

    struct ButtonSpec: Equatable {
        var button: Button
        var center: Point
        /// 見た目の半径. 押せる範囲は これの `hitScale` 倍(少し大きめで, 押しやすく).
        var radius: Float
    }

    /// 画面のはしの「安全な範囲」の外側の幅(ノッチ・角の丸み・ホームバー). ボタンはこの内側に置く.
    struct Insets: Equatable {
        var left: Float = 0
        var right: Float = 0
        var top: Float = 0
        var bottom: Float = 0
    }

    private enum Role: Equatable {
        case move(origin: Point)
        case look(last: Point)
        case button(Button, last: Point)
    }

    var screenWidth: Float
    var screenHeight: Float
    var insets = Insets()
    var leftHanded = false
    /// 視点: 1 pt 動かしたとき何ラジアン回るか(設定の感度をかけたもの).
    var lookSensitivity: Float = 0.006
    var invertY = false
    var stickRadius: Float = 60
    /// スティックの まん中の 遊び(この割合より小さい傾きは 0).
    var stickDeadZone: Float = 0.12
    /// 押せる範囲 = 見た目の半径 × これ.
    var hitScale: Float = 1.3
    /// 「もちかえる」ボタンを出しているか(出していないときは 押せない. その場所は 視点の指になる).
    var showsInteract = false

    private var touches: [Int: Role] = [:]
    private var stick = Point(x: 0, y: 0)
    private var lookYaw: Float = 0
    private var lookPitch: Float = 0
    private var pressedEdges: Set<Button> = []

    init(width: Float, height: Float) {
        screenWidth = width
        screenHeight = height
    }

    /// ボタンの置き場所(安全な範囲の内側. 右ききは右下, 左ききは左下に撃つボタン).
    /// 数字は「はしから何 pt」. 親指が届く扇の形に並べる.
    var buttons: [ButtonSpec] {
        let w = screenWidth, h = screenHeight
        func x(_ fromEdge: Float) -> Float { leftHanded ? insets.left + fromEdge : w - insets.right - fromEdge }
        func y(_ fromBottom: Float) -> Float { h - insets.bottom - fromBottom }
        let midX = insets.left + (w - insets.left - insets.right) / 2
        return [
            ButtonSpec(button: .fire, center: Point(x: x(100), y: y(110)), radius: 70),
            ButtonSpec(button: .aim, center: Point(x: x(232), y: y(78)), radius: 44),
            ButtonSpec(button: .jump, center: Point(x: x(70), y: y(248)), radius: 46),
            ButtonSpec(button: .reload, center: Point(x: x(218), y: y(192)), radius: 40),
            ButtonSpec(button: .switchWeapon, center: Point(x: x(178), y: y(292)), radius: 38),
            ButtonSpec(button: .interact, center: Point(x: midX, y: y(140)), radius: 46),
        ]
    }

    /// 今 押せるボタン(「もちかえる」は 出しているときだけ).
    var activeButtons: [ButtonSpec] {
        buttons.filter { $0.button != .interact || showsInteract }
    }

    /// 指の下のボタン. 押せる範囲(見た目より少し大きい)が重なるときは, いちばん近い(半径で割った距離が小さい)ボタン.
    func button(at p: Point) -> Button? {
        var best: (Button, Float)?
        for b in activeButtons {
            let dx = p.x - b.center.x, dy = p.y - b.center.y
            let d = (dx * dx + dy * dy).squareRoot() / b.radius
            if d <= hitScale, best == nil || d < best!.1 { best = (b.button, d) }
        }
        return best?.0
    }

    private func isMoveSide(_ p: Point) -> Bool {
        leftHanded ? p.x >= screenWidth / 2 : p.x < screenWidth / 2
    }

    // MARK: 指

    mutating func touchBegan(id: Int, x: Float, y: Float) {
        let p = Point(x: x, y: y)
        if let b = button(at: p) {
            touches[id] = .button(b, last: p)
            // 押した瞬間も覚える(1 コマより短いタップでも 撃つ・ジャンプが消えないように). 構えるは 押しているあいだだけ.
            if b != .aim { pressedEdges.insert(b) }
        } else if isMoveSide(p) && !touches.values.contains(where: { if case .move = $0 { return true } else { return false } }) {
            touches[id] = .move(origin: p)
            stick = Point(x: 0, y: 0)
        } else {
            touches[id] = .look(last: p)
        }
    }

    mutating func touchMoved(id: Int, x: Float, y: Float) {
        let p = Point(x: x, y: y)
        switch touches[id] {
        case .move(var origin)?:
            var dx = p.x - origin.x
            var dy = p.y - origin.y
            var len = (dx * dx + dy * dy).squareRoot()
            // 指がスティックの外へ出たら, まん中も ついてくる(指を戻さなくても 向きを変えられる).
            if len > stickRadius {
                let k = (len - stickRadius) / len
                origin.x += dx * k
                origin.y += dy * k
                dx = p.x - origin.x
                dy = p.y - origin.y
                len = stickRadius
                touches[id] = .move(origin: origin)
            }
            let amount = len / stickRadius
            if amount < stickDeadZone || len < 1e-3 {
                stick = Point(x: 0, y: 0)
            } else {
                let scaled = (amount - stickDeadZone) / (1 - stickDeadZone)
                stick = Point(x: dx / len * scaled, y: -dy / len * scaled)     // 画面の上へ動かす = 前
            }
        case .look(let last)?:
            addLook(from: last, to: p)
            touches[id] = .look(last: p)
        case .button(let b, let last)?:
            if b == .fire { addLook(from: last, to: p) }       // 撃ちながら 視点を動かせる
            touches[id] = .button(b, last: p)
        case nil:
            break
        }
    }

    /// 指をはなした. 押した瞬間の記録(`takePressed`)は消さない(ゲームが読むまで残す).
    mutating func touchEnded(id: Int) {
        if case .move? = touches[id] { stick = Point(x: 0, y: 0) }
        touches[id] = nil
    }

    /// 電話がかかってきた・アプリが止まったとき: 指を全部はなしたことにする.
    /// (指が 0 本になるたびに呼ぶものではない. 呼ぶと 押しっぱなしの判定が消える.)
    mutating func cancelAll() {
        touches = [:]
        stick = Point(x: 0, y: 0)
    }

    private mutating func addLook(from a: Point, to b: Point) {
        lookYaw += (b.x - a.x) * lookSensitivity
        lookPitch += (a.y - b.y) * lookSensitivity * (invertY ? -1 : 1)     // 指を上へ = 上を向く
    }

    // MARK: 読み出し

    /// 移動の向き(右が +x, 前が +y. 長さ 1 まで. まん中の遊びは 0).
    var move: Point { stick }

    /// スティックの絵: 指を置いた所(まん中)と, つまみの位置. 移動の指が無ければ nil.
    var stickVisual: (origin: Point, knob: Point)? {
        for role in touches.values {
            if case .move(let origin) = role {
                let len = (stick.x * stick.x + stick.y * stick.y).squareRoot()
                let shown = len > 0 ? stickDeadZone + len * (1 - stickDeadZone) : 0
                let k = len > 0 ? shown / len : 0
                return (origin, Point(x: origin.x + stick.x * k * stickRadius, y: origin.y - stick.y * k * stickRadius))
            }
        }
        return nil
    }

    /// 前に読んでから動いた視点の量(ラジアン). 読むと 0 に戻る.
    mutating func takeLook() -> (yaw: Float, pitch: Float) {
        defer { lookYaw = 0; lookPitch = 0 }
        return (lookYaw, lookPitch)
    }

    /// 押しっぱなしのボタン(撃つ・構える).
    func isHeld(_ b: Button) -> Bool {
        touches.values.contains { if case .button(let x, _) = $0 { return x == b } else { return false } }
    }

    /// 前に読んでから 押されたボタン(撃つ・ジャンプ・リロード・武器の切りかえ・もちかえる). 読むと空になる.
    /// すぐ はなしても ここには残る.
    mutating func takePressed() -> Set<Button> {
        defer { pressedEdges = [] }
        return pressedEdges
    }

    var activeTouchCount: Int { touches.count }
}
