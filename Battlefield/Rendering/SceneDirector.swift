import Combine
import Foundation
import RealityKit
import UIKit

/// RealityKit の画面を受け持つ. ルールは知らず, 渡された状態を描くだけ(Airplane の `SceneDirector` と同じ作り).
///
/// - ARView を「AR を使わないモード」で作り, 自分で置いたカメラから描く.
/// - 太陽(影つき)と, 空の画像からの環境光で照らす. 霧は後処理(`PostProcessor`).
/// - 毎コマ `onUpdate` を呼ぶ.
@MainActor
final class SceneDirector {
    let view: ARView
    var onUpdate: ((Float) -> Void)?

    private let anchor = AnchorEntity(world: .zero)
    private let camera = PerspectiveCamera()
    private let sun = DirectionalLight()
    private var post: PostProcessor?
    private var subscription: Cancellable?
    private var flashLevel: Float = 0

    /// 明るさの調整つまみ(実機で見て合わせる. Airplane と同じ値から始める).
    static let sunIntensityScale: Float = 0.33
    static let ambientExposureOffset: Float = 0.5

    init(quality: GameSettings.Quality) {
        view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.renderOptions.insert([.disableMotionBlur, .disableDepthOfField, .disablePersonOcclusion,
                                   .disableGroundingShadows, .disableCameraGrain, .disableAREnvironmentLighting])
        if quality == .standard { view.renderOptions.insert(.disableHDR) }
        view.environment.background = .color(UIColor(red: 0.8, green: 0.88, blue: 0.97, alpha: 1))
        camera.camera.near = 0.08
        camera.camera.far = 4000
        camera.camera.fieldOfViewInDegrees = 60
        anchor.addChild(camera)
        anchor.addChild(sun)
        view.scene.addAnchor(anchor)
        subscription = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            self?.onUpdate?(Float(event.deltaTime))
        }
    }

    /// 島・人・演出を置く.
    func install(arena: ArenaScene, characters: Entity, effects: Entity, map: MapData, assets: AssetLibrary,
                 quality: GameSettings.Quality) {
        anchor.addChild(arena.root)
        anchor.addChild(characters)
        anchor.addChild(effects)

        // 太陽: JSON の向き・色・強さ.
        let toSun = vec(map.sun.direction).normalized(or: .up)
        sun.light.color = UIColor(srgb: map.sun.color)
        sun.light.intensity = map.sun.intensity * Self.sunIntensityScale
        sun.look(at: .zero, from: toSun * 200, relativeTo: nil)
        sun.shadow = DirectionalLightComponent.Shadow(maximumDistance: quality == .high ? 60 : 30, depthBias: 2.0)

        // 環境光: 空の画像そのものから. 作り終わるまで(非同期)は標準の環境光.
        if let image = assets.cgImage(map.sky, ext: "png") {
            Task { @MainActor [weak self] in
                guard let env = try? await EnvironmentResource(equirectangular: image) else { return }
                self?.view.environment.lighting.resource = env
            }
        }
        view.environment.lighting.intensityExponent = log2(max(map.ambient, 0.1)) + Self.ambientExposureOffset
        view.environment.background = .color(UIColor(srgb: map.fog.color))

        let processor = PostProcessor(settings: .init(fogColorSRGB: vec(map.fog.color), fogStart: map.fog.start,
                                                      fogEnd: map.fog.end, vignette: quality == .high ? 0.16 : 0,
                                                      skyDistance: ArenaScene.skyRadius - 300))
        post?.detach(from: view)
        processor.attach(to: view)
        post = processor
    }

    /// 毎コマ: カメラを置く.
    func setCamera(_ pose: ThirdPersonCamera.Pose) {
        camera.look(at: pose.position + pose.forward * 20, from: pose.position, relativeTo: nil)
        camera.camera.fieldOfViewInDegrees = pose.verticalFOV * 180 / .pi
    }

    /// 画面の白さ・色(円の外にいるときの色みなど). 0〜1.
    func setFlash(_ level: Float) {
        guard abs(level - flashLevel) > 0.005, var s = post?.settings else { return }
        flashLevel = level
        s.flash = level
        post?.settings = s
    }

    func tearDown() {
        subscription?.cancel()
        subscription = nil
        post?.detach(from: view)
        onUpdate = nil
    }
}
