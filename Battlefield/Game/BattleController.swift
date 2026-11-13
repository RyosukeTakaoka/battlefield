import Foundation
import Observation
import RealityKit
import UIKit

/// 1 試合を動かす司会役(`docs/DESIGN.md` §2「毎コマの順番」).
///
/// 入力(指) → 自分を進める(`CharacterMotor`) → 撃つ(`Hitscan`・申し出) → 通信(`NetSession`) → ホストならボット → 出来事(音・演出)
/// → 相手の姿(補間) → カメラ(`ThirdPersonCamera`) → 描画(`SceneDirector`). ルール・物理・通信の中身は Core にあり, ここは「つなぐ」だけ.
///
/// 「れんしゅう」も オンラインも同じ道: 自分がホストで, 相手が全部ボットの試合が「れんしゅう」.
@MainActor
@Observable
final class BattleController {
    enum LoadState: Equatable {
        case loading(Double)
        case ready
        case failed(String)
    }

    /// 画面に出すもの(ロビー・戦い・結果・切断).
    enum UIPhase: Equatable {
        case loading
        case connecting
        case lobby
        case match
        case finished
        case disconnected(String)
    }

    enum Mode {
        case practice(kind: GameMode.Kind, bots: Int, difficulty: BotDifficulty)
        case online
    }

    struct ScoreLine: Equatable, Identifiable {
        var id: Int
        var name: String
        var score: Int
        var kills: Int
        var alive: Bool
        var isMe: Bool
    }

    /// 画面の上に出す数字(1 秒に 15 回だけ更新して, SwiftUI を重くしない).
    struct HUD: Equatable {
        var hp = 100
        var shield = 0
        var ammo = 0
        var magazine = 0
        var weaponName = ""
        var slotNames: [String?] = [nil, nil]
        var selectedSlot = 0
        var reload: Float?
        var aliveCount = 0
        var playerCount = 0
        var kills = 0
        var roundText = ""
        var modeText = ""
        var zoneText = ""
        var zone: Disc?
        var outsideZone = false
        var playerX: Float = 0
        var playerZ: Float = 0
        var playerYaw: Float = 0
        var arena: Disc?
        var scores: [ScoreLine] = []
        var countdown: Int?
        var aiming = false
        var scope = false
        var pickupPrompt: String?
        var spectating: String?
        var alive = true
        var netText: String?
    }

    struct Toast: Equatable, Identifiable {
        enum Style { case info, good, bad, big }
        let id = UUID()
        var text: String
        var style: Style
    }

    struct FeedItem: Equatable, Identifiable {
        let id = UUID()
        var text: String
        var mine: Bool
        var expires: Double
    }

    struct Result: Equatable {
        struct Row: Equatable, Identifiable {
            var id: Int
            var name: String
            var placement: Int
            var kills: Int
            var score: Int
            var isMe: Bool
        }
        var rows: [Row]
        var winnerName: String?
        var iWon: Bool
        var modeText: String
    }

    // MARK: 画面が読むもの

    private(set) var loadState: LoadState = .loading(0)
    private(set) var phase: UIPhase = .loading
    private(set) var hud = HUD()
    private(set) var toast: Toast?
    private(set) var feed: [FeedItem] = []
    private(set) var result: Result?
    /// ロビー: 名簿と, ホストか.
    private(set) var lobbyPlayers: [(name: String, isHost: Bool, isMe: Bool)] = []
    private(set) var isHost = false
    private(set) var hitMarker: Float = 0
    private(set) var headMarker = false
    private(set) var damageAngle: Float?
    private(set) var damageAlpha: Float = 0
    var lobbyKind: GameMode.Kind = .roundBattle
    var lobbyBots = 0
    @ObservationIgnored var onExit: (() -> Void)?

    /// 指(`TouchControlsView` が書きこむ. 画面の更新のたびに SwiftUI が再描画しないよう 監視の外).
    @ObservationIgnored var touch = TouchLayout(width: 844, height: 390)

    // MARK: 中身

