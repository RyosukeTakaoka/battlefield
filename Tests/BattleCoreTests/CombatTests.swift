import XCTest
@testable import BattleCore

final class CombatTests: XCTestCase {
    // MARK: 武器の数字

    func testWeaponTable() {
        let h = WeaponSpec.spec(.handgun), a = WeaponSpec.spec(.assaultRifle)
        let s = WeaponSpec.spec(.shotgun), r = WeaponSpec.spec(.sniper)
        XCTAssertEqual([h.damage, a.damage, s.damage, r.damage], [18, 14, 9, 70])
        XCTAssertEqual([h.magazine, a.magazine, s.magazine, r.magazine], [12, 25, 5, 4])
        XCTAssertEqual(s.pellets, 8)
        XCTAssertEqual(a.fireInterval, 1.0 / 9, accuracy: 1e-5)
        XCTAssertFalse(h.automatic)
        XCTAssertTrue(a.automatic)
        for w in WeaponKind.allCases { XCTAssertEqual(WeaponSpec.spec(w).kind, w) }
    }

    func testDamageFalloffBoundaries() {
        let h = WeaponSpec.spec(.handgun)        // 18, 落ち始め 40 m, 半分 80 m, 届く 160 m
        XCTAssertEqual(h.damage(distance: 10, head: false), 18)
        XCTAssertEqual(h.damage(distance: 40, head: false), 18)
        XCTAssertEqual(h.damage(distance: 60, head: false), 14)      // 18 × 0.75 = 13.5 → 14
        XCTAssertEqual(h.damage(distance: 80, head: false), 9)
        XCTAssertEqual(h.damage(distance: 160, head: false), 9)
        XCTAssertEqual(h.damage(distance: 160.5, head: false), 0)
        XCTAssertEqual(h.damage(distance: 10, head: true), 27)       // 頭 × 1.5
        let sg = WeaponSpec.spec(.shotgun)
        XCTAssertEqual(sg.damage(distance: 5, head: false) * 8, 72)
        XCTAssertEqual(sg.damage(distance: 61, head: false), 0)
        let sn = WeaponSpec.spec(.sniper)
        XCTAssertEqual(sn.damage(distance: 299, head: false), 70)    // 落ちない
        XCTAssertEqual(sn.damage(distance: 100, head: true), 140)
        XCTAssertEqual(sn.damage(distance: 301, head: true), 0)
    }

    // MARK: 弾倉・リロード・切りかえ

    func testHoldingFireKeepsShootingAtTheWeaponsRate() {
        // タッチ画面向け: どの武器も 押しっぱなしで撃ち続ける(速さは武器ごと).
        for (kind, perSecond) in [(WeaponKind.handgun, 4), (.assaultRifle, 9)] {
            var l = Loadout(weapons: [kind, nil])
            var shots = 0
            var t = 0.0
            while t < 1.0 {
                if l.pullTrigger(held: true, now: t) { shots += 1 }
                t += 1.0 / 60
            }
            XCTAssertEqual(shots, perSecond, accuracy: 1, "\(kind)")
        }
        var sniper = Loadout(weapons: [.sniper, nil])
        XCTAssertTrue(sniper.pullTrigger(held: true, now: 0))
        XCTAssertFalse(sniper.pullTrigger(held: true, now: 1.0), "sniper: 0.8 shots per second")
        XCTAssertTrue(sniper.pullTrigger(held: true, now: 1.3))
    }

    func testFireRateIsEnforced() {
        var hand = Loadout.starter
        XCTAssertTrue(hand.pullTrigger(held: true, now: 0))
        _ = hand.pullTrigger(held: false, now: 0.05)
        XCTAssertFalse(hand.pullTrigger(held: true, now: 0.1), "too soon (4 shots per second)")
        _ = hand.pullTrigger(held: false, now: 0.2)
        XCTAssertTrue(hand.pullTrigger(held: true, now: 0.26))
    }

    func testEmptyMagazineAutoReloadsAndRefills() {
        var l = Loadout(weapons: [.sniper, nil])                      // 弾倉 4 発, リロード 3.0 秒
        var t = 0.0
        for i in 0..<4 {
            XCTAssertEqual(l.currentAmmo, 4 - i)
            XCTAssertTrue(l.pullTrigger(held: true, now: t))
            _ = l.pullTrigger(held: false, now: t + 0.1)
            t += 1.3
        }
        XCTAssertEqual(l.currentAmmo, 0)
        XCTAssertTrue(l.isReloading, "reload starts by itself when the magazine runs out")
        XCTAssertFalse(l.pullTrigger(held: true, now: t))
        let lastShot = t - 1.3                                          // 4 発目を撃った時刻
        l.update(now: lastShot + 2.0)
        XCTAssertTrue(l.isReloading)
        l.update(now: lastShot + 3.01)
        XCTAssertFalse(l.isReloading)
        XCTAssertEqual(l.currentAmmo, 4)
    }

