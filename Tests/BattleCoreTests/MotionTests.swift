import XCTest
@testable import BattleCore

final class MotionTests: XCTestCase {
    func forwardInput(yaw: Float = 0) -> PlayerInput {
        var i = PlayerInput()
        i.moveY = 1
        i.yaw = yaw
        return i
    }

    func testRunning() {
        let world = makeWorld()
        var p = standingPlayer(0, 15)
        simulate(&p, input: forwardInput(), world: world, seconds: 1)
        XCTAssertEqual(p.position.z, 9, accuracy: 0.1)           // -Z へ 6.0 m
        XCTAssertEqual(p.position.y, 2, accuracy: 1e-3)
        XCTAssertTrue(p.isGrounded)
    }

    func testSameDistanceAt30And60Fps() {
        let world = makeWorld()
        var a = standingPlayer(0, 0), b = standingPlayer(0, 0)
        simulate(&a, input: forwardInput(yaw: 0.7), world: world, seconds: 1, dt: 1.0 / 60)
        simulate(&b, input: forwardInput(yaw: 0.7), world: world, seconds: 1, dt: 1.0 / 30)
        XCTAssertEqual((a.position - b.position).length, 0, accuracy: 0.05)
    }

    func testDiagonalIsNotFaster() {
        let world = makeWorld()
        var p = standingPlayer(0, 0)
        var i = PlayerInput()
        i.moveX = 1; i.moveY = 1
        simulate(&p, input: i, world: world, seconds: 1)
        XCTAssertEqual((p.position - Vec3(0, 2, 0)).length, 6, accuracy: 0.1)
    }

    func testAimingIsSlower() {
        let world = makeWorld()
        var p = standingPlayer(0, 15)
        var i = forwardInput()
        i.aiming = true
        simulate(&p, input: i, world: world, seconds: 1)
        XCTAssertEqual(15 - p.position.z, 3.5, accuracy: 0.1)
    }

    func testYawTurnsTheRunDirection() {
        let world = makeWorld()
        var p = standingPlayer(0, 0)
        simulate(&p, input: forwardInput(yaw: .pi / 2), world: world, seconds: 1)     // 右(+X)を向く
        XCTAssertEqual(p.position.x, 6, accuracy: 0.1)
        XCTAssertEqual(p.position.z, 0, accuracy: 0.1)
    }

    func testJumpHeightAndNoDoubleJump() {
        let world = makeWorld()
        var p = standingPlayer()
        var jump = PlayerInput()
        jump.jump = true
        CharacterMotor.step(&p, input: jump, world: world, dt: GameRules.tick)
        var peak = p.position.y
        // 空中でもう一度押しても飛べない.
        for _ in 0..<120 {
            CharacterMotor.step(&p, input: jump, world: world, dt: GameRules.tick)
            peak = max(peak, p.position.y)
            if p.isGrounded { break }
        }
        XCTAssertGreaterThan(peak - 2, 1.1)
        XCTAssertLessThan(peak - 2, 1.3)
        XCTAssertTrue(p.isGrounded)
        XCTAssertEqual(p.position.y, 2, accuracy: 1e-3)
    }

    func testAirControlIsWeak() {
        let world = makeWorld()
        var p = standingPlayer()
        var jump = PlayerInput()
        jump.jump = true
        CharacterMotor.step(&p, input: jump, world: world, dt: GameRules.tick)
        XCTAssertFalse(p.isGrounded)
        // 空中で右へ入れても, 1 コマでは ほとんど変わらない(地上なら 6 m/s にすぐ届く).
        var side = PlayerInput()
        side.moveX = 1
        CharacterMotor.step(&p, input: side, world: world, dt: GameRules.tick)
        XCTAssertGreaterThan(p.velocity.x, 0)
        XCTAssertLessThan(p.velocity.x, GameRules.runSpeed * 0.1)
        // 0.5 秒かけても 目標の速さには届かない(30% くらいの効き).
        for _ in 0..<20 { CharacterMotor.step(&p, input: side, world: world, dt: GameRules.tick) }
        XCTAssertLessThan(p.velocity.x, GameRules.runSpeed * 0.7)
    }

    func testSlidesAlongABoxAndNeverEntersIt() {
        let world = makeWorld(obstacles: [.box(center: Vec3(0, 4, -10), half: Vec3(25, 2, 1))])   // 高さ 2〜6 の長いかべ
        var p = standingPlayer(0, 0)
        var i = PlayerInput()
        i.moveX = 0.7; i.moveY = 1               // かべへななめに
        simulate(&p, input: i, world: world, seconds: 4)
        XCTAssertGreaterThan(p.position.z, -10 + 1 + GameRules.playerRadius - 1e-3, "stopped by the wall")
        XCTAssertGreaterThan(p.position.x, 4, "kept sliding sideways along the wall")
    }

    func testFastMoveCannotTunnelThroughThinWall() {
        let world = makeWorld(obstacles: [.box(center: Vec3(0, 4, -10), half: Vec3(8, 2, 0.1))])
        var p = standingPlayer(0, 0)
        for _ in 0..<60 {
            p.position = world.resolveMove(from: p.position, to: p.position + Vec3(0, 0, -20.0 / 60))
        }
        XCTAssertGreaterThan(p.position.z, -10)
    }