    @ObservationIgnored private let settings: GameSettings
    @ObservationIgnored private let mode: Mode
    @ObservationIgnored private let myName: String
    @ObservationIgnored private let assets = AssetLibrary()
    @ObservationIgnored private let sound = SoundEngine()
    @ObservationIgnored private let director: SceneDirector
    @ObservationIgnored private let charactersRoot = Entity()
    @ObservationIgnored private let effects = CombatEffects()
    @ObservationIgnored private var arena: ArenaScene?
    @ObservationIgnored private var world: ArenaWorld?
    @ObservationIgnored private var rigs: [Int: CharacterRig] = [:]
    @ObservationIgnored private var session: NetSession?
    @ObservationIgnored private var transport: MatchTransport
    @ObservationIgnored private var bots: BotRunner?
    @ObservationIgnored private var player = PlayerState(position: .zero)
    @ObservationIgnored private var loadout = Loadout.starter
    @ObservationIgnored private var cameraRig = ThirdPersonCamera()
    @ObservationIgnored private var cameraPose: ThirdPersonCamera.Pose?
    @ObservationIgnored private var rng = SeededRandom(seed: UInt64.random(in: 1...UInt64.max))
    @ObservationIgnored private var accumulator: Float = 0
    @ObservationIgnored private var hudTimer: Float = 0
    @ObservationIgnored private var time: Float = 0
    @ObservationIgnored private var shotId: UInt16 = 0
    @ObservationIgnored private var lastPickup: [Int: Double] = [:]
    @ObservationIgnored private var spectateSlot: Int?
    @ObservationIgnored private var toastExpires: Double = 0
    @ObservationIgnored private var lastEmptyClick: Double = 0
    @ObservationIgnored private var lastZoneBeep: Double = 0
    @ObservationIgnored private var damageFade: Float = 0
    @ObservationIgnored private var started = false
    @ObservationIgnored private var peersReady = false
    @ObservationIgnored private var spectateTap = false
    @ObservationIgnored private var kickPitch: Float = 0
    @ObservationIgnored private var pendingPrompt: String?

    init(mode: Mode, settings: GameSettings, playerName: String, transport: MatchTransport? = nil) {
        self.mode = mode
        self.settings = settings
        myName = playerName.isEmpty ? "プレイヤー" : playerName
        self.transport = transport ?? LoopbackTransport()
        director = SceneDirector(quality: settings.quality)
        sound.volume = Float(settings.soundVolume)
        touch.leftHanded = settings.leftHanded
        touch.invertY = settings.invertY
        touch.lookSensitivity = 0.006 * Float(settings.lookSensitivity)
    }

    /// SwiftUI の `GameView` が使う 3D の画面.
    func makeView() -> ARView {
        director.onUpdate = { [weak self] dt in self?.update(dt: dt) }
        return director.view
    }

    private var now: Double { ProcessInfo.processInfo.systemUptime }

    // MARK: - 読み込み

    func load() async {
        guard !started else { return }
        started = true
        LoadTimer.lap("ロード開始")
        do {
            guard let jsonURL = Bundle.main.url(forResource: "island", withExtension: "json"),
                  let heightURL = Bundle.main.url(forResource: "island", withExtension: "height") else {
                throw AssetLibrary.AssetError.missing("island.json / island.height")
            }
            let map = try MapData.decode(from: Data(contentsOf: jsonURL))
            let terrain = try Heightfield(data: Data(contentsOf: heightURL))
            let world = ArenaWorld(map: map, terrain: terrain)
            self.world = world
            loadState = .loading(0.05)
            LoadTimer.lap("島のデータを読む")
            // 進み具合は その場で書く(メインスレッドの上). 以前は `Task { }` で あとから書いていたため,
            // `.ready` にしたあとで「ロード中」に戻ってしまい, ロード画面から抜けられないことがあった.
            let scene = try await ArenaScene.build(world: world, assets: assets, quality: settings.quality) { [weak self] p in
                guard let self, case .loading = self.loadState else { return }
                self.loadState = .loading(p)
            }
            arena = scene
            director.install(arena: scene, characters: charactersRoot, effects: effects.root, map: map, assets: assets,
                             quality: settings.quality)
            LoadTimer.lap("画面に置く")
            sound.start()
            startSession(world: world)
            LoadTimer.lap("試合の準備")
            loadState = .ready
            LoadTimer.done()
        } catch {
            loadState = .failed(error.localizedDescription)
            phase = .disconnected("読み込みに失敗しました: \(error.localizedDescription)")
        }
    }

