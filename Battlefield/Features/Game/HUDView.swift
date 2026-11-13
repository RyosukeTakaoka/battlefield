import SwiftUI

/// 戦いのあいだ画面に重ねる表示(指は受けない).
struct HUDView: View {
    let controller: BattleController

    var body: some View {
        let hud = controller.hud
        ZStack {
            if hud.scope { ScopeOverlay() }
            if hud.outsideZone { ZoneWarning() }
            DamageIndicator(angle: controller.damageAngle, alpha: controller.damageAlpha)
            Crosshair(aiming: hud.aiming, hit: controller.hitMarker, head: controller.headMarker, reload: hud.reload)

            // 左上: ミニマップと点.
            VStack(alignment: .leading, spacing: 8) {
                MinimapView(hud: hud)
                if hud.scores.count > 1 { ScoreBoard(lines: hud.scores, mode: hud.modeText) }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(14)

            // 上: ラウンド・のこり人数・円.
            VStack(spacing: 6) {
                HStack(spacing: 14) {
                    Text(hud.roundText).font(Theme.font(17))
                    Label("\(hud.aliveCount)/\(hud.playerCount)", systemImage: "person.fill").font(Theme.font(17))
                    Label("\(hud.kills)", systemImage: "scope").font(Theme.font(17))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Capsule().fill(.black.opacity(0.45)))
                if !hud.zoneText.isEmpty {
                    Text(hud.zoneText).font(Theme.font(14, .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(Capsule().fill(Color(red: 0.55, green: 0.3, blue: 0.9).opacity(0.8)))
                }
                if let who = hud.spectating {
                    Text("観戦中: \(who)(タップで切りかえ)").font(Theme.font(15)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 5).background(Capsule().fill(.black.opacity(0.55)))
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 10)

            // 右上: だれがだれを倒したか.
            VStack(alignment: .trailing, spacing: 4) {
                ForEach(controller.feed) { item in
                    Text(item.text).font(Theme.font(14, .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Capsule().fill(item.mine ? Theme.coral.opacity(0.85) : .black.opacity(0.5)))
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(14)
            .animation(.easeOut(duration: 0.2), value: controller.feed)

            // 左下: 体力・シールド.
            VStack(alignment: .leading, spacing: 6) {
                Spacer()
                if let net = hud.netText {
                    Text(net).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(.white)
                        .padding(4).background(.black.opacity(0.5))
                }
                VitalsBar(hp: hud.hp, shield: hud.shield)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(14)

            // 下の中: 武器と弾.
            VStack(spacing: 6) {
                Spacer()
                if let prompt = hud.pickupPrompt {
                    Text(prompt).font(Theme.font(16)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 5).background(Capsule().fill(Theme.leaf))
                        .padding(.bottom, 70)
                }
                WeaponBar(hud: hud)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 8)

            if let n = hud.countdown { CountdownNumber(n: n) }
            if let toast = controller.toast { ToastView(toast: toast).id(toast.id) }
        }
        .allowsHitTesting(false)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: controller.toast)
    }
}

private struct Crosshair: View {
    let aiming: Bool
    let hit: Float
    let head: Bool
    let reload: Float?

    var body: some View {
        ZStack {
            let gap: CGFloat = aiming ? 4 : 9
            ForEach(0..<4, id: \.self) { i in
                Rectangle().fill(.white).frame(width: 2.5, height: 9)
                    .offset(y: -(gap + 4.5))
                    .rotationEffect(.degrees(Double(i) * 90))
            }
            .shadow(color: .black.opacity(0.6), radius: 1)
            // 当たりの印.
            if hit > 0 {
                ZStack {
                    Rectangle().fill(head ? Color.red : .white).frame(width: 3, height: 20).rotationEffect(.degrees(45))
                    Rectangle().fill(head ? Color.red : .white).frame(width: 3, height: 20).rotationEffect(.degrees(-45))
                }
                .opacity(Double(hit)).scaleEffect(1 + CGFloat(1 - hit) * 0.5)
            }
            if let r = reload {
                Circle().trim(from: 0, to: CGFloat(r)).stroke(Theme.gold, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90)).frame(width: 46, height: 46)
            }
        }
    }
}

private struct VitalsBar: View {
    let hp: Int
    let shield: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            bar(value: Double(shield) / Double(GameRules.maxShield), color: Color(red: 0.3, green: 0.65, blue: 1), text: "\(shield)")
            bar(value: Double(hp) / Double(GameRules.maxHP), color: hp > 30 ? Theme.leaf : Theme.coral, text: "\(hp)")
        }
        .padding(8).background(RoundedRectangle(cornerRadius: 12).fill(.black.opacity(0.45)))
    }

    private func bar(value: Double, color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.25))
                RoundedRectangle(cornerRadius: 5).fill(color).frame(width: 170 * max(0, min(1, value)))
            }
            .frame(width: 170, height: 12)
            Text(text).font(Theme.font(15)).foregroundStyle(.white).monospacedDigit().frame(width: 36, alignment: .trailing)
        }
    }
}

