import Foundation

/// 弾の線が最初に当たったもの.
struct RayHit: Equatable {
    enum Surface: Equatable {
        case terrain
        /// `ArenaWorld.solids` の番号.
        case obstacle(Int)
    }

    var distance: Float
    var point: Vec3
    var normal: Vec3
    var surface: Surface
}

/// 世界への問い合わせの窓口: 地面の高さ・動きの当たり・弾の線.
/// 地形(高さマップ)と障害物(箱・円柱)を, 同じデータから見る(見た目と判定がずれない).
struct ArenaWorld {
    /// 固いもの 1 つ. 箱は Y 軸まわりに回せる.
    struct Solid: Equatable {
        var isBox: Bool
        /// 箱: 中心. 円柱: 底の中心.
        var center: Vec3
        /// 箱: 半分の大きさ.
        var half: Vec3
        var cosYaw: Float
        var sinYaw: Float
        /// 円柱の半径と高さ.
        var radius: Float
        var height: Float

        var baseY: Float { isBox ? center.y - half.y : center.y }
        var topY: Float { isBox ? center.y + half.y : center.y + height }
        /// 上から見て, このものをすっぽり囲む円の半径.
        var boundRadius: Float { isBox ? (half.x * half.x + half.z * half.z).squareRoot() : radius }

        /// 世界の水平な向き → 箱の中の向き.
        func toLocal(dx: Float, dz: Float) -> (Float, Float) { (cosYaw * dx - sinYaw * dz, sinYaw * dx + cosYaw * dz) }
        /// 箱の中の向き → 世界.
        func toWorld(lx: Float, lz: Float) -> (Float, Float) { (cosYaw * lx + sinYaw * lz, -sinYaw * lx + cosYaw * lz) }

        func containsXZ(_ x: Float, _ z: Float) -> Bool {
            let dx = x - center.x, dz = z - center.z
            if isBox {
                let (lx, lz) = toLocal(dx: dx, dz: dz)
                return abs(lx) <= half.x && abs(lz) <= half.z
            }
            return dx * dx + dz * dz <= radius * radius
        }
    }

    let map: MapData
    let terrain: Heightfield
    private(set) var solids: [Solid] = []
    private var grid: [Int64: [Int]] = [:]
    private static let cellSize: Float = 16

    var waterY: Float { map.waterY }

    init(map: MapData, terrain: Heightfield) {
        self.map = map
        self.terrain = terrain
        for o in map.obstacles {
            let p = vec(o.p)
            switch o.shape {
            case .box:
                let yaw = o.yaw ?? 0
                solids.append(Solid(isBox: true, center: p, half: vec(o.half ?? [0.5, 0.5, 0.5]), cosYaw: cos(yaw),
                                    sinYaw: sin(yaw), radius: 0, height: 0))
            case .cyl:
                solids.append(Solid(isBox: false, center: p, half: .zero, cosYaw: 1, sinYaw: 0, radius: o.r ?? 0.5,
                                    height: o.h ?? 1))
            }
        }
        for (i, s) in solids.enumerated() {
            let r = s.boundRadius
            for ix in Self.cell(s.center.x - r)...Self.cell(s.center.x + r) {
                for iz in Self.cell(s.center.z - r)...Self.cell(s.center.z + r) {
                    grid[Self.key(ix, iz), default: []].append(i)
                }
            }
        }
    }

    private static func cell(_ v: Float) -> Int { Int((v / cellSize).rounded(.down)) }
    private static func key(_ ix: Int, _ iz: Int) -> Int64 { Int64(ix) &* 100_003 &+ Int64(iz) }

    /// (x, z) の近く(半径 radius)にある固いものの番号.
    func solidIndices(nearX x: Float, z: Float, radius: Float) -> [Int] {
        var out: [Int] = []
        for ix in Self.cell(x - radius)...Self.cell(x + radius) {
            for iz in Self.cell(z - radius)...Self.cell(z + radius) {
                if let list = grid[Self.key(ix, iz)] {
                    for i in list where !out.contains(i) { out.append(i) }
                }
            }
        }
        return out
    }

    // MARK: - 地面

    /// 地形の高さ(障害物は含めない). 島の外は深い海.
    func terrainHeight(x: Float, z: Float) -> Float {
        terrain.contains(x: x, z: z) ? terrain.height(x: x, z: z) : -50
    }