    private func startSession(world: ArenaWorld) {
        var s = NetSession(world: world, myKey: UInt64.random(in: 1...UInt64.max), name: myName,
                           seed: UInt64.random(in: 1...UInt64.max))
        switch mode {
        case .practice(let kind, let n, let difficulty):
            bots = BotRunner(world: world, difficulty: difficulty, seed: UInt64.random(in: 1...UInt64.max))
            // 相手がいないので, begin のあと すぐ ロビー(自分がホスト)になる. そのまま はじめる.
            send(s.begin(peers: [], now: now))
            send(s.startMatch(kind: kind, bots: n, now: now))
            session = s
            phase = .match
        case .online:
            phase = .connecting
            session = s
            transport.onReceive = { [weak self] data, handle in self?.receive(data, from: handle) }
            transport.onPeerChange = { [weak self] handle, connected in self?.peerChanged(handle, connected) }
            if let gk = transport as? GameKitTransport {
                gk.onAllConnected = { [weak self] in self?.beginOnline() }
                gk.onFailure = { [weak self] text in self?.phase = .disconnected(text) }
                gk.startListening()
            } else {
                beginOnline()
            }
        }
    }

    private func beginOnline() {
        guard var s = session, !peersReady else { return }
        peersReady = true
        send(s.begin(peers: transport.peers, now: now))
        session = s
    }

    private func receive(_ data: Data, from handle: PeerHandle) {
        guard var s = session else { return }
        let out = s.receive(data, from: handle, now: now)
        session = s
        send(out)
    }

    private func peerChanged(_ handle: PeerHandle, _ connected: Bool) {
        guard var s = session else { return }
        let out = s.peerChanged(handle, connected: connected, now: now)
        session = s
        send(out)
    }

    private func send(_ outgoing: [Outgoing]) {
        for o in outgoing { transport.send(o.data, to: o.to, reliable: o.reliable) }
    }

    // MARK: - ロビー・結果からの操作

    /// ロビー(オンライン): ホストが「はじめる」.
    func hostStart() {
        guard var s = session, s.isHost else { return }
        send(s.startMatch(kind: lobbyKind, bots: lobbyBots, now: now))
        session = s
    }

    /// 結果の画面: ホストが「もう一度」.
    func rematch() {
        guard var s = session, s.isHost else { return }
        let kind = s.match.mode.kind
        let bots = s.match.participants.filter { $0.isBot }.count
        send(s.startMatch(kind: kind, bots: bots, now: now))
        session = s
        result = nil
    }

    /// 「やめる」.
    func leave() {
        if var s = session, let slot = s.mySlot, s.status == .inMatch {
            send(s.send(.leave(slot: slot), now: now))
            session = s
        }
        transport.disconnect()
        director.tearDown()
        sound.stop()
        onExit?()
    }

    /// 観戦中に画面をタップ: 見る相手を切りかえる.
    func cycleSpectate() { spectateTap = true }

    // MARK: - 毎コマ

