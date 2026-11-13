import Foundation

/// ロードのどこに時間がかかったかを, Xcode の下の欄(コンソール)に出す.
/// 例: `[ロード] 小物の形を読む(13 種類): 0.82 秒(ここまで 1.10 秒)`
/// ロードが長いと感じたら, この行をそのまま AI に貼ってもらう.
@MainActor
enum LoadTimer {
    private static var start: Date?
    private static var last: Date?

    static func lap(_ label: String) {
        let now = Date()
        if start == nil { start = now; last = now }
        let step = now.timeIntervalSince(last ?? now)
        let total = now.timeIntervalSince(start ?? now)
        print(String(format: "[ロード] %@: %.2f 秒(ここまで %.2f 秒)", label, step, total))
        last = now
    }

    static func done() {
        lap("おわり")
        start = nil
        last = nil
    }
}
