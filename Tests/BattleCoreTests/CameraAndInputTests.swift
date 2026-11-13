import XCTest
@testable import BattleCore

final class ThirdPersonCameraTests: XCTestCase {
    func settle(_ cam: inout ThirdPersonCamera, _ p: PlayerState, aiming: Bool = false, weapon: WeaponKind? = nil, world: ArenaWorld) -> ThirdPersonCamera.Pose {
        var pose = cam.update(player: p, aiming: aiming, weapon: weapon, world: world, dt: 1.0 / 60)
        for _ in 0..<120 { pose = cam.update(player: p, aiming: aiming, weapon: weapon, world: world, dt: 1.0 / 60) }
        return pose
    }

    func testCameraSitsBehindAndAboveTheShoulder() {
        let world = makeWorld()
        var cam = ThirdPersonCamera()
        let p = PlayerState(position: Vec3(0, 2, 0), yaw: 0)             // -Z を向く
        let pose = settle(&cam, p, world: world)
        XCTAssertEqual(pose.position.z, 3.2, accuracy: 0.05)             // うしろ(+Z)へ 3.2 m
        XCTAssertEqual(pose.position.x, 0.6, accuracy: 0.05)             // 右へ 0.6 m
        XCTAssertEqual(pose.position.y, 2 + 1.6 + 0.4, accuracy: 0.05)
        XCTAssertEqual(pose.forward, Vec3(0, 0, -1))
        XCTAssertEqual(pose.verticalFOV, 60 * .pi / 180, accuracy: 1e-3)
    }

    func testCameraFollowsYawAndPitch() {
        let world = makeWorld()
        var cam = ThirdPersonCamera()
        var p = PlayerState(position: Vec3(0, 2, 0), yaw: .pi / 2)       // +X を向く
        let pose = settle(&cam, p, world: world)
        XCTAssertEqual(pose.position.x, -3.2, accuracy: 0.05)
        XCTAssertEqual(pose.forward.x, 1, accuracy: 1e-4)
        p.pitch = 0.5                                                    // 上を向くと, カメラは下がる
        let up = settle(&cam, p, world: world)
        XCTAssertLessThan(up.position.y, pose.position.y)
        XCTAssertEqual(up.forward.y, sin(0.5), accuracy: 1e-4)
        XCTAssertEqual(up.forward.length, 1, accuracy: 1e-4)
    }

    func testAimingMovesInAndNarrowsTheView() {
        let world = makeWorld()
        var cam = ThirdPersonCamera()
        let p = PlayerState(position: Vec3(0, 2, 0), yaw: 0)
        let normal = settle(&cam, p, world: world)
        let aim = settle(&cam, p, aiming: true, weapon: .assaultRifle, world: world)
        XCTAssertLessThan(aim.position.z, normal.position.z)
        XCTAssertEqual(aim.position.z, 1.6, accuracy: 0.05)
        XCTAssertEqual(aim.verticalFOV, 35 * .pi / 180, accuracy: 1e-3)
        let sniper = settle(&cam, p, aiming: true, weapon: .sniper, world: world)
        XCTAssertEqual(sniper.verticalFOV, 15 * .pi / 180, accuracy: 1e-3)
        let back = settle(&cam, p, world: world)
        XCTAssertEqual(back.verticalFOV, 60 * .pi / 180, accuracy: 1e-3)
    }

    func testCameraNeverGoesInsideAWall() {
        // うしろに かべ(z = 1.5 の位置, 高い板).
        let world = makeWorld(obstacles: [.box(center: Vec3(0, 4, 1.8), half: Vec3(10, 3, 0.2))])
        var cam = ThirdPersonCamera()
        let p = PlayerState(position: Vec3(0, 2, 0), yaw: 0)
        let pose = settle(&cam, p, world: world)
        XCTAssertLessThan(pose.position.z, 1.6, "pulled in front of the wall (wall face at z = 1.6)")
        XCTAssertGreaterThan(pose.position.z, -1)
        XCTAssertFalse(world.solids[0].containsXZ(pose.position.x, pose.position.z))
    }