    private func update(dt rawDt: Float) {
        guard loadState == .ready, var s = session, let world, let arena else { return }
        let dt = min(rawDt, 0.1)
        time += dt
        let local = now
        let hostNow = s.hostNow(local: local)

        // 通信: 毎コマ 1 回. 自分の姿・ホストの仕事・時計合わせ.
        let me0 = s.mySlot.flatMap { s.match.participant($0) }
        var snapshot: LocalSnapshot?
        if let me0, me0.alive, s.match.phase == .playing {
            var flags: PlayerFlags = [.alive]
            if player.isGrounded { flags.insert(.grounded) }
            if touch.isHeld(.fire) { flags.insert(.firing) }
            if loadout.isReloading { flags.insert(.reloading) }
            if touch.isHeld(.aim) { flags.insert(.aiming) }
            snapshot = LocalSnapshot(player: player, flags: flags, weapon: loadout.current ?? .handgun)
        }
        send(s.tick(now: local, local: snapshot))

        // 出来事.
        let events = s.drainEvents()
        let shots = s.drainShots()
        session = s
        handle(events: events, session: &s, hostNow: hostNow)
        if var b = bots, s.isHost {
            b.observe(events: events, match: s.match, now: hostNow)
            bots = b
        }
        let match = s.match
        let mySlot = s.mySlot
        let me = mySlot.flatMap { match.participant($0) }

        // 画面の状態.
        updatePhase(s)

        // 自分: 入力 → 動き → 撃つ → ひろう.
        let look = touch.takeLook()
        let pressed = touch.takePressed()
        let aiming = touch.isHeld(.aim)
        let sens: Float = aiming ? 0.55 : 1
        player.yaw += look.yaw * sens
        player.pitch = clamp(player.pitch + look.pitch * sens, -1.35, 1.35)
        let canAct = (me?.alive ?? false) && match.phase == .playing && s.status == .inMatch
        let frozen = (me?.alive ?? false) && match.phase == .countdown
        loadout.isAiming = aiming
        if canAct || frozen {
            accumulator += dt
            var steps = 0
            var first = true
            while accumulator >= GameRules.tick && steps < 6 {
                accumulator -= GameRules.tick
                steps += 1
                if canAct {
                    var input = PlayerInput()
                    input.moveX = touch.move.x
                    input.moveY = touch.move.y
                    input.yaw = player.yaw
                    input.pitch = player.pitch
                    input.aiming = aiming
                    input.jump = first && pressed.contains(.jump)
                    CharacterMotor.step(&player, input: input, world: world, dt: GameRules.tick)
                    first = false
                }
            }
            if player.position.y < GameRules.killY { player.position.y = world.terrainHeight(x: player.position.x, z: player.position.z) + 1 }
        } else {
            accumulator = 0
        }

        if canAct {
            loadout.update(now: local)
            if pressed.contains(.reload), loadout.currentAmmo < (loadout.currentSpec?.magazine ?? 0), !loadout.isReloading {
                loadout.startReload(now: local)
                sound.play(.reload)
            }
            if pressed.contains(.switchWeapon) {
                let before = loadout.current
                loadout.switchSlot(now: local)
                if loadout.current != before { sound.play(.switchWeapon) }
            }
            let held = touch.isHeld(.fire)
            if loadout.pullTrigger(held: held, now: local) {
                fire(session: &s, world: world, now: local, mySlot: mySlot)
            } else if held, loadout.currentAmmo == 0, local - lastEmptyClick > 0.4 {
                lastEmptyClick = local
                sound.play(.empty)
            }
            requestPickups(session: &s, match: match, mySlot: mySlot, interact: pressed.contains(.interact), now: local)
        } else {
            pendingPrompt = nil
        }

        // ホストなら, ボットを動かす.
        if s.isHost, var b = bots, match.phase != .lobby {
            var humans: [Int: Vec3] = [:]
            for p in match.participants where !p.isBot && !p.left {
                if p.slot == mySlot { humans[p.slot] = player.position }
                else if let pose = s.latestPose(slot: p.slot) { humans[p.slot] = pose.position }
            }
            let msgs = b.update(now: hostNow, dt: dt, match: match, humans: humans)
            bots = b
            for m in msgs { send(s.submitBot(m, now: local)) }
        }
        session = s

        // 相手の弾の線・音.
        for shot in shots where shot.slot != mySlot { showRemoteShot(shot) }

        render(session: s, match: match, me: me, mySlot: mySlot, aiming: aiming, dt: dt, arena: arena, local: local)
        effects.update(dt: dt)

        // 当たりの印・撃たれた向きをうすれさせる.
        if hitMarker > 0 { hitMarker = max(0, hitMarker - dt * 5) }
        damageFade = max(0, damageFade - dt * 1.2)
        if damageAlpha != damageFade { damageAlpha = damageFade }
        kickPitch *= (1 - approach(12, dt))

        if toast != nil, local > toastExpires { toast = nil }
        if feed.contains(where: { local > $0.expires }) { feed.removeAll { local > $0.expires } }

        hudTimer += dt
        if hudTimer >= 1.0 / 15 {
            hudTimer = 0
            updateHUD(session: s, match: match, me: me, mySlot: mySlot, hostNow: hostNow)
        }
    }

    // MARK: - 撃つ・ひろう