    func testManualReload() {
        var l = Loadout.starter
        l.startReload(now: 0)
        XCTAssertFalse(l.isReloading, "a full magazine does not need a reload")
        XCTAssertTrue(l.pullTrigger(held: true, now: 1))
        l.startReload(now: 1.5)
        XCTAssertTrue(l.isReloading)
        XCTAssertFalse(l.canFire(now: 2))
        l.update(now: 2.8)                                              // 1.5 + 1.2 = 2.7
        XCTAssertEqual(l.currentAmmo, 12)
    }

    func testSwitchAndPickUp() {
        var l = Loadout.starter
        l.switchSlot(now: 0)
        XCTAssertEqual(l.current, .handgun, "nothing in the other slot")
        XCTAssertNil(l.pickUp(.assaultRifle, now: 1))                   // 空いている枠へ
        XCTAssertEqual(l.current, .handgun)
        l.switchSlot(now: 2)
        XCTAssertEqual(l.current, .assaultRifle)
        XCTAssertFalse(l.canFire(now: 2.1), "short delay after switching")
        XCTAssertTrue(l.canFire(now: 2.4))
        XCTAssertEqual(l.pickUp(.sniper, now: 3), .assaultRifle, "full: swap with the one in hand")
        XCTAssertEqual(l.current, .sniper)
        XCTAssertEqual(l.currentAmmo, 4)
        l.reset(to: [.handgun, nil])
        XCTAssertEqual(l.current, .handgun)
    }

    // MARK: 当たり判定の線

    func testRayShapes() throws {
        let t = try XCTUnwrap(Hitscan.raySphere(origin: Vec3(0, 0, 10), direction: .forward, center: .zero, radius: 1))
        XCTAssertEqual(t, 9, accuracy: 1e-4)
        XCTAssertNil(Hitscan.raySphere(origin: Vec3(2, 0, 10), direction: .forward, center: .zero, radius: 1))
        let c = try XCTUnwrap(Hitscan.rayCapsule(origin: Vec3(0, 1, 10), direction: .forward, a: Vec3(0, 0, 0), b: Vec3(0, 2, 0), radius: 0.5))
        XCTAssertEqual(c, 9.5, accuracy: 1e-4)
        // 上の丸い部分に斜めに当たる.
        XCTAssertNotNil(Hitscan.rayCapsule(origin: Vec3(0, 3, 10), direction: Vec3(0, -0.2, -1).normalized(), a: .zero, b: Vec3(0, 2, 0), radius: 0.5))
        XCTAssertNil(Hitscan.rayCapsule(origin: Vec3(0, 3.1, 10), direction: .forward, a: .zero, b: Vec3(0, 2, 0), radius: 0.5))
    }

    func testTraceHitsPlayersBodyAndHead() {
        let world = makeWorld()
        let target = Hitscan.Target(slot: 1, feet: Vec3(0, 2, -20))
        let body = Hitscan.trace(world: world, origin: Vec3(0, 3.0, 0), direction: .forward, maxRange: 100, targets: [target])
        XCTAssertEqual(body.kind, .player(slot: 1, head: false))
        XCTAssertEqual(body.distance, 20 - Hitscan.bodyRadius, accuracy: 0.05)      // 体の真ん中の高さ(足もと + 1.0)
        // 頭の高さ(足もと + 1.62)をねらう.
        let head = Hitscan.trace(world: world, origin: Vec3(0, 3.62, 0), direction: .forward, maxRange: 100, targets: [target])
        XCTAssertEqual(head.kind, .player(slot: 1, head: true))
        // 頭の上を通る / 横を通る.
        XCTAssertEqual(Hitscan.trace(world: world, origin: Vec3(0, 4.2, 0), direction: .forward, maxRange: 100, targets: [target]).kind, .none)
        XCTAssertEqual(Hitscan.trace(world: world, origin: Vec3(1.0, 3.35, 0), direction: .forward, maxRange: 100, targets: [target]).kind, .none)
    }

