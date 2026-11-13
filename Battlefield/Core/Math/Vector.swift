import Foundation

/// 3 次元のベクトル. 標準ライブラリの SIMD3 をそのまま使う.
///
/// Core は iPad 以外(テスト用の Linux)でも動くように, Apple 専用の `simd`
/// モジュールの関数(simd_normalize など)を使わず, ここで小さく用意する.
typealias Vec3 = SIMD3<Float>

extension SIMD3 where Scalar == Float {
    static let up = Vec3(0, 1, 0)
    /// ゲームの「前」. RealityKit の約束で -Z が前.
    static let forward = Vec3(0, 0, -1)
    static let right = Vec3(1, 0, 0)

    var length: Float { (self * self).sum().squareRoot() }
    var lengthSquared: Float { (self * self).sum() }

    /// 長さ 1 にしたもの. 長さがほぼ 0 のときは fallback を返す.
    func normalized(or fallback: Vec3 = .forward) -> Vec3 {
        let len = length
        return len > 1e-6 ? self / len : fallback
    }

    func dot(_ other: Vec3) -> Float { (self * other).sum() }

    func cross(_ o: Vec3) -> Vec3 {
        Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x)
    }

    /// 水平(XZ 平面)に投影したもの.
    var horizontal: Vec3 { Vec3(x, 0, z) }

    /// axis(長さ 1)のまわりに angle ラジアン回したもの(ロドリゲスの回転公式).
    func rotated(around axis: Vec3, by angle: Float) -> Vec3 {
        let c = cos(angle), s = sin(angle)
        return self * c + axis.cross(self) * s + axis * (axis.dot(self) * (1 - c))
    }
}

/// 値を範囲に収める.
@inline(__always) func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T { min(max(v, lo), hi) }

/// a から b へ t の割合だけ近づける.
@inline(__always) func mix(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }
@inline(__always) func mix(_ a: Vec3, _ b: Vec3, _ t: Float) -> Vec3 { a + (b - a) * t }

/// なめらかな 0〜1(端でゆっくり).
@inline(__always) func smoothstep(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
    let t = clamp((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)
}

/// 「毎秒 rate の速さで目標へ近づく」ときの, この 1 コマで近づく割合.
///
/// `mix(current, target, approach(rate, dt))` の形で使うと, コマの長さ(dt)が
/// ばらついても同じ動きになる(60fps でも 120fps でも同じ).
@inline(__always) func approach(_ rate: Float, _ dt: Float) -> Float { 1 - exp(-rate * dt) }

/// 角度を -π〜π に収める.
@inline(__always) func wrapAngle(_ a: Float) -> Float {
    var x = a.truncatingRemainder(dividingBy: 2 * .pi)
    if x > .pi { x -= 2 * .pi }
    if x < -.pi { x += 2 * .pi }
    return x
}

/// 向き(前・上・右の 3 本の軸). 回転を「軸の組」で持つと, 誰でも図に描いて
/// 確かめやすい. 描画側ではこれをクォータニオンに変換する.
struct Basis: Equatable {
    var forward: Vec3
    var up: Vec3
    var right: Vec3 { forward.cross(up) }

    static let identity = Basis(forward: .forward, up: .up)

    /// 方位(heading: 0 で -Z, 正で右へ), 機首の上げ下げ(pitch: 正で上), 傾き(bank: 正で右翼が下がる).
    init(heading: Float, pitch: Float, bank: Float) {
        let f = Vec3(sin(heading) * cos(pitch), sin(pitch), -cos(heading) * cos(pitch))
        let flatRight = Vec3(cos(heading), 0, sin(heading))
        let u0 = flatRight.cross(f).normalized(or: .up)
        // 右へ傾ける = 前を軸に, 上を右へ倒す
        // (前 = -Z を軸に正の向きへ回すと, 上 (0,1,0) は右 (+X) へ倒れる).
        let u = u0.rotated(around: f, by: bank)
        self.init(forward: f, up: u)
    }

    init(forward: Vec3, up: Vec3) {
        let f = forward.normalized()
        let r = f.cross(up).normalized(or: .right)
        self.forward = f
        self.up = r.cross(f)
    }
}