    private func fire(session s: inout NetSession, world: ArenaWorld, now: Double, mySlot: Int?) {
        guard let spec = loadout.currentSpec, let mySlot, let cam = cameraPose else { return }
        let session = s
        var targets: [Hitscan.Target] = []
        for p in session.match.participants where p.slot != mySlot && p.alive && !p.left {
            if let pose = session.remotePose(slot: p.slot, now: now) { targets.append(Hitscan.Target(slot: p.slot, feet: pose.position)) }
        }
        let aim = Hitscan.aimPoint(world: world, cameraPosition: cam.position, cameraDirection: cam.forward, targets: targets)
        let results = Hitscan.fire(world: world, shooterFeet: player.position, aimPoint: aim, targets: targets, spec: spec,
                                   aiming: touch.isHeld(.aim), rng: &rng)
        // 見た目と音.
        rigs[mySlot]?.muzzleFlash()
        sound.play(Self.shotSound(spec.kind))
        kickPitch = spec.kind == .sniper ? 0.05 : 0.012
        player.pitch = clamp(player.pitch + kickPitch * 0.4, -1.35, 1.35)
        var any = false
        var perTarget: [Int: (pellets: Int, head: Bool, distance: Float)] = [:]
        var fxShots: [ShotFxMessage.Shot] = []
        for r in results {
            effects.tracer(from: r.origin + (r.end - r.origin).normalized() * 0.6, to: r.end)
            var kind: UInt8 = 0
            switch r.kind {
            case .none: kind = 0
            case .ground: kind = 1; effects.spark(at: r.end)
            case .obstacle: kind = 2; effects.spark(at: r.end)
            case .player(let slot, let head):
                kind = 3
                effects.spark(at: r.end)
                any = true
                var cur = perTarget[slot] ?? (0, false, r.distance)
                cur.pellets += 1
                cur.head = cur.head || head
                cur.distance = min(cur.distance, r.distance)
                perTarget[slot] = cur
            }
            fxShots.append(.init(end: r.end, hitKind: kind))
        }
        if any { hitMarker = 1 }
        // 通信: 見た目は全員へ(信頼なし), 当たりはホストへ申し出る(信頼あり).
        let origin = results.first?.origin ?? player.eye
        send(s.send(.shotFx(ShotFxMessage(slot: mySlot, weapon: spec.kind, origin: origin, shots: fxShots)), now: now))
        for (slot, hit) in perTarget.sorted(by: { $0.key < $1.key }) {
            shotId &+= 1
            send(s.send(.hitClaim(HitClaimMessage(shotId: shotId, attacker: mySlot, target: slot, weapon: spec.kind, head: hit.head,
                                                  pellets: hit.pellets, distance: hit.distance)), now: now))
        }
    }

    private static func shotSound(_ w: WeaponKind) -> SoundEngine.Effect {
        switch w {
        case .handgun: return .shotHandgun
        case .assaultRifle: return .shotRifle
        case .shotgun: return .shotShotgun
        case .sniper: return .shotSniper
        }
    }

    /// 近くのひろうもの: 回復と空き枠の武器は自動で. 枠がいっぱいの武器は「もちかえる」ボタンで.
    private func requestPickups(session s: inout NetSession, match: MatchState, mySlot: Int?, interact: Bool, now: Double) {
        guard let mySlot, let me = match.participant(mySlot), let world else { return }
        var prompt: String?
        for item in match.loot where !item.taken && item.id < world.map.loot.count {
            let spot = vec(world.map.loot[item.id])
            let d = (spot - player.position).horizontal.length
            guard d <= LootKind.autoPickupRange, abs(spot.y - player.position.y) < 3 else { continue }
            var want = false
            switch item.kind {
            case .shield: want = me.shield < GameRules.maxShield
            case .medkit: want = me.hp < GameRules.maxHP
            default:
                if loadout.hasFreeSlot { want = true }
                else if let w = item.kind.weapon {
                    prompt = "もちかえる: \(WeaponSpec.spec(w).name)"
                    want = interact
                }
            }
            if want, now - (lastPickup[item.id] ?? -10) > 0.4 {
                lastPickup[item.id] = now
                send(s.send(.pickupRequest(PickupRequestMessage(lootId: item.id, slot: mySlot)), now: now))
            }
        }
        pendingPrompt = prompt
    }

    private func showRemoteShot(_ shot: ShotFxMessage) {
        for s in shot.shots {
            effects.tracer(from: shot.origin + (s.end - shot.origin).normalized() * 0.6, to: s.end)
            if s.hitKind != 0 { effects.spark(at: s.end) }
        }
        rigs[shot.slot]?.muzzleFlash()
        let d = (shot.origin - player.position).length
        sound.play(Self.shotSound(shot.weapon), gain: clamp(1 - d / 90, 0.12, 0.9))
    }

    // MARK: - 出来事