    /// 地形の法線(上向き).
    func terrainNormal(x: Float, z: Float) -> Vec3 {
        let e = terrain.cell
        let dhdx = (terrainHeight(x: x + e, z: z) - terrainHeight(x: x - e, z: z)) / (2 * e)
        let dhdz = (terrainHeight(x: x, z: z + e) - terrainHeight(x: x, z: z - e)) / (2 * e)
        return Vec3(-dhdx, 1, -dhdz).normalized(or: .up)
    }

    /// 足もとの高さ feetY から見て, 立てる面の高さ.
    /// 地形と, 「足から段差ぶんまでの高さにある天面」を持つ障害物の高い方.
    func surfaceHeight(x: Float, z: Float, feetY: Float) -> Float {
        var h = terrainHeight(x: x, z: z)
        for i in solidIndices(nearX: x, z: z, radius: 0) {
            let s = solids[i]
            if s.topY <= feetY + GameRules.stepHeight && s.baseY <= feetY + GameRules.stepHeight && s.containsXZ(x, z) {
                h = max(h, s.topY)
            }
        }
        return h
    }

    // MARK: - 動き

    /// 歩ける地面か(水・急すぎる坂・高すぎる崖でない). from → to は水平の動き.
    private func terrainBlocks(from: Vec3, to: Vec3) -> Bool {
        let hTo = terrainHeight(x: to.x, z: to.z)
        if hTo < GameRules.minGroundY { return true }
        // 足より段差以上に高い所は崖.
        if hTo > to.y + GameRules.stepHeight { return true }
        // 急な坂は登れない(下りはよい).
        let hFrom = terrainHeight(x: from.x, z: from.z)
        if hTo > hFrom + 1e-4 && to.y <= hTo + 0.05
            && terrainNormal(x: to.x, z: to.z).y < GameRules.walkableNormalY { return true }
        return false
    }

    /// 円柱(足もと feet, 半径 radius, 高さ height)を水平に動かし, 固いもの・水・崖・急な坂で止める.
    /// 戻り値は動いたあいだの位置(y は feet.y のまま). かべにそってすべる.
    func resolveMove(from feet: Vec3, to target: Vec3, radius: Float = GameRules.playerRadius,
                     height: Float = GameRules.playerHeight) -> Vec3 {
        let dx = target.x - feet.x, dz = target.z - feet.z
        let dist = (dx * dx + dz * dz).squareRoot()
        // 薄いかべをすりぬけないよう, 半径の半分ずつに分けて動かす.
        let steps = max(1, Int((dist / (radius * 0.5)).rounded(.up)))
        var pos = feet
        for i in 1...steps {
            let t = Float(i) / Float(steps)
            let want = Vec3(feet.x + dx * t, feet.y, feet.z + dz * t)
            pos = moveOnce(from: pos, to: want, radius: radius, height: height)
        }
        return pos
    }

    private func moveOnce(from: Vec3, to: Vec3, radius: Float, height: Float) -> Vec3 {
        var candidate = to
        if terrainBlocks(from: from, to: candidate) {
            let xOnly = Vec3(to.x, to.y, from.z), zOnly = Vec3(from.x, to.y, to.z)
            if !terrainBlocks(from: from, to: xOnly) { candidate = xOnly }
            else if !terrainBlocks(from: from, to: zOnly) { candidate = zOnly }
            else { candidate = from }
        }
        // 固いものから押し出す(何度か繰り返して, 角でも抜ける).
        for _ in 0..<3 {
            var moved = false
            for i in solidIndices(nearX: candidate.x, z: candidate.z, radius: radius) {
                let s = solids[i]
                guard s.topY > candidate.y + GameRules.stepHeight, s.baseY < candidate.y + height else { continue }
                if let push = Self.pushOut(s, x: candidate.x, z: candidate.z, radius: radius) {
                    candidate.x += push.0
                    candidate.z += push.1
                    moved = true
                }
            }
            if !moved { break }
        }
        // 押し出されて水や崖の中へ入ったら, 動かなかったことにする.
        if terrainBlocks(from: from, to: candidate) { return from }
        return candidate
    }