    func testWallsStopBulletsAndShortRangeDoesNotReach() {
        let world = makeWorld(obstacles: [.box(center: Vec3(0, 4, -10), half: Vec3(5, 2, 0.5))])
        let target = Hitscan.Target(slot: 1, feet: Vec3(0, 2, -20))
        let shot = Hitscan.trace(world: world, origin: Vec3(0, 3.35, 0), direction: .forward, maxRange: 100, targets: [target])
        XCTAssertEqual(shot.kind, .obstacle, "no shooting through walls")
        XCTAssertEqual(shot.distance, 9.5, accuracy: 0.05)
        let open = makeWorld()
        let far = Hitscan.trace(world: open, origin: Vec3(0, 3.35, 0), direction: .forward, maxRange: 10, targets: [target])
        XCTAssertEqual(far.kind, .none)
    }

    func testNearestPlayerWins() {
        let world = makeWorld()
        let targets = [Hitscan.Target(slot: 1, feet: Vec3(0, 2, -30)), Hitscan.Target(slot: 2, feet: Vec3(0, 2, -15))]
        let shot = Hitscan.trace(world: world, origin: Vec3(0, 3.35, 0), direction: .forward, maxRange: 100, targets: targets)
        XCTAssertEqual(shot.kind, .player(slot: 2, head: false))
    }

    func testFireFromChestTowardsTheAimPoint() {
        let target = Hitscan.Target(slot: 1, feet: Vec3(0, 2, -20))
        // 胸の高さ(足もと + 1.35)にある板: カメラは板の上から まっすぐ前を見ている. 弾は胸から出るので 板に当たる.
        // (かべの向こうから 体を出さずに撃てない)
        let high = makeWorld(obstacles: [.box(center: Vec3(0, 3.5, -4), half: Vec3(2, 0.5, 0.5))])
        var rng = SeededRandom(seed: 1)
        let aim = Hitscan.aimPoint(world: high, cameraPosition: Vec3(0, 6, 3), cameraDirection: .forward, targets: [target])
        let blocked = Hitscan.fire(world: high, shooterFeet: Vec3(0, 2, 0), aimPoint: aim, targets: [target], spec: .spec(.sniper),
                                   aiming: true, rng: &rng)
        XCTAssertEqual(blocked[0].origin, Vec3(0, 3.35, 0))
        XCTAssertEqual(blocked[0].kind, .obstacle)
        // 胸より低い板(上が 2.75)なら, 弾はこえて 体に届く.
        let low = makeWorld(obstacles: [.box(center: Vec3(0, 2.5, -4), half: Vec3(2, 0.25, 0.5))])
        let shots = Hitscan.fire(world: low, shooterFeet: Vec3(0, 2, 0), aimPoint: aim, targets: [target], spec: .spec(.sniper),
                                 aiming: true, rng: &rng)
        XCTAssertEqual(shots.count, 1)
        // 板をこえて 相手に届く(弾は少し上向きに出るので, 頭に当たることもある).
        guard case .player(let slot, _) = shots[0].kind else { return XCTFail("expected a player hit, got \(shots[0].kind)") }
        XCTAssertEqual(slot, 1)
    }

    func testShotgunFiresEightPelletsWithSpread() {
        let world = makeWorld()
        var rng = SeededRandom(seed: 5)
        let target = Hitscan.Target(slot: 1, feet: Vec3(0, 2, -6))
        let aim = Vec3(0, 3.35, -6)
        let shots = Hitscan.fire(world: world, shooterFeet: Vec3(0, 2, 0), aimPoint: aim, targets: [target], spec: .spec(.shotgun),
                                 aiming: false, rng: &rng)
        XCTAssertEqual(shots.count, 8)
        let ends = Set(shots.map { "\($0.end.x)" })
        XCTAssertGreaterThan(ends.count, 4, "pellets spread out")
        let hits = shots.filter { if case .player = $0.kind { return true } else { return false } }.count
        XCTAssertGreaterThan(hits, 3)                                   // 6 m ならほとんど当たる
        XCTAssertLessThanOrEqual(hits, 8)
    }

    func testSpreadStaysInsideTheCone() {
        var rng = SeededRandom(seed: 9)
        let base = Vec3(0.3, 0.1, -1).normalized()
        for _ in 0..<500 {
            let d = Hitscan.perturbed(base, spreadDegrees: 2.2, rng: &rng)
            XCTAssertEqual(d.length, 1, accuracy: 1e-4)
            XCTAssertLessThanOrEqual(acos(min(1, d.dot(base))) * 180 / .pi, 2.2 + 0.01)
        }
        XCTAssertEqual(Hitscan.perturbed(base, spreadDegrees: 0, rng: &rng), base)
    }