    func testCameraStaysAboveTheGround() {
        let world = makeWorld()
        var cam = ThirdPersonCamera()
        var p = PlayerState(position: Vec3(0, 2, 0), yaw: 0)
        p.pitch = -1.3                                                   // 真下近くを向く: カメラは高く上がる
        let pose = settle(&cam, p, world: world)
        XCTAssertGreaterThan(pose.position.y, 2 + 0.3)
        p.pitch = 1.3                                                    // 真上近く: カメラは地面にもぐらない
        let low = settle(&cam, p, world: world)
        XCTAssertGreaterThanOrEqual(low.position.y, 2 + 0.3 - 1e-3)
    }

    func testCameraEasesBackOutAfterAWall() {
        let world = makeWorld(obstacles: [.box(center: Vec3(0, 4, 1.8), half: Vec3(2, 3, 0.2))])
        var cam = ThirdPersonCamera()
        let behindWall = settle(&cam, PlayerState(position: Vec3(0, 2, 0), yaw: 0), world: world)
        // 横へ動いて かべがなくなる: 1 コマで一気には戻らず, 少しずつ.
        let free = PlayerState(position: Vec3(10, 2, 0), yaw: 0)
        let first = cam.update(player: free, aiming: false, weapon: nil, world: world, dt: 1.0 / 60)
        XCTAssertLessThan(first.position.z, 3.2 - 0.5)
        _ = behindWall
        let done = settle(&cam, free, world: world)
        XCTAssertEqual(done.position.z, 3.2, accuracy: 0.05)
    }
}

final class TouchLayoutTests: XCTestCase {
    func layout() -> TouchLayout { TouchLayout(width: 844, height: 390) }

    func testTwoFingersAtOnceMoveAndLook() {
        var t = layout()
        t.touchBegan(id: 1, x: 100, y: 200)               // 左半分: 移動
        t.touchBegan(id: 2, x: 500, y: 100)               // 右半分: 視点
        t.touchMoved(id: 1, x: 100, y: 140)               // 上へ 60 pt = 前へいっぱい
        XCTAssertEqual(t.move.x, 0, accuracy: 1e-5)
        XCTAssertEqual(t.move.y, 1, accuracy: 1e-5)
        t.touchMoved(id: 2, x: 600, y: 80)                // 右へ 100 pt, 上へ 20 pt
        let look = t.takeLook()
        XCTAssertEqual(look.yaw, 100 * 0.006, accuracy: 1e-5)
        XCTAssertEqual(look.pitch, 20 * 0.006, accuracy: 1e-5)
        XCTAssertEqual(t.activeTouchCount, 2)
        // 移動の指を止めても視点の指は続く. はなすとスティックが 0 に戻る.
        t.touchEnded(id: 1)
        XCTAssertEqual(t.move, TouchLayout.Point(x: 0, y: 0))
        t.touchMoved(id: 2, x: 610, y: 80)
        XCTAssertEqual(t.takeLook().yaw, 10 * 0.006, accuracy: 1e-5)
    }

    func testStickIsClampedToUnitLength() {
        var t = layout()
        t.touchBegan(id: 1, x: 100, y: 200)
        t.touchMoved(id: 1, x: 200, y: 100)               // 右上へ 100 pt ずつ
        XCTAssertEqual(t.move.x * t.move.x + t.move.y * t.move.y, 1, accuracy: 1e-4)
        XCTAssertGreaterThan(t.move.x, 0)
        XCTAssertGreaterThan(t.move.y, 0)
        t.touchMoved(id: 1, x: 130, y: 200)               // 右へ 30 pt = 半分
        XCTAssertEqual(t.move.x, 0.5, accuracy: 1e-4)
    }

    func testLookAccumulatesBetweenReads() {
        var t = layout()
        t.touchBegan(id: 2, x: 500, y: 100)
        for i in 1...5 { t.touchMoved(id: 2, x: 500 + Float(i) * 10, y: 100) }
        XCTAssertEqual(t.takeLook().yaw, 50 * 0.006, accuracy: 1e-5)
        let again = t.takeLook()
        XCTAssertEqual(again.yaw, 0)
        XCTAssertEqual(again.pitch, 0)
    }