    /// 円(中心 x, z・半径 radius)が固いものに食いこんでいるとき, 押し出す量.
    static func pushOut(_ s: Solid, x: Float, z: Float, radius: Float) -> (Float, Float)? {
        let dx = x - s.center.x, dz = z - s.center.z
        if !s.isBox {
            let d2 = dx * dx + dz * dz
            let reach = s.radius + radius
            guard d2 < reach * reach else { return nil }
            let d = d2.squareRoot()
            if d < 1e-5 { return (reach, 0) }
            let k = (reach - d) / d
            return (dx * k, dz * k)
        }
        let (lx, lz) = s.toLocal(dx: dx, dz: dz)
        let cx = clamp(lx, -s.half.x, s.half.x), cz = clamp(lz, -s.half.z, s.half.z)
        let ex = lx - cx, ez = lz - cz
        let d2 = ex * ex + ez * ez
        var pushL: (Float, Float)
        if d2 > 1e-10 {
            guard d2 < radius * radius else { return nil }
            let d = d2.squareRoot()
            let k = (radius - d) / d
            pushL = (ex * k, ez * k)
        } else {
            // 中心が箱の中: いちばん近い面から出す.
            let px = s.half.x - abs(lx), pz = s.half.z - abs(lz)
            if px < pz { pushL = ((lx >= 0 ? 1 : -1) * (px + radius), 0) }
            else { pushL = (0, (lz >= 0 ? 1 : -1) * (pz + radius)) }
        }
        return s.toWorld(lx: pushL.0, lz: pushL.1)
    }

    /// 半径 radius の円が, 固いものと重ならない場所か(出発点を選ぶとき).
    func isClear(x: Float, z: Float, radius: Float) -> Bool {
        for i in solidIndices(nearX: x, z: z, radius: radius) {
            if Self.pushOut(solids[i], x: x, z: z, radius: radius) != nil { return false }
        }
        return true
    }

    // MARK: - 弾の線

    /// 水面か地面か, 線にとっての「地面の高さ」(海へ撃つと水面に当たる).
    private func rayGround(x: Float, z: Float) -> Float {
        terrain.contains(x: x, z: z) ? max(terrain.height(x: x, z: z), waterY) : waterY
    }

    /// origin から direction(長さ 1)へ線をのばし, いちばん近い当たりを返す. 何も無ければ nil.
    func raycast(origin: Vec3, direction: Vec3, maxDistance: Float) -> RayHit? {
        var best: RayHit?
        if let t = terrainHit(origin: origin, direction: direction, maxDistance: maxDistance) {
            let p = origin + direction * t
            let underwater = terrain.contains(x: p.x, z: p.z) ? terrain.height(x: p.x, z: p.z) <= waterY : true
            best = RayHit(distance: t, point: p, normal: underwater ? .up : terrainNormal(x: p.x, z: p.z), surface: .terrain)
        }
        // 線の通り道の近くにある固いものを集める(8 m ごとに, まわりの 3 × 3 区画).
        var candidates: Set<Int> = []
        var t: Float = 0
        let limit = best?.distance ?? maxDistance
        while t <= limit + 8 {
            let p = origin + direction * t
            for i in solidIndices(nearX: p.x, z: p.z, radius: Self.cellSize) { candidates.insert(i) }
            t += 8
        }
        for i in candidates.sorted() {
            if let (d, n) = Self.rayVsSolid(solids[i], origin: origin, direction: direction, maxDistance: best?.distance ?? maxDistance),
               d < (best?.distance ?? .infinity) {
                best = RayHit(distance: d, point: origin + direction * d, normal: n, surface: .obstacle(i))
            }
        }
        return best
    }

    private func terrainHit(origin: Vec3, direction: Vec3, maxDistance: Float) -> Float? {
        func above(_ t: Float) -> Float {
            let p = origin + direction * t
            return p.y - rayGround(x: p.x, z: p.z)
        }
        if above(0) <= 0 { return 0 }
        var prev: Float = 0
        var t: Float = 1
        while true {
            let cur = min(t, maxDistance)
            if above(cur) <= 0 {
                var lo = prev, hi = cur
                for _ in 0..<12 {
                    let mid = (lo + hi) / 2
                    if above(mid) <= 0 { hi = mid } else { lo = mid }
                }
                return hi
            }
            if cur >= maxDistance { return nil }
            prev = cur
            t += 1
        }
    }

