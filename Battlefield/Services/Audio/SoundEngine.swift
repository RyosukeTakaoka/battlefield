import AVFoundation
import Foundation

/// 効果音. 音声ファイルを使わず, 起動時にその場で波形を作る(Airplane の方式).
///
/// - 武器 4 種の発射音・リロード・弾切れ
/// - 当たった(体 / 頭)・撃たれた・やられた・ひろった
/// - ラウンドの勝ち・負け・カウントダウン・円の警告・ボタン
///
/// 消音スイッチに従う(`.ambient`). ほかのアプリの音も止めない.
@MainActor
final class SoundEngine {
    enum Effect: CaseIterable {
        case shotHandgun, shotRifle, shotShotgun, shotSniper
        case reload, empty, switchWeapon
        case hit, headshot, hurt, eliminated, pickup, heal
        case roundWin, roundLose, countdown, go, zoneWarning, tap, step
    }

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var buffers: [Effect: AVAudioPCMBuffer] = [:]
    private let format: AVAudioFormat
    private var started = false
    var volume: Float = 0.8 { didSet { engine.mainMixerNode.outputVolume = volume } }

    init() {
        format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        for _ in 0..<10 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
            players.append(p)
        }
        for effect in Effect.allCases { buffers[effect] = Self.synthesize(effect, format: format) }
    }

    func start() {
        guard !started else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, options: [.mixWithOthers])
            try session.setActive(true)
            engine.mainMixerNode.outputVolume = volume
            try engine.start()
            started = true
            players.forEach { $0.play() }
        } catch {
            started = false
        }
    }

    func stop() {
        guard started else { return }
        players.forEach { $0.stop() }
        engine.stop()
        started = false
    }

    func play(_ effect: Effect, gain: Float = 1) {
        guard started, let buffer = buffers[effect] else { return }
        let p = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        p.volume = gain
        p.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !p.isPlaying { p.play() }
    }

    // MARK: - 波形を作る

    private static func buffer(_ format: AVAudioFormat, seconds: Double, _ fill: (Int, Double) -> Float) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(seconds * format.sampleRate)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let ch = buf.floatChannelData?[0] else { return nil }
        buf.frameLength = frames
        for i in 0..<Int(frames) { ch[i] = fill(i, Double(i) / format.sampleRate) }
        return buf
    }

    /// 鐘のような音(基音 + 倍音. ゆっくり消える).
    private static func bell(_ t: Double, freq: Double, decay: Double = 5) -> Double {
        let env = exp(-t * decay) * min(1, t * 400)
        return env * (sin(2 * .pi * freq * t) * 0.6 + sin(2 * .pi * freq * 2.01 * t) * 0.25
            + sin(2 * .pi * freq * 3.98 * t) * 0.1)
    }

    private static func synthesize(_ effect: Effect, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        var rng = SystemRandomNumberGenerator()
        func noise() -> Double { Double.random(in: -1...1, using: &rng) }
        switch effect {
        case .shotHandgun:
            var lp = 0.0
            return buffer(format, seconds: 0.25) { _, t in
                lp += (noise() - lp) * 0.35
                return Float((lp * exp(-t * 28) * 0.9 + sin(2 * .pi * 170 * t) * exp(-t * 30) * 0.5) * 0.9)
            }
        case .shotRifle:
            var lp = 0.0
            return buffer(format, seconds: 0.18) { _, t in
                lp += (noise() - lp) * 0.45
                return Float((lp * exp(-t * 34) * 0.9 + sin(2 * .pi * 140 * t) * exp(-t * 40) * 0.45) * 0.8)
            }
        case .shotShotgun:
            var lp = 0.0
            return buffer(format, seconds: 0.5) { _, t in
                lp += (noise() - lp) * 0.2
                return Float((lp * exp(-t * 12) * 1.1 + sin(2 * .pi * 90 * t) * exp(-t * 14) * 0.7) * 0.9)
            }
        case .shotSniper:
            var lp = 0.0
            return buffer(format, seconds: 0.9) { _, t in
                lp += (noise() - lp) * 0.15
                return Float((lp * exp(-t * 7) * 0.9 + sin(2 * .pi * 70 * t) * exp(-t * 6) * 0.8
                              + sin(2 * .pi * 600 * t) * exp(-t * 60) * 0.3) * 0.9)
            }
        case .reload:
            return buffer(format, seconds: 0.35) { _, t in
                Float((sin(2 * .pi * 1200 * t) * exp(-t * 60) + sin(2 * .pi * 700 * max(0, t - 0.2)) * exp(-max(0, t - 0.2) * 60) * (t > 0.2 ? 1 : 0)) * 0.25)
            }
        case .empty:
            return buffer(format, seconds: 0.1) { _, t in Float(sin(2 * .pi * 500 * t) * exp(-t * 70) * 0.25) }
        case .switchWeapon:
            return buffer(format, seconds: 0.18) { _, t in Float(sin(2 * .pi * 420 * t) * exp(-t * 40) * 0.25) }
        case .hit:
            return buffer(format, seconds: 0.1) { _, t in Float(sin(2 * .pi * 1500 * t) * exp(-t * 55) * 0.3) }
        case .headshot:
            return buffer(format, seconds: 0.25) { _, t in
                Float((sin(2 * .pi * 2200 * t) * exp(-t * 30) + sin(2 * .pi * 1100 * t) * exp(-t * 20) * 0.6) * 0.3)
            }
        case .hurt:
            var lp = 0.0
            return buffer(format, seconds: 0.3) { _, t in
                lp += (noise() - lp) * 0.12
                return Float((lp * exp(-t * 14) + sin(2 * .pi * 110 * t) * exp(-t * 12) * 0.5) * 0.8)
            }
        case .eliminated:
            return buffer(format, seconds: 0.9) { _, t in
                let f = 330 * pow(0.45, t / 0.9)
                return Float(sin(2 * .pi * f * t) * exp(-t * 2.4) * 0.3)
            }
        case .pickup:
            return buffer(format, seconds: 0.4) { _, t in
                var v = 0.0
                for (k, f) in [1046.5, 1568.0].enumerated() where t > Double(k) * 0.06 { v += bell(t - Double(k) * 0.06, freq: f, decay: 8) }
                return Float(v * 0.25)
            }
        case .heal:
            return buffer(format, seconds: 0.6) { _, t in
                var v = 0.0
                for (k, f) in [784.0, 988.0, 1318.5].enumerated() where t > Double(k) * 0.07 { v += bell(t - Double(k) * 0.07, freq: f, decay: 6) }
                return Float(v * 0.22)
            }
        case .roundWin:
            return buffer(format, seconds: 1.6) { _, t in
                let notes = [(0.0, 784.0), (0.12, 1046.5), (0.24, 1318.5), (0.4, 1568.0)]
                var v = 0.0
                for (start, f) in notes where t > start { v += bell(t - start, freq: f, decay: 2.8) }
                return Float(v * 0.22)
            }
        case .roundLose:
            return buffer(format, seconds: 1.0) { _, t in
                let f = 392 * pow(0.5, t / 1.0)
                return Float(sin(2 * .pi * f * t) * exp(-t * 2.2) * 0.28)
            }
        case .countdown:
            return buffer(format, seconds: 0.25) { _, t in Float(sin(2 * .pi * 880 * t) * exp(-t * 14) * 0.3) }
        case .go:
            return buffer(format, seconds: 0.6) { _, t in Float(bell(t, freq: 1760, decay: 4) * 0.35) }
        case .zoneWarning:
            return buffer(format, seconds: 0.5) { _, t in
                Float(sin(2 * .pi * 660 * t) * (sin(2 * .pi * 10 * t) > 0 ? 1 : 0.2) * exp(-t * 4) * 0.25)
            }
        case .tap:
            return buffer(format, seconds: 0.12) { _, t in Float(sin(2 * .pi * 880 * t) * exp(-t * 40) * 0.25) }
        case .step:
            var lp = 0.0
            return buffer(format, seconds: 0.08) { _, t in
                lp += (noise() - lp) * 0.2
                return Float(lp * exp(-t * 50) * 0.3)
            }
        }
    }
}
