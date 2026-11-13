import AVFoundation
import Foundation

/// 効果音. 音声ファイルを使わず, 起動時にその場で波形を作る.
///
/// - 風の音: ノイズをくり返し流し, 速さに合わせて音量と明るさ(フィルタ)を変える.
/// - リング: 澄んだ鐘の音(パーフェクトとブーストは音を足す).
/// - 投げる・着地・水しぶき・ゴール・ボタン.
///
/// 授業中に音が出ないよう, 消音スイッチに従う(`.ambient`). ほかのアプリの音も止めない.
@MainActor
final class SoundEngine {
    enum Effect: CaseIterable {
        case launch, ring, ringPerfect, boost, combo, updraft, stall, landGround, landWater, landCloud, finish, tap
        case gem, checkpoint, warp, fail, countdown, go, skid, boss
    }

    private let engine = AVAudioEngine()
    private let windPlayer = AVAudioPlayerNode()
    private let windEQ = AVAudioUnitEQ(numberOfBands: 1)
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var buffers: [Effect: AVAudioPCMBuffer] = [:]
    private let format: AVAudioFormat
    private var started = false
    var volume: Float = 0.8 { didSet { engine.mainMixerNode.outputVolume = volume } }

    init() {
        format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        windEQ.bands[0].filterType = .lowPass
        windEQ.bands[0].frequency = 600
        windEQ.bands[0].bypass = false
        engine.attach(windPlayer)
        engine.attach(windEQ)
        engine.connect(windPlayer, to: windEQ, format: format)
        engine.connect(windEQ, to: engine.mainMixerNode, format: format)
        for _ in 0..<6 {
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
            if let wind = Self.windLoop(format: format) {
                windPlayer.scheduleBuffer(wind, at: nil, options: .loops)
                windPlayer.volume = 0
                windPlayer.play()
            }
            players.forEach { $0.play() }
        } catch {
            started = false
        }
    }