    /// 撃つボタンを指で押しっぱなしにすると, 武器の表の速さで撃ち続ける(60 Hz でも 120 Hz の画面でも).
    func testHoldingTheFireButtonWithAFinger() throws {
        for fps in [60.0, 120.0] {
            // ショットガンは 1.1 発/秒 → 0 秒と 0.91 秒の 2 発
            for (kind, perSecond) in [(WeaponKind.assaultRifle, 9), (.handgun, 4), (.shotgun, 2), (.sniper, 1)] {
                var touch = TouchLayout(width: 844, height: 390)
                let fire = try XCTUnwrap(touch.buttons.first { $0.button == .fire })
                var loadout = Loadout(weapons: [kind, nil])
                touch.touchBegan(id: 1, x: fire.center.x, y: fire.center.y)
                var shots = 0
                var t = 0.0
                while t < 1.0 - 1e-9 {
                    // 親指が少しゆれても 押しっぱなしのまま.
                    touch.touchMoved(id: 1, x: fire.center.x + Float(sin(t * 30)) * 6, y: fire.center.y)
                    let pressed = touch.takePressed()
                    loadout.update(now: t)
                    if loadout.pullTrigger(held: touch.isHeld(.fire) || pressed.contains(.fire), now: t) { shots += 1 }
                    t += 1 / fps
                }
                XCTAssertEqual(shots, perSecond, "\(kind) \(Int(fps)) Hz")
            }
        }
    }

    /// アサルトライフルを押しっぱなし: 25 発うちきると 自動でリロードし, 押したままなら また撃ちはじめる.
    func testHoldingFireThroughAReload() {
        var l = Loadout(weapons: [.assaultRifle, nil])
        var times: [Double] = []
        var t = 0.0
        while t < 6 {
            l.update(now: t)
            if l.pullTrigger(held: true, now: t) { times.append(t) }
            t += 1.0 / 60
        }
        XCTAssertEqual(times.prefix(25).count, 25)
        // 25 発目のあと 2.0 秒のリロード. そのあと 押したまま撃ちはじめる.
        XCTAssertEqual(times[25] - times[24], 2.0, accuracy: 0.05)
        XCTAssertEqual(times.count, 37)                  // 2.67 秒で 25 発 → 2 秒リロード → のこり 1.33 秒で 12 発
        // 連射の間かくは 平均して 1/9 秒.
        let first25 = times[24] - times[0]
        XCTAssertEqual(first25 / 24, 1.0 / 9, accuracy: 0.005)
    }
}

final class AimAssistTests: XCTestCase {
    let cam = Vec3(0.6, 4.0, 3.2)          // 足もと (0, 2, 0) の肩ごしカメラ
    let feet = Vec3(0, 2, 0)

    /// カメラから見て, 水平に yawDeg 度・距離 d の所に立つ敵.
    func target(_ slot: Int, yawDeg: Float, distance d: Float) -> Hitscan.Target {
        let a = yawDeg * .pi / 180
        return Hitscan.Target(slot: slot, feet: Vec3(cam.x + sin(a) * d, 2, cam.z - cos(a) * d))
    }

    /// カメラから 敵の胸を まっすぐ見る向きを, 横に offsetDeg 度ずらしたもの.
    func direction(toward t: Hitscan.Target, offsetDeg: Float) -> Vec3 {
        let to = (t.feet + Vec3(0, 1.0, 0) - cam).normalized()
        return to.rotated(around: .up, by: -offsetDeg * .pi / 180).normalized()
    }

    func testNearMissIsPulledToTheTarget() {
        let world = makeWorld()
        let t = target(1, yawDeg: 0, distance: 12)
        let dir = direction(toward: t, offsetDeg: 2)          // 2 度ずれた(このままでは 体の横を通る)
        if case .player = Hitscan.trace(world: world, origin: cam, direction: dir, maxRange: 100, targets: [t]).kind {
            XCTFail("without help this aim should miss the player")
        }
        let r = AimAssist.aimPoint(world: world, cameraPosition: cam, cameraDirection: dir, shooterFeet: feet, targets: [t], maxRange: 100)
        XCTAssertEqual(r.target, 1)
        // 胸から その点へ撃つと 当たる.
        var rng = SeededRandom(seed: 1)
        var spec = WeaponSpec.spec(.assaultRifle)
        spec.spreadHip = 0
        let shots = Hitscan.fire(world: world, shooterFeet: feet, aimPoint: r.point, targets: [t], spec: spec, aiming: false, rng: &rng)
        guard case .player(1, _) = shots[0].kind else { return XCTFail("\(shots[0].kind)") }
    }