    func testRotatedBoxBlocks() {
        let world = makeWorld(obstacles: [.box(center: Vec3(0, 4, -10), half: Vec3(6, 2, 0.5), yaw: 0.6)])
        var p = standingPlayer(0, 0)
        // 3 秒のあいだ, 一度も かべの中に入らない. まっすぐ進めなかった(かべにそって曲がった)ので x がずれる.
        for _ in 0..<180 {
            CharacterMotor.step(&p, input: forwardInput(), world: world, dt: GameRules.tick)
            XCTAssertFalse(world.solids[0].containsXZ(p.position.x, p.position.z))
        }
        XCTAssertGreaterThan(p.position.x, 0.5)
    }

    func testCylinderBlocks() {
        let world = makeWorld(obstacles: [.cylinder(base: Vec3(0, 2, -8), radius: 1, height: 6)])
        var p = standingPlayer(0, 0)
        simulate(&p, input: forwardInput(), world: world, seconds: 3)
        XCTAssertGreaterThanOrEqual((Vec3(p.position.x, 0, p.position.z) - Vec3(0, 0, -8)).length, 1 + GameRules.playerRadius - 1e-3)
    }

    func testStepUpSmallBoxButNotBigBox() {
        // 高さ 0.5 m(乗れる)と 1.0 m(乗れない).
        let low = makeWorld(obstacles: [.box(center: Vec3(0, 2.25, -6), half: Vec3(2, 0.25, 2))])
        var p = standingPlayer(0, 0)
        simulate(&p, input: forwardInput(), world: low, seconds: 1.2)
        XCTAssertEqual(p.position.y, 2.5, accuracy: 1e-3, "climbed onto the 0.5 m box")
        XCTAssertLessThan(p.position.z, -5)

        let high = makeWorld(obstacles: [.box(center: Vec3(0, 2.5, -6), half: Vec3(2, 0.5, 2))])
        var q = standingPlayer(0, 0)
        simulate(&q, input: forwardInput(), world: high, seconds: 2)
        XCTAssertEqual(q.position.y, 2, accuracy: 1e-3)
        XCTAssertGreaterThan(q.position.z, -4 + GameRules.playerRadius - 1e-3)
    }

    func testJumpOntoAOneMeterBox() {
        let world = makeWorld(obstacles: [.box(center: Vec3(0, 2.5, -3), half: Vec3(3, 0.5, 2))])
        var p = standingPlayer(0, 0)
        simulate(&p, input: forwardInput(), world: world, seconds: 0.5)     // かべにぶつかって止まる
        XCTAssertEqual(p.position.y, 2, accuracy: 1e-3)
        var i = forwardInput()
        i.jump = true
        CharacterMotor.step(&p, input: i, world: world, dt: GameRules.tick)
        i.jump = false
        simulate(&p, input: i, world: world, seconds: 0.5)      // 箱の上を 3 m ほど進んだところ(箱の長さは 4 m)
        XCTAssertEqual(p.position.y, 3, accuracy: 1e-3, "jumped up on the 1 m box")
        XCTAssertTrue(p.isGrounded)
    }

    func testStandingOnABoxAndWalkingOff() {
        let world = makeWorld(obstacles: [.box(center: Vec3(0, 2.25, 0), half: Vec3(1, 0.25, 1))])
        var p = standingPlayer(0, 0)
        p.position.y = 2.5
        simulate(&p, input: forwardInput(), world: world, seconds: 1)
        XCTAssertEqual(p.position.y, 2, accuracy: 1e-3, "walked off the edge and fell to the ground")
        XCTAssertTrue(p.isGrounded)
    }

    func testSteepSlopeBlocksButFlatDoesNot() {
        let world = makeWorld()
        var p = standingPlayer(0, 15)
        var i = PlayerInput()
        i.moveY = -1                       // +Z へ(急な坂の方)
        i.yaw = 0
        simulate(&p, input: i, world: world, seconds: 3)
        XCTAssertLessThan(p.position.z, 22, "cannot climb the steep slope")
        XCTAssertLessThan(p.position.y, 6)
    }

    func testWaterBlocks() {
        let world = makeWorld()
        var p = standingPlayer(20, 0)
        simulate(&p, input: forwardInput(yaw: .pi / 2), world: world, seconds: 5)    // +X へ(海の方)
        XCTAssertLessThan(p.position.x, 31)
        XCTAssertGreaterThan(p.position.y, GameRules.minGroundY)
    }

    func testOutsideTheMapIsBlocked() {
        let world = makeWorld()
        var p = standingPlayer(-35, 0)
        simulate(&p, input: forwardInput(yaw: -.pi / 2), world: world, seconds: 3)    // -X へ(地図のはて)
        XCTAssertGreaterThan(p.position.x, -41)
    }

    func testWalkingDownASlopeStaysOnTheGround() {
        // ゆるい下り坂(傾き 0.3).
        let hf = makeHeightfield(cols: 81, rows: 81, cell: 1, originX: -40, originZ: 40) { _, z in 10 + z * 0.3 }
        let world = ArenaWorld(map: MapData(id: "slope", name: "slope"), terrain: hf)
        var p = PlayerState(position: Vec3(0, 10 + 20 * 0.3, 20))
        p.isGrounded = true
        simulate(&p, input: forwardInput(), world: world, seconds: 2)
        XCTAssertTrue(p.isGrounded)
        XCTAssertEqual(p.position.y, world.terrainHeight(x: p.position.x, z: p.position.z), accuracy: 1e-3)
    }
}
