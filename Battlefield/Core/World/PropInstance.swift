import Foundation

/// 小物 1 つぶん(見た目だけ. 当たり判定は `MapData.obstacles` が別に持つ).
/// JSON では配列 `[名前, 番号, x, y, z, 向き, sx, sy, sz]`(Airplane と同じ).
struct PropInstance: Codable, Equatable {
    var name: String
    var variant: Int
    var position: Vec3
    var yaw: Float
    var scale: Vec3

    init(name: String, variant: Int = 0, position: Vec3, yaw: Float = 0, scale: Vec3 = Vec3(1, 1, 1)) {
        self.name = name
        self.variant = variant
        self.position = position
        self.yaw = yaw
        self.scale = scale
    }

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        name = try c.decode(String.self)
        variant = try c.decode(Int.self)
        let x = try c.decode(Float.self), y = try c.decode(Float.self), z = try c.decode(Float.self)
        position = Vec3(x, y, z)
        yaw = try c.decode(Float.self)
        let sx = try c.decode(Float.self), sy = try c.decode(Float.self), sz = try c.decode(Float.self)
        scale = Vec3(sx, sy, sz)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(name)
        try c.encode(variant)
        try c.encode(position.x)
        try c.encode(position.y)
        try c.encode(position.z)
        try c.encode(yaw)
        try c.encode(scale.x)
        try c.encode(scale.y)
        try c.encode(scale.z)
    }
}

/// `[x, y, z]` → Vec3. 足りない要素は 0.
func vec(_ a: [Float]) -> Vec3 {
    Vec3(a.count > 0 ? a[0] : 0, a.count > 1 ? a[1] : 0, a.count > 2 ? a[2] : 0)
}