    private func handle(events: [MatchEvent], session s: inout NetSession, hostNow: Double) {
        let match = s.match
        let mySlot = s.mySlot
        func name(_ slot: Int) -> String { match.participant(slot)?.name ?? "?" }
        for e in events {
            switch e {
            case .roundStarting(let round, _):
                resetLocalForRound(match: match, mySlot: mySlot)
                arena?.setLoot(match.loot)
                ensureRigs(match: match)
                spectateSlot = nil
                result = nil
                let title: String
                switch match.mode.kind {
                case .roundBattle: title = "ラウンド \(round + 1)"
                case .killRace: title = "キル勝負 \(match.mode.killTarget) キルで勝ち"
                case .battleRoyale: title = "最後の 1 人をめざせ!"
                }
                showToast(title, .big, seconds: 2.6)
            case .roundStarted:
                sound.play(.go)
                showToast("スタート!", .big, seconds: 1.2)
            case .damaged(let target, let attacker, _, _, _, let head):
                if target == mySlot {
                    sound.play(.hurt)
                    damageFade = 1
                    damageAngle = angleToAttacker(attacker, session: s)
                }
                if attacker == mySlot, target != mySlot { sound.play(head ? .headshot : .hit); hitMarker = 1; headMarker = head }
            case .eliminated(let slot, let by, _):
                let text: String
                if let by { text = "\(name(by)) → \(name(slot))" } else { text = "\(name(slot)) がやられた" }
                addFeed(text, mine: by == mySlot || slot == mySlot)
                if slot == mySlot {
                    sound.play(.eliminated)
                    showToast(by != nil ? "\(name(by!)) にやられた" : "やられた", .bad, seconds: 2.2)
                } else if by == mySlot {
                    showToast("キル!", .good, seconds: 1.2)
                }
            case .respawned(let slot):
                if slot == mySlot, let p = match.participant(slot) {
                    player = PlayerState(position: p.spawn, yaw: p.spawnYaw)
                    loadout.reset(to: [.handgun, nil])
                    cameraRig.snap()
                    spectateSlot = nil
                    showToast("ふっかつ!", .good, seconds: 1.2)
                }
            case .lootTaken(let id, let slot, let kind):
                arena?.setLoot(match.loot)
                if slot == mySlot {
                    if let w = kind.weapon {
                        loadout.pickUp(w, now: now)
                        sound.play(.pickup)
                        showToast(WeaponSpec.spec(w).name, .info, seconds: 1.0)
                    } else {
                        sound.play(.heal)
                        showToast(kind == .shield ? "シールド +25" : "回復 +50", .good, seconds: 1.0)
                    }
                }
                _ = id
            case .lootRestored:
                arena?.setLoot(match.loot)
            case .vitalsChanged:
                break
            case .roundEnded(let winner, let final):
                let won = winner == mySlot && winner != nil
                sound.play(won ? .roundWin : .roundLose)
                if final {
                    buildResult(match: match, mySlot: mySlot)
                } else {
                    let msg = winner.map { "\(name($0)) がラウンドを取った!" } ?? "ひきわけ"
                    showToast(msg, won ? .good : .info, seconds: 3.0)
                }
            case .playerLeft(let slot):
                addFeed("\(name(slot)) がぬけました", mine: false)
            }
        }
    }

    private func angleToAttacker(_ attacker: Int, session s: NetSession) -> Float? {
        guard attacker < 200, let pose = s.latestPose(slot: attacker) else { return nil }
        let d = pose.position - player.position
        let world = atan2(d.x, -d.z)                     // 相手の方角
        return wrapAngle(world - player.yaw)             // 自分の向きから見た角度(0 = 正面)
    }

    private func resetLocalForRound(match: MatchState, mySlot: Int?) {
        guard let mySlot, let me = match.participant(mySlot) else { return }
        player = PlayerState(position: me.spawn, yaw: me.spawnYaw)
        player.isGrounded = true
        let weapons: [WeaponKind?] = match.mode.sharedLoadout ? GameMode.weapons(forSet: match.loadoutSet) : [.handgun, nil]
        loadout = Loadout(weapons: weapons)
        cameraRig.snap()
        accumulator = 0
        lastPickup = [:]
        for rig in rigs.values { rig.root.isEnabled = true }
    }

