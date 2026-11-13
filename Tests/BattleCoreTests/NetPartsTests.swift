import XCTest
@testable import BattleCore

final class ClockSyncTests: XCTestCase {
    /// 自分の時計がホストより `trueOffset` だけ進んでいる/遅れている(ホスト = 自分 + trueOffset)として, 遅れがばらつく通信でずれを見つもる.
    func estimate(trueOffset: Double, latency: ClosedRange<Double>, samples: Int, seed: UInt64) -> Double {
        var rng = SeededRandom(seed: seed)
        var clock = ClockSync()
        var t = 100.0
        for _ in 0..<samples {
            let up = Double(rng.float(in: Float(latency.lowerBound)...Float(latency.upperBound)))
            let down = Double(rng.float(in: Float(latency.lowerBound)...Float(latency.upperBound)))
            let sent = t
            let hostTime = sent + up + trueOffset
            let received = sent + up + down
            clock.addSample(sent: sent, received: received, hostTime: hostTime)
            t += 2
        }
        return clock.offset
    }

    func testEstimateWithin20msUnderJitter() {
        for seed in 1...20 {
            let off = estimate(trueOffset: 1234.5678, latency: 0.05...0.10, samples: 20, seed: UInt64(seed))
            XCTAssertEqual(off, 1234.5678, accuracy: 0.02, "seed \(seed)")
        }
        XCTAssertEqual(estimate(trueOffset: -987.6, latency: 0.03...0.12, samples: 30, seed: 9), -987.6, accuracy: 0.03)
    }

    func testFirstSampleIsUsedAtOnce() {
        var c = ClockSync()
        XCTAssertFalse(c.hasSample)
        c.addSample(sent: 10, received: 10.1, hostTime: 510.05)           // rtt 0.1, offset = 510.05 + 0.05 - 10.1 = 500
        XCTAssertEqual(c.offset, 500, accuracy: 1e-9)
        XCTAssertEqual(c.hostTime(local: 20), 520, accuracy: 1e-9)
    }

    func testSmallChangesAreSmoothedAndBigOnesJump() {
        var c = ClockSync()
        c.addSample(sent: 0, received: 0.1, hostTime: 100.05)             // offset 100
        // rtt のもっと小さい回が来て, 見つもりが 0.2 秒だけ動く → なめらかに 1 秒かけて.
        c.addSample(sent: 1, received: 1.02, hostTime: 101.21)            // offset = 101.21 + 0.01 - 1.02 = 100.2
        XCTAssertEqual(c.offset, 100, accuracy: 1e-9, "not yet")
        c.update(dt: 0.5)
        XCTAssertEqual(c.offset, 100.1, accuracy: 0.01)
        for _ in 0..<10 { c.update(dt: 0.5) }
        XCTAssertEqual(c.offset, 100.2, accuracy: 0.001)
        // 0.5 秒をこえるずれは すぐ合わせる.
        var d = ClockSync()
        d.addSample(sent: 0, received: 0.1, hostTime: 100.05)
        d.addSample(sent: 1, received: 1.01, hostTime: 105.0)             // 5 秒ずれた
        XCTAssertEqual(d.offset, 105 + 0.005 - 1.01, accuracy: 1e-9)
    }

    func testRestartKeepsTheOffsetUntilNewSamples() {
        var c = ClockSync()
        c.addSample(sent: 0, received: 0.1, hostTime: 100.05)
        c.restart()
        XCTAssertFalse(c.hasSample)
        XCTAssertEqual(c.offset, 100, accuracy: 1e-9)
        c.addSample(sent: 5, received: 5.1, hostTime: 300.05)
        XCTAssertEqual(c.offset, 295, accuracy: 1e-9)
    }
}

final class InterpolationTests: XCTestCase {
    func state(_ seq: UInt16, t: Double, x: Float, z: Float = 0, vx: Float = 0, yaw: Float = 0, flags: PlayerFlags = [.grounded, .alive]) -> PlayerStateMessage {
        PlayerStateMessage(slot: 1, seq: seq, timeMs: UInt32(t * 1000), position: Vec3(x, 2, z), yaw: yaw, pitch: 0,
                           velocity: Vec3(vx, 0, 0), flags: flags, weapon: .handgun)
    }

