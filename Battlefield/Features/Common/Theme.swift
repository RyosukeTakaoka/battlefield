import SwiftUI

/// 画面のデザインの決まりごと: ノートと折り紙の雰囲気.
/// クリーム色の紙のパネル, こげ茶の縁取り, 丸みのある太字.
enum Theme {
    static let ink = Color(red: 0.22, green: 0.18, blue: 0.15)
    static let paper = Color(red: 1.0, green: 0.975, blue: 0.93)
    static let paperShade = Color(red: 0.94, green: 0.91, blue: 0.85)
    static let sky = Color(red: 0.28, green: 0.60, blue: 0.95)
    static let coral = Color(red: 0.97, green: 0.47, blue: 0.35)
    static let gold = Color(red: 0.98, green: 0.74, blue: 0.22)
    static let leaf = Color(red: 0.36, green: 0.68, blue: 0.36)
    static let ruled = Color(red: 0.55, green: 0.72, blue: 0.93)

    static func font(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

/// 紙のパネル(縁取り + やわらかい影).
struct PaperPanel: ViewModifier {
    var padding: CGFloat = 16
    var corner: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Theme.paper)
                    .overlay(RuledLines().clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous)).opacity(0.35))
            )
            .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).stroke(Theme.ink, lineWidth: 2.5))
            .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
    }
}

/// ノートの罫線(パネルの背景にうっすら).
struct RuledLines: View {
    var body: some View {
        Canvas { ctx, size in
            var y: CGFloat = 28
            while y < size.height {
                ctx.stroke(Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)) },
                           with: .color(Theme.ruled.opacity(0.5)), lineWidth: 1)
                y += 28
            }
        }
    }
}

extension View {
    func paperPanel(padding: CGFloat = 16, corner: CGFloat = 20) -> some View {
        modifier(PaperPanel(padding: padding, corner: corner))
    }
}

/// 大きな丸いボタン.
struct PaperButtonStyle: ButtonStyle {
    var color: Color = Theme.sky
    var size: CGFloat = 24

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(size))
            .foregroundStyle(.white)
            .padding(.horizontal, size * 1.1)
            .padding(.vertical, size * 0.55)
            .background(
                Capsule().fill(color)
                    .overlay(Capsule().fill(.white.opacity(configuration.isPressed ? 0.15 : 0)))
            )
            .overlay(Capsule().stroke(Theme.ink, lineWidth: 2.5))
            .shadow(color: .black.opacity(0.2), radius: configuration.isPressed ? 2 : 6, y: configuration.isPressed ? 1 : 4)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// パネルの上につく見出しのタブ(参考画像の「飛距離」「タイム」のような).
struct LabelTab: View {
    let text: String
    var color: Color = Theme.ink

    var body: some View {
        Text(text)
            .font(Theme.font(15))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Capsule().fill(color))
    }
}

/// ★ の並び(むずかしさ).
struct Stars: View {
    let count: Int
    var max: Int = 3

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<max, id: \.self) { i in
                Image(systemName: i < count ? "star.fill" : "star")
                    .foregroundStyle(i < count ? Theme.gold : Theme.ink.opacity(0.3))
            }
        }
        .font(.system(size: 14, weight: .bold))
    }
}

/// 戻るボタン(左上).
struct BackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("もどる", systemImage: "chevron.left")
                .font(Theme.font(18))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Theme.paper))
                .overlay(Capsule().stroke(Theme.ink, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

/// 背景: コースの絵 + 空色のグラデーション.
struct SkyBackground: View {
    var imageName: String = "Course_countryside"

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.42, green: 0.68, blue: 0.97), Color(red: 0.86, green: 0.93, blue: 1.0)],
                           startPoint: .top, endPoint: .bottom)
            // 絵は「画面の大きさの枠」の中に貼って, はみ出た所は切る.
            // (scaledToFill の絵をそのまま置くと, 画面全体が絵の大きさに広がって, ボタンが画面の外へ出てしまう.)
            Color.clear
                .overlay(Image(imageName).resizable().scaledToFill().opacity(0.9))
                .clipped()
            LinearGradient(colors: [.white.opacity(0.0), .white.opacity(0.35)], startPoint: .center, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }
}
