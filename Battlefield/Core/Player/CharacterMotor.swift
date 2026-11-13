import Foundation

/// 人の動きの計算(走る・ジャンプ・落ちる). 描画も通信も知らない.
/// 固定の刻み(`GameRules.tick`)で呼ぶと, 60 fps でも 30 fps でも同じ動きになる.
enum CharacterMotor {
    static func step(_ state: inout PlayerState, input: PlayerInput, world: ArenaWorld, dt: Float) {
        state.yaw = input.yaw
        state.pitch = clamp(input.pitch, -1.4, 1.4)

        // 目標の横の速さ.
        var wish = state.right * input.moveX + state.forward * input.moveY
        if wish.length > 1 { wish = wish.normalized() }
        let speed = input.aiming ? GameRules.aimSpeed : GameRules.runSpeed
        let target = wish * speed

        if state.isGrounded {
            // 地上は入力のとおりに動く(すぐ追いつく).
            state.velocity.x = target.x
            state.velocity.z = target.z
            state.velocity.y = 0
            if input.jump {
                state.velocity.y = GameRules.jumpSpeed
                state.isGrounded = false
            }
        } else {
            // 空中は少ししか曲がれない.
            let k = min(1, GameRules.airControl * 10 * dt)
            state.velocity.x += (target.x - state.velocity.x) * k
            state.velocity.z += (target.z - state.velocity.z) * k
        }
        if !state.isGrounded { state.velocity.y -= GameRules.gravity * dt }

        // 横に動く(かべ・水・崖・急な坂で止まる).
        let moved = world.resolveMove(from: state.position,
                                      to: state.position + Vec3(state.velocity.x * dt, 0, state.velocity.z * dt))
        state.position.x = moved.x
        state.position.z = moved.z

        // 縦に動く.
        let wasGrounded = state.isGrounded
        var y = state.position.y + state.velocity.y * dt
        let ground = world.surfaceHeight(x: state.position.x, z: state.position.z,
                                         feetY: state.position.y)
        if y <= ground + 1e-4 {
            // 降りてきた / 段を上がった.
            y = ground
            state.velocity.y = 0
            state.isGrounded = true
        } else if wasGrounded && state.velocity.y <= 0 && y - ground <= GameRules.groundSnap {
            // 下り坂ではりつく.
            y = ground
            state.velocity.y = 0
            state.isGrounded = true
        } else {
            state.isGrounded = false
        }
        state.position.y = y
    }
}