    func testWalkingIsSmooth() throws {
        var b = InterpolationBuffer()
        for i in 0..<20 { b.add(state(UInt16(i), t: Double(i) * 0.05, x: Float(i) * 0.3, vx: 6)) }      // 20 Hz で 6 m/s
        var last: Float = -1
        for k in 0..<100 {
            let t = 0.1 + Double(k) * 0.008
            let p = try XCTUnwrap(b.pose(at: t))
            XCTAssertEqual(p.position.x, Float(t) * 6, accuracy: 0.01)
            XCTAssertGreaterThanOrEqual(p.position.x, last)
            last = p.position.x
        }
    }

    func testOneLostPacketIsBridged() throws {
        var b = InterpolationBuffer()
        for i in 0..<10 where i != 5 { b.add(state(UInt16(i), t: Double(i) * 0.05, x: Float(i) * 0.3, vx: 6)) }
        // 抜けた 0.25 秒ぶんの前後でも まっすぐつながる.
        XCTAssertEqual(try XCTUnwrap(b.pose(at: 0.25)).position.x, 1.5, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(b.pose(at: 0.27)).position.x, 1.62, accuracy: 0.01)
    }

    func testOutOfOrderAndDuplicatePacketsDoNotGoBack() throws {
        var b = InterpolationBuffer()
        b.add(state(1, t: 0.05, x: 0.3))
        b.add(state(3, t: 0.15, x: 0.9))
        b.add(state(2, t: 0.10, x: 0.6))            // おくれて届いた(捨てる)
        b.add(state(3, t: 0.15, x: 0.9))            // 同じものが 2 度
        XCTAssertEqual(b.samples.count, 2)
        XCTAssertEqual(try XCTUnwrap(b.pose(at: 0.10)).position.x, 0.6, accuracy: 0.01)    // 1 と 3 のあいだを補間
    }

    func testSequenceNumbersWrapAround() {
        var b = InterpolationBuffer()
        b.add(state(65534, t: 1.0, x: 0))
        b.add(state(65535, t: 1.05, x: 1))
        b.add(state(0, t: 1.10, x: 2))              // 一周した(新しい)
        b.add(state(1, t: 1.15, x: 3))
        XCTAssertEqual(b.samples.count, 4)
        b.add(state(65535, t: 1.05, x: 1))          // 古い
        XCTAssertEqual(b.samples.count, 4)
    }

    func testYawTakesTheShortWayAcrossZero() throws {
        var b = InterpolationBuffer()
        b.add(state(1, t: 0, x: 0, yaw: 6.2))
        b.add(state(2, t: 0.1, x: 0, yaw: 0.2))      // 359° → 11°: 逆まわりしない
        let mid = try XCTUnwrap(b.pose(at: 0.05)).yaw
        XCTAssertEqual(wrapAngle(mid), 0, accuracy: 0.1)
        XCTAssertTrue(mid > 6.0 || mid < 0.4)
    }

    func testExtrapolationIsLimitedAndTeleportIsNotSmoothed() throws {
        var b = InterpolationBuffer()
        b.add(state(1, t: 0, x: 0, vx: 6))
        b.add(state(2, t: 0.05, x: 0.3, vx: 6))
        XCTAssertEqual(try XCTUnwrap(b.pose(at: 0.15)).position.x, 0.3 + 0.6, accuracy: 0.01)         // 最後の速度でのばす
        XCTAssertEqual(try XCTUnwrap(b.pose(at: 5)).position.x, 0.3 + 6 * 0.25, accuracy: 0.01)     // 250 ms で止まる
        var t = InterpolationBuffer()
        t.add(state(1, t: 0, x: 0))
        t.add(state(2, t: 0.05, x: 50))              // 50 m 飛んだ(やり直し・通信の乱れ)
        XCTAssertEqual(try XCTUnwrap(t.pose(at: 0.025)).position.x, 0, accuracy: 1e-4, "no smoothing across a teleport")
        XCTAssertEqual(try XCTUnwrap(t.pose(at: 0.06)).position.x, 50, accuracy: 0.5)
        XCTAssertNil(InterpolationBuffer().pose(at: 0))
    }

    func testHistoryIsTrimmed() {
        var b = InterpolationBuffer()
        for i in 0..<100 { b.add(state(UInt16(i), t: Double(i) * 0.05, x: 0)) }
        XCTAssertLessThan(b.samples.count, 30)
        XCTAssertEqual(b.latest?.seq, 99)
    }
}
