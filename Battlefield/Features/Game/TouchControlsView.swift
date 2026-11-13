import SwiftUI
import UIKit

/// 指を 1 本ずつ追う(`docs/DESIGN.md` §3「Input」). SwiftUI の `DragGesture` は 2 本・3 本の指を同時に追えないので,
/// `UIView` の `touchesBegan / Moved / Ended / Cancelled` を使う. どの指が どの役か(移動・視点・ボタン)は Core の `TouchLayout` が決める.
struct TouchControlsView: UIViewRepresentable {
    let controller: BattleController

    func makeUIView(context: Context) -> TouchSurface {
        let v = TouchSurface()
        v.controller = controller
        return v
    }

    func updateUIView(_ uiView: TouchSurface, context: Context) {
        uiView.controller = controller
    }
}

final class TouchSurface: UIView {
    weak var controller: BattleController?
    private var ids: [UITouch: Int] = [:]
    private var nextId = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateLayout()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        updateLayout()
    }

    /// この板は 画面全体(安全な範囲の外まで)に広がる. ボタンは安全な範囲の内側に置くので, その幅も渡す.
    /// ボタンの絵(`ControlButtonsOverlay`)も 同じ `controller.touch` から描くので, 見える場所 = 押せる場所.
    private func updateLayout() {
        guard let c = controller else { return }
        c.touch.screenWidth = Float(bounds.width)
        c.touch.screenHeight = Float(bounds.height)
        let i = safeAreaInsets
        c.touch.insets = .init(left: Float(i.left), right: Float(i.right), top: Float(i.top), bottom: Float(i.bottom))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let c = controller else { return }
        for t in touches {
            let id = nextId
            nextId += 1
            ids[t] = id
            let p = t.location(in: self)
            c.touch.touchBegan(id: id, x: Float(p.x), y: Float(p.y))
        }
        // やられて観戦中は, 画面をタップして見る相手を切りかえる.
        if !c.hud.alive, c.phase == .match { c.cycleSpectate() }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let c = controller else { return }
        for t in touches {
            guard let id = ids[t] else { continue }
            let p = t.location(in: self)
            c.touch.touchMoved(id: id, x: Float(p.x), y: Float(p.y))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        end(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        end(touches)
    }

    /// 指を 1 本ずつ はなす. (以前は 指が 0 本になるたびに `cancelAll` を呼んでいて,
    /// まだゲームが読んでいない「ジャンプを押した」などの記録まで消していた.)
    private func end(_ touches: Set<UITouch>) {
        guard let c = controller else { return }
        for t in touches {
            if let id = ids.removeValue(forKey: t) { c.touch.touchEnded(id: id) }
        }
    }
}

/// 画面の上のボタンとスティックの絵(指は `TouchSurface` が受けるので, ここは見た目だけ).
/// **当たり判定と同じ `controller.touch` から描く**ので, 見える場所と押せる場所がずれない.
/// 指の板と同じく 画面全体に広げて置くこと(`.ignoresSafeArea()`).
struct ControlButtonsOverlay: View {
    let controller: BattleController

    private static func symbol(_ b: TouchLayout.Button) -> String {
        switch b {
        case .fire: return "target"
        case .aim: return "scope"
        case .jump: return "arrow.up"
        case .reload: return "arrow.clockwise"
        case .switchWeapon: return "arrow.left.arrow.right"
        case .interact: return "hand.tap.fill"
        }
    }

    private static func label(_ b: TouchLayout.Button) -> String? {
        switch b {
        case .aim: return "構える"
        case .jump: return "ジャンプ"
        case .reload: return "リロード"
        case .switchWeapon: return "武器"
        case .interact: return "もちかえる"
        case .fire: return nil
        }
    }

    var body: some View {
        // 押しているあいだ 明るくする・スティックを動かすため, 30 回/秒 見にいく.
        TimelineView(.periodic(from: .now, by: 1.0 / 30)) { _ in
            let layout = controller.touch
            ZStack {
                if let stick = layout.stickVisual {
                    Circle().fill(.black.opacity(0.18)).overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 2))
                        .frame(width: CGFloat(layout.stickRadius) * 2, height: CGFloat(layout.stickRadius) * 2)
                        .position(x: CGFloat(stick.origin.x), y: CGFloat(stick.origin.y))
                    Circle().fill(.white.opacity(0.75))
                        .frame(width: 44, height: 44)
                        .position(x: CGFloat(stick.knob.x), y: CGFloat(stick.knob.y))
                }
                ForEach(layout.activeButtons, id: \.button) { spec in
                    let held = layout.isHeld(spec.button)
                    VStack(spacing: 1) {
                        Image(systemName: Self.symbol(spec.button))
                            .font(.system(size: CGFloat(spec.radius) * (spec.button == .fire ? 0.62 : 0.5), weight: .heavy))
                        if let text = Self.label(spec.button) {
                            Text(text).font(.system(size: 10, weight: .heavy, design: .rounded))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(width: CGFloat(spec.radius) * 2, height: CGFloat(spec.radius) * 2)
                    .background(Circle().fill(spec.button == .fire ? Theme.coral.opacity(held ? 1 : 0.85)
                                                                     : Color.black.opacity(held ? 0.6 : 0.4)))
                    .overlay(Circle().stroke(.white.opacity(held ? 1 : 0.6), lineWidth: held ? 5 : 3))
                    .scaleEffect(held ? 0.92 : 1)
                    .position(x: CGFloat(spec.center.x), y: CGFloat(spec.center.y))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
    }
}