private struct WeaponBar: View {
    let hud: BattleController.HUD

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<2, id: \.self) { i in
                let name = hud.slotNames[i]
                Text(name ?? "—").font(Theme.font(13))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .foregroundStyle(i == hud.selectedSlot ? .white : .white.opacity(0.6))
                    .background(Capsule().fill(i == hud.selectedSlot ? Theme.coral : .black.opacity(0.4)))
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(hud.ammo)").font(Theme.font(26)).monospacedDigit()
                Text("/\(hud.magazine)").font(Theme.font(14, .bold)).opacity(0.7)
            }
            .foregroundStyle(hud.ammo == 0 ? Theme.coral : .white)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill(.black.opacity(0.45)))
    }
}

private struct ScoreBoard: View {
    let lines: [BattleController.ScoreLine]
    let mode: String

    /// 16 人でも 画面をうめないよう, 上位 5 人 + 自分 だけ出す.
    private var shown: [BattleController.ScoreLine] {
        let sorted = lines.sorted { mode == "ラウンド戦" ? ($0.score, $0.kills) > ($1.score, $1.kills) : $0.kills > $1.kills }
        var top = Array(sorted.prefix(5))
        if let me = sorted.first(where: \.isMe), !top.contains(where: \.isMe) { top.append(me) }
        return top
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(shown) { l in
                HStack(spacing: 6) {
                    Circle().fill(CharacterRig.colors[l.id % CharacterRig.colors.count].swiftUI).frame(width: 9, height: 9)
                    Text(l.name).lineLimit(1)
                    Spacer(minLength: 4)
                    if mode == "ラウンド戦" { Text("\(l.score)点").monospacedDigit() } else { Text("\(l.kills)キル").monospacedDigit() }
                }
                .font(Theme.font(12, l.isMe ? .heavy : .semibold))
                .opacity(l.alive ? 1 : 0.5)
                .foregroundStyle(.white)
            }
        }
        .padding(8).frame(width: 132)
        .background(RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.45)))
    }
}

private extension UIColor {
    var swiftUI: Color { Color(uiColor: self) }
}

private struct ScopeOverlay: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.55)).mask {
                Rectangle().overlay { Circle().frame(width: 330, height: 330).blendMode(.destinationOut) }.compositingGroup()
            }
            Rectangle().fill(.black).frame(width: 340, height: 1.5)
            Rectangle().fill(.black).frame(width: 1.5, height: 340)
        }
        .ignoresSafeArea()
    }
}

private struct ZoneWarning: View {
    var body: some View {
        Rectangle().fill(.clear)
            .overlay(RoundedRectangle(cornerRadius: 0).stroke(Color(red: 0.7, green: 0.3, blue: 1).opacity(0.65), lineWidth: 26).blur(radius: 14))
            .overlay(alignment: .top) {
                Text("円の外! ダメージをうけています").font(Theme.font(18)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 5).background(Capsule().fill(Color(red: 0.6, green: 0.25, blue: 0.9)))
                    .padding(.top, 66)
            }
            .ignoresSafeArea()
    }
}

private struct DamageIndicator: View {
    let angle: Float?
    let alpha: Float

    var body: some View {
        if let angle, alpha > 0.02 {
            Image(systemName: "triangle.fill")
                .font(.system(size: 26)).foregroundStyle(Color.red)
                .offset(y: -120)
                .rotationEffect(.radians(Double(angle)))
                .opacity(Double(alpha))
        }
    }
}

private struct CountdownNumber: View {
    let n: Int

    var body: some View {
        Text("\(n)").font(Theme.font(120)).foregroundStyle(.white).shadow(color: .black.opacity(0.6), radius: 6)
            .id(n).transition(.scale(scale: 1.5).combined(with: .opacity))
    }
}

struct ToastView: View {
    let toast: BattleController.Toast

    var body: some View {
        VStack {
            Text(toast.text)
                .font(Theme.font(toast.style == .big ? 34 : 22))
                .foregroundStyle(.white)
                .padding(.horizontal, 22).padding(.vertical, 8)
                .background(Capsule().fill(color))
                .overlay(Capsule().stroke(Theme.ink, lineWidth: 2.5))
                .padding(.top, toast.style == .big ? 110 : 76)
            Spacer()
        }
        .transition(.scale.combined(with: .opacity))
    }

    private var color: Color {
        switch toast.style {
        case .info: return Theme.sky
        case .good: return Theme.leaf
        case .bad: return Theme.coral
        case .big: return Theme.ink.opacity(0.85)
        }
    }
}