    static func rayVsSolid(_ s: Solid, origin: Vec3, direction d: Vec3, maxDistance: Float) -> (Float, Vec3)? {
        if s.isBox {
            let (ox, oz) = s.toLocal(dx: origin.x - s.center.x, dz: origin.z - s.center.z)
            let o = [ox, origin.y - s.center.y, oz]
            let (dxl, dzl) = s.toLocal(dx: d.x, dz: d.z)
            let dir = [dxl, d.y, dzl]
            let h = [s.half.x, s.half.y, s.half.z]
            var tmin: Float = 0, tmax = maxDistance
            var nl = [Float](repeating: 0, count: 3)
            for a in 0..<3 {
                if abs(dir[a]) < 1e-8 {
                    if o[a] < -h[a] || o[a] > h[a] { return nil }
                } else {
                    let t1 = (-h[a] - o[a]) / dir[a], t2 = (h[a] - o[a]) / dir[a]
                    let near = min(t1, t2), far = max(t1, t2)
                    if near > tmin {
                        tmin = near
                        nl = [0, 0, 0]
                        nl[a] = dir[a] > 0 ? -1 : 1
                    }
                    tmax = min(tmax, far)
                    if tmin > tmax { return nil }
                }
            }
            if nl == [0, 0, 0] { return (0, Vec3(-d.x, -d.y, -d.z)) }     // 線の始まりが箱の中
            let (wx, wz) = s.toWorld(lx: nl[0], lz: nl[2])
            return (tmin, Vec3(wx, nl[1], wz))
        }
        // 円柱
        var best: (Float, Vec3)?
        let ox = origin.x - s.center.x, oz = origin.z - s.center.z
        let a = d.x * d.x + d.z * d.z
        if a > 1e-9 {
            let b = 2 * (ox * d.x + oz * d.z)
            let c = ox * ox + oz * oz - s.radius * s.radius
            let disc = b * b - 4 * a * c
            if disc >= 0 {
                let t = (-b - disc.squareRoot()) / (2 * a)
                let y = origin.y + d.y * t
                if t >= 0, t <= maxDistance, y >= s.baseY, y <= s.topY {
                    best = (t, Vec3(ox + d.x * t, 0, oz + d.z * t).normalized(or: .right))
                }
            }
        }
        if abs(d.y) > 1e-8 {
            for (capY, n) in [(s.topY, Vec3(0, 1, 0)), (s.baseY, Vec3(0, -1, 0))] {
                let t = (capY - origin.y) / d.y
                guard t >= 0, t <= maxDistance, t < (best?.0 ?? .infinity) else { continue }
                let px = ox + d.x * t, pz = oz + d.z * t
                if px * px + pz * pz <= s.radius * s.radius { best = (t, n) }
            }
        }
        return best
    }

    // MARK: - 出発点

    /// 中心 (cx, cz) のまわりの円(半径 radius × fraction)の上に, count 人ぶんの出発点を同じ間かくで選ぶ.
    /// 水・急な坂・固いものの上は 5 度ずつずらして探す. 中心を向く. 見つからなければ nil.
    func arenaSpawns(centerX cx: Float, centerZ cz: Float, radius: Float, count: Int, fraction: Float = 0.85,
                     angleOffset: Float = 0) -> [(position: Vec3, yaw: Float)]? {
        guard count > 0 else { return [] }
        let r = radius * fraction
        var out: [(position: Vec3, yaw: Float)] = []
        for i in 0..<count {
            let base = angleOffset + 2 * .pi * Float(i) / Float(count)
            var found: (position: Vec3, yaw: Float)?
            for k in 0..<37 {
                let sign: Float = k % 2 == 0 ? 1 : -1
                let angle = base + sign * Float((k + 1) / 2) * (5 * .pi / 180)
                let x = cx + r * cos(angle), z = cz + r * sin(angle)
                let h = terrainHeight(x: x, z: z)
                guard h > GameRules.minGroundY + 0.5, h > waterY + 0.2,
                      terrainNormal(x: x, z: z).y >= GameRules.walkableNormalY + 0.1,
                      isClear(x: x, z: z, radius: GameRules.playerRadius + 0.6) else { continue }
                // 固いものの天面の上ではなく, 地面に立つ.
                found = (Vec3(x, h, z), atan2(cx - x, -(cz - z)))
                break
            }
            guard let f = found else { return nil }
            out.append(f)
        }
        // たがいに 30 m 以上はなれていること.
        for i in 0..<out.count {
            for j in (i + 1)..<max(out.count, i + 1) where (out[i].position - out[j].position).length < 30 { return nil }
        }
        return out
    }
}