    private func ensureRigs(match: MatchState) {
        for p in match.participants where rigs[p.slot] == nil {
            let rig = CharacterRig(slot: p.slot)
            rigs[p.slot] = rig
            charactersRoot.addChild(rig.root)
        }
    }

    private func showToast(_ text: String, _ style: Toast.Style, seconds: Double) {
        toast = Toast(text: text, style: style)
        toastExpires = now + seconds
    }

    private func addFeed(_ text: String, mine: Bool) {
        feed.append(FeedItem(text: text, mine: mine, expires: now + 5))
        if feed.count > 5 { feed.removeFirst(feed.count - 5) }
    }

    private func buildResult(match: MatchState, mySlot: Int?) {
        let rows = match.participants.filter { !$0.left || $0.score > 0 || $0.kills > 0 }.map {
            Result.Row(id: $0.slot, name: $0.name, placement: max($0.placement, 1), kills: $0.kills, score: $0.score,
                       isMe: $0.slot == mySlot)
        }.sorted { ($0.placement, $0.id) < ($1.placement, $1.id) }
        let winnerName = match.matchWinner.flatMap { match.participant($0)?.name }
        let modeText: String
        switch match.mode.kind {
        case .roundBattle: modeText = "ラウンド戦"
        case .killRace: modeText = "キル勝負"
        case .battleRoyale: modeText = "バトルロイヤル"
        }
        result = Result(rows: rows, winnerName: winnerName, iWon: match.matchWinner != nil && match.matchWinner == mySlot,
                        modeText: modeText)
    }

    private func updatePhase(_ s: NetSession) {
        switch s.status {
        case .connecting:
            if case .disconnected = phase { return }
            phase = .connecting
        case .lobby:
            if case .disconnected = phase { return }
            phase = .lobby
            lobbyPlayers = s.lobbyPlayers.map { (name: $0.name, isHost: $0.isHost, isMe: $0.isMe) }
            isHost = s.isHost
        case .versionMismatch:
            phase = .disconnected("アプリの版が ちがう人がいます. アプリを新しくしてください.")
        case .inMatch:
            if case .disconnected = phase { return }
            isHost = s.isHost
            phase = s.match.phase == .finished ? .finished : .match
        }
    }

    // MARK: - 描画

    private func render(session s: NetSession, match: MatchState, me: Participant?, mySlot: Int?, aiming: Bool, dt: Float,
                        arena: ArenaScene, local: Double) {
        guard let world else { return }
        ensureRigs(match: match)
        let tNow = match.matchTime(at: s.hostNow(local: local))
        for p in match.participants {
            guard let rig = rigs[p.slot] else { continue }
            if p.left { rig.root.isEnabled = false; continue }
            if p.slot == mySlot {
                let speed = player.velocity.horizontal.length
                rig.update(position: player.position, yaw: player.yaw, pitch: player.pitch, speed: speed, grounded: player.isGrounded,
                           alive: p.alive, weapon: loadout.current ?? .handgun, dt: dt)
            } else if let pose = s.remotePose(slot: p.slot, now: local) {
                rig.update(position: pose.position, yaw: pose.yaw, pitch: pose.pitch, speed: pose.velocity.horizontal.length,
                           grounded: pose.flags.contains(.grounded), alive: p.alive, weapon: pose.weapon, dt: dt)
            } else {
                rig.update(position: p.spawn, yaw: p.spawnYaw, pitch: 0, speed: 0, grounded: true, alive: p.alive, weapon: .handgun, dt: dt)
            }
        }

        // カメラ: 自分(生きていれば), そうでなければ 観戦.
        var viewState = player
        var viewAiming = aiming
        var viewWeapon = loadout.current
        if me?.alive == false || me == nil {
            if spectateTap { spectateTap = false; spectateSlot = nextSpectate(match: match, mySlot: mySlot, from: spectateSlot) }
            let target = spectateSlot.flatMap { match.participant($0) }
            if target == nil || target?.alive == false { spectateSlot = nextSpectate(match: match, mySlot: mySlot, from: spectateSlot) }
            if let slot = spectateSlot, let pose = s.remotePose(slot: slot, now: local) {
                viewState = PlayerState(position: pose.position, yaw: pose.yaw)
                viewState.pitch = pose.pitch
                viewAiming = pose.flags.contains(.aiming)
                viewWeapon = pose.weapon
            }
        } else {
            spectateSlot = nil
        }
        let pose = cameraRig.update(player: viewState, aiming: viewAiming, weapon: viewWeapon, world: world, dt: dt)
        cameraPose = pose
        director.setCamera(pose)

        let zone = (match.phase == .countdown || match.phase == .playing) ? match.zone.circle(at: max(tNow, 0)) : nil
        arena.update(camera: pose.position, time: time, loot: match.loot, zone: zone)
    }

