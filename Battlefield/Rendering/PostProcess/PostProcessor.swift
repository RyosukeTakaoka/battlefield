import Metal
import RealityKit
import simd
import UIKit

/// ARView の後処理(`renderCallbacks.postProcess`)で, 霧と色の調整をかける.
///
/// RealityKit(iPad)には距離の霧が無いので, 描き終わった画面と奥行きの画像を使って
/// 自分でかける(`Fog.metal`). 使えない端末では何もしない(霧なしで表示される).
///
/// 後処理は描画のスレッドから呼ばれることがあるので, メインスレッド専用にはしない.
/// 設定(霧の色など)はゲームの側から書き換えるので, 鍵(NSLock)をかけて読み書きする.
final class PostProcessor: @unchecked Sendable {
    struct Settings {
        var fogColorSRGB: SIMD3<Float>
        var fogStart: Float
        var fogEnd: Float
        var fogMax: Float = 0.82
        var vignette: Float = 0.16
        var saturation: Float = 1.06
        var flash: Float = 0
        /// これより遠い(= 空のドーム)には霧をかけない.
        var skyDistance: Float = 2300
    }

    /// Fog.metal の FogUniforms と同じ並び.
    private struct Uniforms {
        var projection: simd_float4x4
        var fogColor: SIMD4<Float>
        var fogStart: Float
        var fogEnd: Float
        var fogMax: Float
        var skyDistance: Float
        var vignette: Float
        var saturation: Float
        var flash: Float
        var encodeSRGB: Float
    }

    private let lock = NSLock()
    private var _settings: Settings
    var settings: Settings {
        get { lock.lock(); defer { lock.unlock() }; return _settings }
        set { lock.lock(); _settings = newValue; lock.unlock() }
    }
    private var pipeline: MTLComputePipelineState?

    init(settings: Settings) { _settings = settings }

    @MainActor
    func attach(to view: ARView) {
        view.renderCallbacks.prepareWithDevice = { [weak self] device in
            self?.prepare(device: device)
        }
        view.renderCallbacks.postProcess = { [weak self] context in
            self?.process(context)
        }
    }

    @MainActor
    func detach(from view: ARView) {
        view.renderCallbacks.postProcess = nil
        view.renderCallbacks.prepareWithDevice = nil
    }

    private func prepare(device: MTLDevice) {
        guard let library = device.makeDefaultLibrary(),
              let function = library.makeFunction(name: "paperPlanePostProcess") else { return }
        pipeline = try? device.makeComputePipelineState(function: function)
    }

    private func process(_ context: ARView.PostProcessContext) {
        guard let pipeline, let encoder = context.commandBuffer.makeComputeCommandEncoder() else {
            // 後処理が使えないときは, そのまま写す.
            if let blit = context.commandBuffer.makeBlitCommandEncoder() {
                blit.copy(from: context.sourceColorTexture, to: context.targetColorTexture)
                blit.endEncoding()
            }
            return
        }
        let target = context.targetColorTexture
        // 8bit で sRGB の数値をそのまま持つ形式なら, 霧の色も sRGB のまま使う.
        let srgbValues = [MTLPixelFormat.bgra8Unorm, .rgba8Unorm].contains(target.pixelFormat)
        let s = settings
        let fog = srgbValues ? s.fogColorSRGB : s.fogColorSRGB.linearFromSRGB
        var u = Uniforms(projection: context.projection,
                         fogColor: SIMD4(fog, 1),
                         fogStart: s.fogStart, fogEnd: s.fogEnd, fogMax: s.fogMax,
                         skyDistance: s.skyDistance, vignette: s.vignette, saturation: s.saturation,
                         flash: s.flash, encodeSRGB: srgbValues ? 1 : 0)
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(context.sourceColorTexture, index: 0)
        encoder.setTexture(context.sourceDepthTexture, index: 1)
        encoder.setTexture(target, index: 2)
        encoder.setBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
        let tw = pipeline.threadExecutionWidth
        let th = max(1, pipeline.maxTotalThreadsPerThreadgroup / tw)
        encoder.dispatchThreads(MTLSize(width: target.width, height: target.height, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: tw, height: th, depth: 1))
        encoder.endEncoding()
    }
}

extension SIMD3 where Scalar == Float {
    /// sRGB の数値 → 光の強さ(線形).
    var linearFromSRGB: SIMD3<Float> {
        func f(_ c: Float) -> Float { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return SIMD3(f(x), f(y), f(z))
    }
}
