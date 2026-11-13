import Foundation

/// 肩ごしのカメラ(`docs/DESIGN.md` §3「Camera」). 描画を知らない.
///
/// 頭(足もと + 1.6 m)から, 後ろ 3.2 m・右 0.6 m・上 0.4 m. 構えると近づいて 画角がせまくなる.
/// カメラの向きは 視線そのもの(画面のまん中 = 弾がねらう先)なので, 向きはなめらかにせず, 位置と画角だけ近づける.
/// 頭からカメラへ線をのばし, かべ・地面に当たるなら 手前に寄せる(かべの中に入らない).
struct ThirdPersonCamera {
    struct Pose: Equatable {
        var position: Vec3
        /// 視線の向き(長さ 1).
        var forward: Vec3
        /// 縦の画角(ラジアン).
        var verticalFOV: Float
    }

    static let back: Float = 3.2
    static let right: Float = 0.6
    static let up: Float = 0.4
    static let aimBack: Float = 1.6
    static let aimRight: Float = 0.5
    static let fovNormal: Float = 60 * .pi / 180
    static let fovAim: Float = 35 * .pi / 180
    static let fovSniperAim: Float = 15 * .pi / 180
    /// かべから離す距離.
    static let wallMargin: Float = 0.25
    /// 地面からの最低の高さ.
    static let groundMargin: Float = 0.3

    private var distanceScale: Float = 1
    private var offsetBack: Float = back
    private var offsetRight: Float = right
    private var fov: Float = fovNormal

    init() {}

    /// 毎コマ. `player` は見ている人(自分, または 観戦の相手). `weapon` はスナイパーの画角のため.
    mutating func update(player: PlayerState, aiming: Bool, weapon: WeaponKind?, world: ArenaWorld, dt: Float) -> Pose {
        let wantBack = aiming ? Self.aimBack : Self.back
        let wantRight = aiming ? Self.aimRight : Self.right
        let wantFOV = aiming ? (weapon == .sniper ? Self.fovSniperAim : Self.fovAim) : Self.fovNormal
        offsetBack += (wantBack - offsetBack) * approach(14, dt)
        offsetRight += (wantRight - offsetRight) * approach(14, dt)
        fov += (wantFOV - fov) * approach(14, dt)

        let head = player.eye
        let f = player.lookDirection
        let r = player.right
        let desired = head - f * offsetBack + r * offsetRight + Vec3(0, Self.up, 0)
        let toDesired = desired - head
        let length = toDesired.length
        let dir = toDesired.normalized(or: -f)

        // かべ・地面があれば手前へ(すぐ寄せる). 空いたら ゆっくり戻る.
        var limit = length
        if let hit = world.raycast(origin: head, direction: dir, maxDistance: length + Self.wallMargin) {
            limit = max(min(length, hit.distance - Self.wallMargin), 0.2)
        }
        let wanted = limit / max(length, 1e-4)
        if wanted < distanceScale { distanceScale = wanted } else { distanceScale += (wanted - distanceScale) * approach(6, dt) }
        var position = head + dir * (length * distanceScale)
        // 地面の中に入らない.
        let floor = max(world.terrainHeight(x: position.x, z: position.z), world.waterY) + Self.groundMargin
        if position.y < floor { position.y = floor }
        return Pose(position: position, forward: f, verticalFOV: fov)
    }

    /// 画角(ラジアン)をリセット(カメラを別の人へ切りかえるとき).
    mutating func snap() {
        distanceScale = 1
        offsetBack = Self.back
        offsetRight = Self.right
        fov = Self.fovNormal
    }
}
