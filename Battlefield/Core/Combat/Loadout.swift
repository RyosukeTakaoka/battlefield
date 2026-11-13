import Foundation

/// 持っている武器(枠 2 つ), 弾倉の残り, 連射とリロードの時間.
/// 時刻はすべて「試合の時計(秒)」. 描画や通信を知らない.
struct Loadout: Equatable {
    static let slotCount = 2
    /// 武器を切りかえたあと, 撃てるようになるまで.
    static let swapDelay: Double = 0.3

    private(set) var slots: [WeaponKind?]
    private(set) var ammo: [Int]
    private(set) var selected = 0
    private(set) var nextFireTime: Double = 0
    private(set) var reloadEndsAt: Double?
    /// 前のコマで撃つボタンを押していたか.
    private var wasTriggerHeld = false
    var isAiming = false

    /// 武器の組から始める(弾は満タン).
    init(weapons: [WeaponKind?]) {
        var s = Array(weapons.prefix(Self.slotCount))
        while s.count < Self.slotCount { s.append(nil) }
        slots = s
        ammo = s.map { $0.map { WeaponSpec.spec($0).magazine } ?? 0 }
    }

    /// ハンドガンだけ.
    static var starter: Loadout { Loadout(weapons: [.handgun, nil]) }

    var current: WeaponKind? { slots[selected] }
    var currentSpec: WeaponSpec? { current.map(WeaponSpec.spec) }
    var currentAmmo: Int { ammo[selected] }
    var isReloading: Bool { reloadEndsAt != nil }
    var otherSlotHasWeapon: Bool { slots[1 - selected] != nil }

    /// 毎コマ: リロードが終わったら弾を満タンにする.
    mutating func update(now: Double) {
        if let end = reloadEndsAt, now >= end {
            if let spec = currentSpec { ammo[selected] = spec.magazine }
            reloadEndsAt = nil
        }
    }

    func canFire(now: Double) -> Bool {
        current != nil && !isReloading && ammo[selected] > 0 && now >= nextFireTime
    }

    /// 撃つボタンの状態を渡す. 撃てたら true(弾を 1 発使う). 弾が空になったら自動でリロードを始める.
    /// タッチ画面では 押しっぱなしの方が 動きながら撃ちやすいので, どの武器も 押しているあいだ
    /// その武器の速さ(`fireRate`)で撃ち続ける(`automatic` は 将来 コントローラーで使うために残してある).
    mutating func pullTrigger(held: Bool, now: Double) -> Bool {
        defer { wasTriggerHeld = held }
        guard held, let spec = currentSpec else { return false }
        if ammo[selected] == 0 {
            startReload(now: now)         // 空のまま押したら, リロードを始める
            return false
        }
        guard canFire(now: now) else { return false }
        ammo[selected] -= 1
        nextFireTime = now + Double(spec.fireInterval)
        if ammo[selected] == 0 { startReload(now: now) }
        return true
    }

    mutating func startReload(now: Double) {
        guard let spec = currentSpec, !isReloading, ammo[selected] < spec.magazine else { return }
        reloadEndsAt = now + Double(spec.reloadTime)
    }

    /// もう 1 つの枠へ切りかえる(無ければ何もしない). リロードは取り消し.
    mutating func switchSlot(now: Double) {
        guard otherSlotHasWeapon else { return }
        selected = 1 - selected
        reloadEndsAt = nil
        nextFireTime = max(nextFireTime, now + Self.swapDelay)
    }

    /// 武器をひろう. 空いている枠があればそこへ, いっぱいなら 今持っている武器と入れかえる.
    /// 戻り値は 手ばなした武器(あれば).
    @discardableResult
    mutating func pickUp(_ weapon: WeaponKind, now: Double) -> WeaponKind? {
        let spec = WeaponSpec.spec(weapon)
        if let empty = slots.firstIndex(where: { $0 == nil }) {
            slots[empty] = weapon
            ammo[empty] = spec.magazine
            if current == nil { selected = empty }
            return nil
        }
        let old = slots[selected]
        slots[selected] = weapon
        ammo[selected] = spec.magazine
        reloadEndsAt = nil
        nextFireTime = max(nextFireTime, now + Self.swapDelay)
        return old
    }

    /// 空いている枠があるか(自動でひろえるか).
    var hasFreeSlot: Bool { slots.contains { $0 == nil } }

    /// やられて生き返ったとき: ハンドガンだけに戻る.
    mutating func reset(to weapons: [WeaponKind?]) {
        self = Loadout(weapons: weapons)
    }
}
