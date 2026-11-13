import Foundation
import RealityKit
import UIKit

/// 弾の線・火花など(数を決めて 使い回す. 毎コマ 材質やメッシュを作り直さない).
@MainActor
final class CombatEffects {
    let root = Entity()

    private struct Item {
        let entity: ModelEntity
        var life: Float = 0
        var total: Float = 0.1
    }
    private var tracers: [Item] = []
    private var sparks: [Item] = []
    private var nextTracer = 0
    private var nextSpark = 0

    init() {
        let tracerMesh = MeshResource.generateBox(size: SIMD3(0.025, 0.025, 1))
        let tracerMaterial = Materials.glow(UIColor(red: 1.0, green: 0.9, blue: 0.5, alpha: 1), opacity: 0.85)
        for _ in 0..<48 {
            let e = ModelEntity(mesh: tracerMesh, materials: [tracerMaterial])
            e.isEnabled = false
            root.addChild(e)
            tracers.append(Item(entity: e))
        }
        let sparkMesh = MeshResource.generateSphere(radius: 0.08)
        let sparkMaterial = Materials.glow(UIColor(red: 1.0, green: 0.75, blue: 0.3, alpha: 1))
        for _ in 0..<32 {
            let e = ModelEntity(mesh: sparkMesh, materials: [sparkMaterial])
            e.isEnabled = false
            root.addChild(e)
            sparks.append(Item(entity: e))
        }
    }

    /// 弾の線(from → to). 0.08 秒で消える.
    func tracer(from a: Vec3, to b: Vec3) {
        let length = (b - a).length
        guard length > 0.5 else { return }
        var item = tracers[nextTracer]
        let mid = (a + b) / 2
        item.entity.look(at: b, from: mid, relativeTo: nil)
        item.entity.scale = Vec3(1, 1, length)
        item.entity.isEnabled = true
        item.life = 0.08
        item.total = 0.08
        tracers[nextTracer] = item
        nextTracer = (nextTracer + 1) % tracers.count
    }

    /// 当たった所の火花.
    func spark(at p: Vec3) {
        var item = sparks[nextSpark]
        item.entity.position = p
        item.entity.scale = SIMD3(repeating: 1)
        item.entity.isEnabled = true
        item.life = 0.18
        item.total = 0.18
        sparks[nextSpark] = item
        nextSpark = (nextSpark + 1) % sparks.count
    }

    func update(dt: Float) {
        for i in tracers.indices where tracers[i].entity.isEnabled {
            tracers[i].life -= dt
            if tracers[i].life <= 0 { tracers[i].entity.isEnabled = false; continue }
            let k = tracers[i].life / tracers[i].total
            let len = tracers[i].entity.scale.z
            tracers[i].entity.scale = Vec3(k, k, len)
        }
        for i in sparks.indices where sparks[i].entity.isEnabled {
            sparks[i].life -= dt
            if sparks[i].life <= 0 { sparks[i].entity.isEnabled = false; continue }
            let k = sparks[i].life / sparks[i].total
            sparks[i].entity.scale = SIMD3(repeating: 0.4 + 1.2 * (1 - k)) * k
        }
    }
}
