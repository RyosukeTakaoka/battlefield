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
        controller?.touch.screenWidth = Float(bounds.width)
        controller?.touch.screenHeight = Float(bounds.height)
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

    private func end(_ touches: Set<UITouch>) {
        guard let c = controller else { return }
        for t in touches {
            if let id = ids.removeValue(forKey: t) { c.touch.touchEnded(id: id) }
        }
        if ids.isEmpty { c.touch.cancelAll() }
    }
}

/// 画面の上のボタンの絵(指は `TouchSurface` が受けるので, ここは見た目だけ).
struct ControlButtonsOverlay: View {
    let controller: BattleController
    let leftHanded: Bool
    let showInteract: Bool

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

    private func layout(for size: CGSize) -> TouchLayout {
        var l = TouchLayout(width: Float(size.width), height: Float(size.height))
        l.leftHanded = leftHanded
        return l
    }

    private func buttons(_ layout: TouchLayout) -> some View {
        ZStack {
            ForEach(layout.buttons, id: \.button) { spec in
                if spec.button != .interact || showInteract {
                    let held = controller.touch.isHeld(spec.button)
                    Image(systemName: Self.symbol(spec.button))
                        .font(.system(size: CGFloat(spec.radius) * 0.7, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: CGFloat(spec.radius) * 2, height: CGFloat(spec.radius) * 2)
                        .background(Circle().fill(spec.button == .fire ? Theme.coral : Color.black.opacity(0.45)))
                        .overlay(Circle().stroke(.white.opacity(held ? 1 : 0.6), lineWidth: held ? 5 : 3))
                        .scaleEffect(held ? 0.92 : 1)
                        .position(x: CGFloat(spec.center.x), y: CGFloat(spec.center.y))
                }
            }
        }
    }

    var body: some View {
        GeometryReader { geo in
            // 押しているあいだ 明るくする(少しの間かくで見にいく).
            TimelineView(.periodic(from: .now, by: 0.05)) { _ in
                buttons(layout(for: geo.size))
            }
        }
        .allowsHitTesting(false)
    }
}
