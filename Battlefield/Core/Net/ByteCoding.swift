import Foundation

/// バイト列を書く道具(リトルエンディアン). 通信の形は `docs/NETCODE.md` §4.
struct ByteWriter {
    private(set) var data = Data()

    mutating func u8(_ v: Int) { data.append(UInt8(clamping: v)) }
    mutating func u16(_ v: Int) {
        let x = UInt16(clamping: v)
        data.append(UInt8(x & 0xFF)); data.append(UInt8(x >> 8))
    }
    mutating func u32(_ v: UInt32) { for i in 0..<4 { data.append(UInt8((v >> (8 * UInt32(i))) & 0xFF)) } }
    mutating func u64(_ v: UInt64) { for i in 0..<8 { data.append(UInt8((v >> (8 * UInt64(i))) & 0xFF)) } }
    mutating func i8(_ v: Int) { data.append(UInt8(bitPattern: Int8(clamping: v))) }
    mutating func i16(_ v: Int) {
        let x = UInt16(bitPattern: Int16(clamping: v))
        data.append(UInt8(x & 0xFF)); data.append(UInt8(x >> 8))
    }

    /// 1 = 1 cm. ±327 m.
    mutating func position(_ v: Vec3) { i16(Int((v.x * 100).rounded())); i16(Int((v.y * 100).rounded())); i16(Int((v.z * 100).rounded())) }
    /// 0〜65535 が 0〜2π.
    mutating func angle(_ a: Float) {
        var t = a.truncatingRemainder(dividingBy: 2 * .pi)
        if t < 0 { t += 2 * .pi }
        u16(Int((t / (2 * .pi) * 65536).rounded()) & 0xFFFF)
    }
    /// ±127 が ±π/2.
    mutating func pitch(_ p: Float) { i8(Int((p / (.pi / 2) * 127).rounded())) }
    /// 1 = 0.25 m/s.
    mutating func velocity(_ v: Vec3) { i8(Int((v.x * 4).rounded())); i8(Int((v.y * 4).rounded())); i8(Int((v.z * 4).rounded())) }
    /// ホストの時計(秒)を ms にする.
    mutating func time(_ seconds: Double) { u32(UInt32(clamping: Int((seconds * 1000).rounded()))) }
    /// 1 = 0.1 m.
    mutating func distance(_ d: Float) { u16(Int((d * 10).rounded())) }
    /// 円: 中心(cm)と半径(10 cm).
    mutating func circle(_ c: Disc) { i16(Int((c.x * 100).rounded())); i16(Int((c.z * 100).rounded())); u16(Int((c.r * 10).rounded())) }
    /// 名前: 長さ 1 バイト + UTF-8(24 バイトまで. 文字の途中で切らない).
    mutating func name(_ s: String) {
        var bytes = Array(s.utf8)
        while bytes.count > 24 { bytes.removeLast() }
        while !bytes.isEmpty, String(bytes: bytes, encoding: .utf8) == nil { bytes.removeLast() }
        u8(bytes.count)
        data.append(contentsOf: bytes)
    }
}

/// バイト列を読む道具. 長さが足りないときは `ok` が false になり, 0 を返す(落ちない).
struct ByteReader {
    private let data: [UInt8]
    private var pos = 0
    private(set) var ok = true

    init(_ d: Data) { data = [UInt8](d) }

    var remaining: Int { data.count - pos }

    private mutating func take(_ n: Int) -> ArraySlice<UInt8>? {
        guard ok, n >= 0, pos + n <= data.count else { ok = false; return nil }
        defer { pos += n }
        return data[pos..<(pos + n)]
    }

    mutating func u8() -> Int { Int(take(1)?.first ?? 0) }
    mutating func u16() -> Int {
        guard let b = take(2) else { return 0 }
        return Int(b[b.startIndex]) | Int(b[b.startIndex + 1]) << 8
    }
    mutating func u32() -> UInt32 {
        guard let b = take(4) else { return 0 }
        var v: UInt32 = 0
        for i in 0..<4 { v |= UInt32(b[b.startIndex + i]) << (8 * UInt32(i)) }
        return v
    }
    mutating func u64() -> UInt64 {
        guard let b = take(8) else { return 0 }
        var v: UInt64 = 0
        for i in 0..<8 { v |= UInt64(b[b.startIndex + i]) << (8 * UInt64(i)) }
        return v
    }
    mutating func i8() -> Int { Int(Int8(bitPattern: UInt8(u8()))) }
    mutating func i16() -> Int { Int(Int16(bitPattern: UInt16(u16()))) }

    mutating func position() -> Vec3 { Vec3(Float(i16()) / 100, Float(i16()) / 100, Float(i16()) / 100) }
    mutating func angle() -> Float { Float(u16()) / 65536 * 2 * .pi }
    mutating func pitch() -> Float { Float(i8()) / 127 * (.pi / 2) }
    mutating func velocity() -> Vec3 { Vec3(Float(i8()) / 4, Float(i8()) / 4, Float(i8()) / 4) }
    mutating func time() -> Double { Double(u32()) / 1000 }
    mutating func distance() -> Float { Float(u16()) / 10 }
    mutating func circle() -> Disc { Disc(x: Float(i16()) / 100, z: Float(i16()) / 100, r: Float(u16()) / 10) }
    mutating func name() -> String {
        let n = u8()
        guard let b = take(n) else { return "" }
        return String(bytes: b, encoding: .utf8) ?? "?"
    }
}
