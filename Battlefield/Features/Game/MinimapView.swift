import SwiftUI
import UIKit

/// 左上のミニマップ. 上が前(-Z), 右が +X, 1 px = 1 m(`Tools/map/build_arena.py`). 自分と円だけ(敵は出さない).
struct MinimapView: View {
    let hud: BattleController.HUD
    var size: CGFloat = 132

    private static let image: UIImage? = {
        guard let path = Bundle.main.path(forResource: "island_minimap", ofType: "jpg") else { return nil }
        return UIImage(contentsOfFile: path)
    }()

    private func point(_ x: Float, _ z: Float) -> CGPoint {
        CGPoint(x: CGFloat((x + 256) / 512) * size, y: CGFloat((z + 256) / 512) * size)
    }

    var body: some View {
        ZStack {
            if let image = Self.image {
                Image(uiImage: image).resizable().scaledToFill().frame(width: size, height: size)
            } else {
                Color.black.opacity(0.4)
            }
            Canvas { ctx, canvas in
                let k = size / 512
                if let a = hud.arena, a.r > 0 {
                    let c = point(a.x, a.z)
                    ctx.stroke(Path(ellipseIn: CGRect(x: c.x - CGFloat(a.r) * k, y: c.y - CGFloat(a.r) * k,
                                                      width: CGFloat(a.r) * 2 * k, height: CGFloat(a.r) * 2 * k)),
                               with: .color(.white.opacity(0.7)), lineWidth: 1)
                }
                if let z = hud.zone, z.r > 0 {
                    let c = point(z.x, z.z)
                    let rect = CGRect(x: c.x - CGFloat(z.r) * k, y: c.y - CGFloat(z.r) * k, width: CGFloat(z.r) * 2 * k, height: CGFloat(z.r) * 2 * k)
                    ctx.stroke(Path(ellipseIn: rect), with: .color(Color(red: 0.7, green: 0.4, blue: 1)), lineWidth: 2)
                }
                // 自分: 向きを指す三角.
                let p = point(hud.playerX, hud.playerZ)
                var tri = Path()
                tri.move(to: CGPoint(x: 0, y: -7))
                tri.addLine(to: CGPoint(x: 5, y: 5))
                tri.addLine(to: CGPoint(x: -5, y: 5))
                tri.closeSubpath()
                let transform = CGAffineTransform(translationX: p.x, y: p.y).rotated(by: CGFloat(hud.playerYaw))
                ctx.fill(tri.applying(transform), with: .color(Theme.coral))
                ctx.stroke(tri.applying(transform), with: .color(.white), lineWidth: 1.5)
            }
            .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.ink, lineWidth: 2.5))
    }
}
