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
        var radius: Float
    }

    private enum Role: Equatable {
        case move(origin: Point)
        case look(last: Point)
        case button(Button, last: Point)
    }

    var screenWidth: Float
    var screenHeight: Float
    var leftHanded = false
    /// 視点: 1 pt 動かしたとき何ラジアン回るか(設定の感度をかけたもの).
    var lookSensitivity: Float = 0.006
    var invertY = false
    var stickRadius: Float = 60

    private var touches: [Int: Role] = [:]
    private var stick = Point(x: 0, y: 0)
    private var lookYaw: Float = 0
    private var lookPitch: Float = 0
    private var pressedEdges: Set<Button> = []

    init(width: Float, height: Float) {
        screenWidth = width
        screenHeight = height
    }

    /// ボタンの置き場所(画面の大きさから決める. 右ききは右下, 左ききは左下に撃つボタン).
    var buttons: [ButtonSpec] {
        let w = screenWidth, h = screenHeight
        let m: Float = 14
        let side: Float = leftHanded ? 1 : -1
        func x(_ fromEdge: Float) -> Float { leftHanded ? fromEdge : w - fromEdge }
        _ = side
        return [
            ButtonSpec(button: .fire, center: Point(x: x(88 + m), y: h - 96 - m), radius: 64),
            ButtonSpec(button: .aim, center: Point(x: x(210 + m), y: h - 70 - m), radius: 40),
            ButtonSpec(button: .jump, center: Point(x: x(62 + m), y: h - 232 - m), radius: 42),
            ButtonSpec(button: .reload, center: Point(x: x(190 + m), y: h - 170 - m), radius: 36),
            ButtonSpec(button: .switchWeapon, center: Point(x: x(150 + m), y: h - 280 - m), radius: 34),
            ButtonSpec(button: .interact, center: Point(x: w / 2, y: h - 120), radius: 44),
        ]
    }

    private func button(at p: Point) -> Button? {
        for b in buttons {
            let dx = p.x - b.center.x, dy = p.y - b.center.y
            if dx * dx + dy * dy <= b.radius * b.radius { return b.button }
        }
        return nil
    }

    private func isMoveSide(_ p: Point) -> Bool {
        leftHanded ? p.x >= screenWidth / 2 : p.x < screenWidth / 2
    }

    // MARK: 指

    mutating func touchBegan(id: Int, x: Float, y: Float) {
        let p = Point(x: x, y: y)
        if let b = button(at: p) {
            touches[id] = .button(b, last: p)
            if b != .fire && b != .aim { pressedEdges.insert(b) }
        } else if isMoveSide(p) && !touches.values.contains(where: { if case .move = $0 { return true } else { return false } }) {
            touches[id] = .move(origin: p)
        } else {
            touches[id] = .look(last: p)
        }
    }

    mutating func touchMoved(id: Int, x: Float, y: Float) {
        let p = Point(x: x, y: y)
        switch touches[id] {
        case .move(let origin)?:
            var dx = (p.x - origin.x) / stickRadius
            var dy = -(p.y - origin.y) / stickRadius          // 画面の上へ動かす = 前
            let len = (dx * dx + dy * dy).squareRoot()
            if len > 1 { dx /= len; dy /= len }
            stick = Point(x: dx, y: dy)
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

    mutating func touchEnded(id: Int) {
        if case .move? = touches[id] { stick = Point(x: 0, y: 0) }
        touches[id] = nil
    }

    /// 電話がかかってきた・アプリが止まったとき: 全部はなしたことにする.
    mutating func cancelAll() {
        touches = [:]
        stick = Point(x: 0, y: 0)
        pressedEdges = []
    }

    private mutating func addLook(from a: Point, to b: Point) {
        lookYaw += (b.x - a.x) * lookSensitivity
        lookPitch += (a.y - b.y) * lookSensitivity * (invertY ? -1 : 1)     // 指を上へ = 上を向く
    }

    // MARK: 読み出し

    /// 移動の向き(右が +x, 前が +y. 長さ 1 まで).
    var move: Point { stick }

    /// 前に読んでから動いた視点の量(ラジアン). 読むと 0 に戻る.
    mutating func takeLook() -> (yaw: Float, pitch: Float) {
        defer { lookYaw = 0; lookPitch = 0 }
        return (lookYaw, lookPitch)
    }

    /// 押しっぱなしのボタン(撃つ・構える).
    func isHeld(_ b: Button) -> Bool {
        touches.values.contains { if case .button(let x, _) = $0 { return x == b } else { return false } }
    }

    /// 押した瞬間のボタン(ジャンプ・リロード・武器の切りかえ・もちかえる). 読むと空になる.
    mutating func takePressed() -> Set<Button> {
        defer { pressedEdges = [] }
        return pressedEdges
    }

    var activeTouchCount: Int { touches.count }
}