    func stop() {
        guard started else { return }
        windPlayer.stop()
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

    /// 風の音. speed01 は 0〜1(速いほど大きく, 高い音が増える).
    func setWind(speed01: Float, active: Bool) {
        guard started else { return }
        let target = active ? 0.08 + speed01 * 0.32 : 0
        windPlayer.volume += (target - windPlayer.volume) * 0.15
        windEQ.bands[0].frequency = 350 + speed01 * 1600
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
        case .ring:
            return buffer(format, seconds: 0.9) { _, t in
                Float((bell(t, freq: 1046.5) + bell(max(0, t - 0.07), freq: 1318.5) * (t > 0.07 ? 1 : 0)) * 0.35)
            }
        case .ringPerfect:
            return buffer(format, seconds: 1.1) { _, t in
                let notes = [1046.5, 1318.5, 1568.0, 2093.0]
                var v = 0.0
                for (k, f) in notes.enumerated() where t > Double(k) * 0.06 { v += bell(t - Double(k) * 0.06, freq: f) }
                return Float(v * 0.24)
            }
        case .boost:
            return buffer(format, seconds: 0.8) { _, t in
                let sweep = sin(2 * .pi * (400 * t + 900 * t * t)) * exp(-t * 3) * 0.3
                return Float(sweep + bell(t, freq: 1568) * 0.2)
            }
        case .combo:
            return buffer(format, seconds: 0.5) { _, t in Float(bell(t, freq: 2349.3, decay: 8) * 0.25) }
        case .launch:
            var lp = 0.0
            return buffer(format, seconds: 0.6) { _, t in
                lp += (noise() - lp) * (0.05 + t * 0.4)
                return Float(lp * sin(min(1, t / 0.6) * .pi) * 0.9)
            }
        case .updraft:
            var lp = 0.0
            return buffer(format, seconds: 1.2) { _, t in
                lp += (noise() - lp) * 0.08
                return Float(lp * sin(t / 1.2 * .pi) * 0.5 + sin(2 * .pi * (300 + 200 * t) * t) * 0.05 * exp(-t))
            }
        case .stall:
            return buffer(format, seconds: 0.45) { _, t in
                Float(sin(2 * .pi * 220 * t) * (sin(2 * .pi * 18 * t) > 0 ? 1 : 0.3) * exp(-t * 4) * 0.25)
            }
        case .landGround:
            var lp = 0.0
            return buffer(format, seconds: 0.5) { _, t in
                lp += (noise() - lp) * 0.12
                return Float(lp * exp(-t * 9) * 1.2 + sin(2 * .pi * 90 * t) * exp(-t * 14) * 0.4)
            }
        case .landWater:
            var lp = 0.0
            return buffer(format, seconds: 0.9) { _, t in
                lp += (noise() - lp) * (0.3 - t * 0.25)
                return Float(lp * exp(-t * 4) * 0.9)
            }
        case .landCloud:
            var lp = 0.0
            return buffer(format, seconds: 0.8) { _, t in
                lp += (noise() - lp) * 0.04
                return Float(lp * sin(t / 0.8 * .pi) * 1.4)
            }
        case .finish:
            return buffer(format, seconds: 1.8) { _, t in
                let notes = [(0.0, 784.0), (0.12, 1046.5), (0.24, 1318.5), (0.36, 1568.0), (0.6, 2093.0)]
                var v = 0.0
                for (start, f) in notes where t > start { v += bell(t - start, freq: f, decay: 2.5) }
                return Float(v * 0.2)
            }
        case .tap:
            return buffer(format, seconds: 0.12) { _, t in Float(sin(2 * .pi * 880 * t) * exp(-t * 40) * 0.25) }
        case .gem:
            // きらきら: 高い鐘を 3 つ, すばやく.
            return buffer(format, seconds: 0.7) { _, t in
                var v = 0.0
                for (k, f) in [2637.0, 3136.0, 3951.0].enumerated() where t > Double(k) * 0.045 {
                    v += bell(t - Double(k) * 0.045, freq: f, decay: 9)
                }
                return Float(v * 0.18)
            }
        case .checkpoint:
            return buffer(format, seconds: 1.4) { _, t in
                let notes = [(0.0, 1046.5), (0.1, 1568.0), (0.2, 2093.0)]
                var v = 0.0
                for (start, f) in notes where t > start { v += bell(t - start, freq: f, decay: 3.5) }
                return Float(v * 0.22)
            }
        case .warp:
            // 吸いこまれるような音: 上がっていく音 + 風.
            var lp = 0.0
            return buffer(format, seconds: 2.2) { _, t in
                lp += (noise() - lp) * (0.02 + t * 0.12)
                let sweep = sin(2 * .pi * (180 * t + 260 * t * t)) * exp(-pow(t - 1.0, 2) * 1.5) * 0.18
                return Float(lp * sin(min(t / 2.2, 1) * .pi) * 0.9 + sweep)
            }
        case .fail:
            return buffer(format, seconds: 0.9) { _, t in
                let f = 440 * pow(0.5, t / 0.9)
                return Float(sin(2 * .pi * f * t) * exp(-t * 2.5) * 0.25)
            }
        case .countdown:
            return buffer(format, seconds: 0.25) { _, t in Float(sin(2 * .pi * 880 * t) * exp(-t * 14) * 0.3) }
        case .go:
            return buffer(format, seconds: 0.6) { _, t in Float(bell(t, freq: 1760, decay: 4) * 0.35) }
        case .boss:
            // ボスの登場: 低いどん, どん, と高い警告の音.
            return buffer(format, seconds: 1.6) { _, t in
                var v = 0.0
                for start in [0.0, 0.35, 0.7] where t > start {
                    let u = t - start
                    v += sin(2 * .pi * 70 * u) * exp(-u * 7) * 0.6
                }
                v += sin(2 * .pi * (660 + 110 * sin(t * 18)) * t) * exp(-pow(t - 0.9, 2) * 6) * 0.12
                return Float(v)
            }
        case .skid:
            var lp = 0.0
            return buffer(format, seconds: 0.35) { _, t in
                lp += (noise() - lp) * 0.3
                return Float(lp * exp(-t * 10) * 0.6)
            }
        }
    }

    private static func windLoop(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        // 2 秒のノイズ. 端をなめらかにつないで, くり返しても「ぷつっ」と鳴らないようにする.
        var rng = SystemRandomNumberGenerator()
        var lp = 0.0
        let seconds = 2.0
        let n = Int(seconds * format.sampleRate)
        var raw = [Double](repeating: 0, count: n)
        for i in 0..<n {
            lp += (Double.random(in: -1...1, using: &rng) - lp) * 0.2
            raw[i] = lp
        }
        let fade = Int(0.1 * format.sampleRate)
        return buffer(format, seconds: seconds) { i, _ in
            var v = raw[i]
            if i < fade {
                let w = Double(i) / Double(fade)
                v = raw[i] * w + raw[n - fade + i] * (1 - w)
            }
            return Float(v * 0.8)
        }
    }
}