    private func nextSpectate(match: MatchState, mySlot: Int?, from: Int?) -> Int? {
        let alive = match.participants.filter { $0.alive && !$0.left && $0.slot != mySlot }.map(\.slot).sorted()
        guard !alive.isEmpty else { return nil }
        guard let from, let i = alive.firstIndex(of: from) else { return alive[0] }
        return alive[(i + 1) % alive.count]
    }

    // MARK: - HUD

    private func updateHUD(session s: NetSession, match: MatchState, me: Participant?, mySlot: Int?, hostNow: Double) {
        var h = hud
        h.hp = me?.hp ?? 0
        h.shield = me?.shield ?? 0
        h.alive = me?.alive ?? false
        h.ammo = loadout.currentAmmo
        h.magazine = loadout.currentSpec?.magazine ?? 0
        h.weaponName = loadout.currentSpec?.name ?? ""
        h.slotNames = (0..<2).map { i in loadout.slots[i].map { WeaponSpec.spec($0).name } }
        h.selectedSlot = 0
        if let cur = loadout.current, let idx = loadout.slots.firstIndex(where: { $0 == cur }) { h.selectedSlot = idx }
        if let end = loadout.reloadEndsAt, let spec = loadout.currentSpec {
            h.reload = clamp(1 - Float((end - now) / Double(spec.reloadTime)), 0, 1)
        } else {
            h.reload = nil
        }
        h.pickupPrompt = pendingPrompt
        h.aliveCount = match.aliveCount
        h.playerCount = match.activeCount
        h.kills = me?.kills ?? 0
        h.aiming = touch.isHeld(.aim)
        h.scope = h.aiming && loadout.current == .sniper
        h.playerX = player.position.x
        h.playerZ = player.position.z
        h.playerYaw = player.yaw
        h.arena = match.arena
        switch match.mode.kind {
        case .roundBattle: h.modeText = "ラウンド戦"; h.roundText = "ラウンド \(match.round + 1)  先に \(match.mode.winScore) 点"
        case .killRace: h.modeText = "キル勝負"; h.roundText = "先に \(match.mode.killTarget) キル"
        case .battleRoyale: h.modeText = "バトルロイヤル"; h.roundText = "のこり \(match.aliveCount) 人"
        }
        h.scores = match.participants.filter { !$0.left }.map {
            ScoreLine(id: $0.slot, name: $0.name, score: $0.score, kills: $0.kills, alive: $0.alive, isMe: $0.slot == mySlot)
        }
        let t = match.matchTime(at: hostNow)
        h.countdown = match.phase == .countdown ? max(1, Int((-t).rounded(.up))) : nil
        if match.phase == .playing {
            let c = match.zone.circle(at: t)
            h.zone = c
            h.outsideZone = (me?.alive ?? false) && !c.contains(x: player.position.x, z: player.position.z)
            if let next = match.zone.timeUntilChange(at: t) {
                h.zoneText = next.shrinking ? "円がせばまっています \(Int(next.seconds.rounded(.up)))" : "つぎの円まで \(Int(next.seconds.rounded(.up)))"
            } else {
                h.zoneText = ""
            }
            if h.outsideZone, now - lastZoneBeep > 1.0 { lastZoneBeep = now; sound.play(.zoneWarning) }
        } else {
            h.zone = nil
            h.outsideZone = false
            h.zoneText = ""
        }
        if let slot = spectateSlot, !(me?.alive ?? true) { h.spectating = match.participant(slot)?.name } else { h.spectating = nil }
        if settings.showNetStats {
            h.netText = "\(s.isHost ? "ホスト" : "クライアント") 人数 \(s.humanCount) 時計ずれ \(Int(s.clock.offset * 1000)) ms"
                + (Matchmaking.maxPlayersAllowed > 0 ? " 上限 \(Matchmaking.maxPlayersAllowed)" : "")
        }
        if h != hud { hud = h }
    }
}
