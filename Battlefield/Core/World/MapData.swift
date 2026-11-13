import Foundation

/// 島 1 つぶんのデータ(`Resources/Maps/<id>.json`. `Tools/map/build_arena.py` が作る).
///
/// 座標は Y が上, 単位はメートル, -Z が前. 島の中心が原点.
struct MapData: Codable, Equatable {
    struct Sun: Codable, Equatable {
        var direction: [Float]
        var color: [Float]
        var intensity: Float
    }

    struct Fog: Codable, Equatable {
        var color: [Float]
        var start: Float
        var end: Float
    }

    /// 弾と体をさえぎる固いもの(見た目の小物とは別に持つ).
    /// - `box`: `p` = 箱の中心, `half` = 半分の大きさ(x, y, z), `yaw` = Y 軸まわりの回転(小物の向きと同じ約束)
    /// - `cyl`: `p` = 底の中心, `r` = 半径, `h` = 高さ
    struct Obstacle: Codable, Equatable {
        enum Shape: String, Codable { case box, cyl }
        var shape: Shape
        var p: [Float]
        var half: [Float]?
        var yaw: Float?
        var r: Float?
        var h: Float?

        static func box(center: Vec3, half: Vec3, yaw: Float = 0) -> Obstacle {
            Obstacle(shape: .box, p: [center.x, center.y, center.z], half: [half.x, half.y, half.z], yaw: yaw, r: nil, h: nil)
        }

        static func cylinder(base: Vec3, radius: Float, height: Float) -> Obstacle {
            Obstacle(shape: .cyl, p: [base.x, base.y, base.z], half: nil, yaw: nil, r: radius, h: height)
        }
    }

    /// 名所(ラウンド戦・キル勝負の場所). `p` は [x, z].
    struct POI: Codable, Equatable {
        var name: String
        var p: [Float]
        var r: Float
        var center: (x: Float, z: Float) { (p.count > 0 ? p[0] : 0, p.count > 1 ? p[1] : 0) }

        static func == (a: POI, b: POI) -> Bool { a.name == b.name && a.p == b.p && a.r == b.r }
    }

    var id: String
    var name: String
    var waterY: Float = 0
    var sun = Sun(direction: [0.4, 0.8, 0.45], color: [1, 0.96, 0.9], intensity: 9000)
    var ambient: Float = 1
    var sky: String = "Sky_island"
    var fog = Fog(color: [0.78, 0.86, 0.95], start: 150, end: 700)
    /// 見た目だけの小物.
    var props: [PropInstance] = []
    var obstacles: [Obstacle] = []
    /// バトルロイヤルの出発点(島のふち). [x, z].
    var spawns: [[Float]] = []
    /// ひろうものの置き場. [x, y, z].
    var loot: [[Float]] = []
    var pois: [POI] = []

    static func decode(from data: Data) throws -> MapData {
        try JSONDecoder().decode(MapData.self, from: data)
    }
}