    func testFarOffOrFarAwayIsNotPulled() {
        let world = makeWorld()
        let t = target(1, yawDeg: 0, distance: 12)
        XCTAssertNil(AimAssist.aimPoint(world: world, cameraPosition: cam, cameraDirection: direction(toward: t, offsetDeg: 8),
                                        shooterFeet: feet, targets: [t], maxRange: 100).target, "8 degrees off: your own aim")
        // 遠いと 助けの角度は せまい(横に 0.9 m まで): 30 m 先で 3 度(= 1.6 m)ずれは 助けない.
        let far = target(2, yawDeg: 0, distance: 30)
        XCTAssertNil(AimAssist.aimPoint(world: world, cameraPosition: cam, cameraDirection: direction(toward: far, offsetDeg: 3),
                                        shooterFeet: feet, targets: [far], maxRange: 100).target)
        XCTAssertEqual(AimAssist.aimPoint(world: world, cameraPosition: cam, cameraDirection: direction(toward: far, offsetDeg: 1),
                                          shooterFeet: feet, targets: [far], maxRange: 100).target, 2)
        // 武器の届く距離の外.
        XCTAssertNil(AimAssist.aimPoint(world: world, cameraPosition: cam, cameraDirection: direction(toward: far, offsetDeg: 0.5),
                                        shooterFeet: feet, targets: [far], maxRange: 20).target)
    }

    func testNoHelpThroughWalls() {
        // 敵の前に 高いかべ.
        let t = target(1, yawDeg: 0, distance: 12)
        let wallZ = (cam.z + t.feet.z) / 2
        let world = makeWorld(obstacles: [.box(center: Vec3(0, 4, wallZ), half: Vec3(4, 3, 0.3))])
        let r = AimAssist.aimPoint(world: world, cameraPosition: cam, cameraDirection: direction(toward: t, offsetDeg: 1.5),
                                   shooterFeet: feet, targets: [t], maxRange: 100)
        XCTAssertNil(r.target)
    }

    func testPicksTheTargetClosestToTheCrosshair() {
        let world = makeWorld()
        let a = target(1, yawDeg: 0, distance: 15), b = target(2, yawDeg: 3, distance: 10)
        let r = AimAssist.aimPoint(world: world, cameraPosition: cam, cameraDirection: direction(toward: a, offsetDeg: 0.5),
                                   shooterFeet: feet, targets: [a, b], maxRange: 100)
        XCTAssertEqual(r.target, 1)
    }

    func testLookSlowsDownNearATarget() {
        let t = target(1, yawDeg: 0, distance: 12)
        XCTAssertEqual(AimAssist.lookScale(cameraPosition: cam, cameraDirection: direction(toward: t, offsetDeg: 1), targets: [t], maxRange: 100),
                       GameRules.aimFriction)
        XCTAssertEqual(AimAssist.lookScale(cameraPosition: cam, cameraDirection: direction(toward: t, offsetDeg: 20), targets: [t], maxRange: 100), 1)
    }

    func testAssistOffMeansPlainAim() {
        let world = makeWorld()
        let t = target(1, yawDeg: 0, distance: 12)
        let r = AimAssist.aimPoint(world: world, cameraPosition: cam, cameraDirection: direction(toward: t, offsetDeg: 2),
                                   shooterFeet: feet, targets: [t], maxRange: 100, degrees: 0)
        XCTAssertNil(r.target)
    }
}

final class AimButtonTests: XCTestCase {
    func testAimIsOnTheOtherHandAndIsATap() throws {
        var t = TouchLayout(width: 844, height: 390)
        t.insets = .init(left: 47, right: 47, top: 0, bottom: 21)
        let aim = try XCTUnwrap(t.buttons.first { $0.button == .aim })
        let fire = try XCTUnwrap(t.buttons.first { $0.button == .fire })
        XCTAssertLessThan(aim.center.x, 422, "right-handed: aim on the left")
        XCTAssertGreaterThan(fire.center.x, 422)
        // 移動の指(左下)と 構える を同時に使える.
        t.touchBegan(id: 1, x: 200, y: 330)
        t.touchMoved(id: 1, x: 200, y: 280)
        t.touchBegan(id: 2, x: aim.center.x, y: aim.center.y)
        XCTAssertGreaterThan(t.move.y, 0.5)
        t.touchEnded(id: 2)
        XCTAssertEqual(t.takePressed(), [.aim], "a tap is recorded so the game can toggle aiming")
        t.leftHanded = true
        XCTAssertGreaterThan(t.buttons.first { $0.button == .aim }!.center.x, 422, "left-handed: aim on the right")
    }
}