    func testButtonsAndFireWhileLooking() throws {
        var t = layout()
        let fire = try XCTUnwrap(t.buttons.first { $0.button == .fire })
        let jump = try XCTUnwrap(t.buttons.first { $0.button == .jump })
        XCTAssertGreaterThan(fire.center.x, 422, "right-handed: fire button on the right")
        t.touchBegan(id: 1, x: fire.center.x, y: fire.center.y)
        XCTAssertTrue(t.isHeld(.fire))
        XCTAssertEqual(t.activeTouchCount, 1)
        // 撃ちながら 指を動かすと 視点も動く.
        t.touchMoved(id: 1, x: fire.center.x + 30, y: fire.center.y)
        XCTAssertEqual(t.takeLook().yaw, 30 * 0.006, accuracy: 1e-5)
        XCTAssertTrue(t.isHeld(.fire))
        // 別の指でジャンプ: 押した瞬間だけ.
        t.touchBegan(id: 2, x: jump.center.x, y: jump.center.y)
        XCTAssertEqual(t.takePressed(), [.jump])
        XCTAssertEqual(t.takePressed(), [])
        t.touchEnded(id: 1)
        XCTAssertFalse(t.isHeld(.fire))
        // 構えるは 押しているあいだ.
        let aim = try XCTUnwrap(t.buttons.first { $0.button == .aim })
        t.touchBegan(id: 3, x: aim.center.x, y: aim.center.y)
        XCTAssertTrue(t.isHeld(.aim))
        XCTAssertEqual(t.takePressed(), [])
        t.touchEnded(id: 3)
        XCTAssertFalse(t.isHeld(.aim))
    }

    func testLeftHandedSwapsTheSides() throws {
        var t = layout()
        t.leftHanded = true
        let fire = try XCTUnwrap(t.buttons.first { $0.button == .fire })
        XCTAssertLessThan(fire.center.x, 422)
        t.touchBegan(id: 1, x: 700, y: 200)               // 右半分が 移動
        t.touchMoved(id: 1, x: 700, y: 140)
        XCTAssertEqual(t.move.y, 1, accuracy: 1e-5)
        t.touchBegan(id: 2, x: 400, y: 100)               // 左半分が 視点
        t.touchMoved(id: 2, x: 420, y: 100)
        XCTAssertEqual(t.takeLook().yaw, 20 * 0.006, accuracy: 1e-5)
    }

    func testInvertYAndSensitivity() {
        var t = layout()
        t.invertY = true
        t.lookSensitivity = 0.01
        t.touchBegan(id: 2, x: 500, y: 100)
        t.touchMoved(id: 2, x: 500, y: 80)                // 上へ 20 pt
        XCTAssertEqual(t.takeLook().pitch, -20 * 0.01, accuracy: 1e-5)
    }

    func testOnlyOneMoveFingerAndCancel() {
        var t = layout()
        t.touchBegan(id: 1, x: 100, y: 200)
        t.touchBegan(id: 2, x: 120, y: 220)               // 左半分の 2 本目: 視点の指として扱う(移動は 1 本だけ)
        t.touchMoved(id: 2, x: 140, y: 220)
        XCTAssertEqual(t.takeLook().yaw, 20 * 0.006, accuracy: 1e-5)
        t.touchMoved(id: 1, x: 100, y: 150)
        XCTAssertGreaterThan(t.move.y, 0.5)
        t.cancelAll()
        XCTAssertEqual(t.move, TouchLayout.Point(x: 0, y: 0))
        XCTAssertEqual(t.activeTouchCount, 0)
        XCTAssertFalse(t.isHeld(.fire))
        t.touchMoved(id: 1, x: 100, y: 100)               // はなした指の動きは 無視する
        XCTAssertEqual(t.move, TouchLayout.Point(x: 0, y: 0))
    }

    func testButtonsDoNotOverlapAndFitTheScreen() {
        for (w, h) in [(Float(844), Float(390)), (932, 430), (1194, 834), (667, 375)] {
            let t = TouchLayout(width: w, height: h)
            let bs = t.buttons
            for b in bs {
                XCTAssertGreaterThanOrEqual(b.center.x - b.radius, 0, "\(b.button) \(w)x\(h)")
                XCTAssertLessThanOrEqual(b.center.x + b.radius, w)
                XCTAssertGreaterThanOrEqual(b.center.y - b.radius, 0)
                XCTAssertLessThanOrEqual(b.center.y + b.radius, h)
            }
            for i in 0..<bs.count {
                for j in (i + 1)..<bs.count {
                    let dx = bs[i].center.x - bs[j].center.x, dy = bs[i].center.y - bs[j].center.y
                    XCTAssertGreaterThan((dx * dx + dy * dy).squareRoot(), bs[i].radius + bs[j].radius - 1, "\(bs[i].button)/\(bs[j].button) \(w)x\(h)")
                }
            }
        }
    }
}
