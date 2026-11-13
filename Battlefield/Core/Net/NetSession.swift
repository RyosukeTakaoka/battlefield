import Foundation

/// 自分の今の姿(毎コマ `NetSession.tick` に渡す).
struct LocalSnapshot: Equatable {
    var player: PlayerState
    var flags: PlayerFlags
    var weapon: WeaponKind
}

/// 通信の司会役(`docs/NETCODE.md` §3〜§9). Core の中の 値 で, 送る・受けるは `Data` と `PeerHandle` だけ.
/// 実際に送るのは `MatchTransport`(本番は `GameKitTransport`)なので, ここは Linux でテストできる.
///
/// 使い方:
/// 1. つながったら `begin(peers:now:)` → 返った `Outgoing`(hello)を送る
/// 2. 届いたら `receive`, 切れたら `peerChanged`, 毎コマ `tick`
/// 3. ホストは「はじめる」で `startMatch`
/// 4. 画面は `match`(写し)・`drainEvents()`・`remotePose(slot:now:)` を読む
///
/// 時刻は「自分の時計(秒)」を渡す. 試合の時刻はすべて「ホストの時計」(自分の時計 + `clock.offset`).
struct NetSession {
    enum Status: Equatable {
        /// hello がそろうのを待っている.
        case connecting
        case lobby
        case inMatch
        /// 通信の版が違う人がいる.
        case versionMismatch
    }

    struct PeerInfo: Equatable {
        var peerKey: UInt64
        var name: String
        var connected: Bool
    }

    let world: ArenaWorld
    let myKey: UInt64
    let myName: String
    private let seed: UInt64

    private(set) var status: Status = .connecting
    /// hello を受けた人.
    private(set) var peers: [PeerHandle: PeerInfo] = [:]
    private var expected: Set<PeerHandle> = []
    private var begun = false
    private(set) var hostKey: UInt64?
    private(set) var hostEpoch = 0
    private(set) var match = MatchState()
    private(set) var clock = ClockSync()
    private var host: HostLogic?
    private var buffers: [Int: InterpolationBuffer] = [:]
    private var events: [MatchEvent] = []
    private var shots: [ShotFxMessage] = []
    private var seq: UInt16 = 0
    private var lastStateSend: Double = -1000
    private var lastPing: Double = -1000
    private var pingsSent = 0

    static let stateInterval = 1.0 / 20
    static let stateIntervalCrowded = 1.0 / 15
    static let crowdedHumans = 5

    init(world: ArenaWorld, myKey: UInt64, name: String, seed: UInt64 = 1) {
        self.world = world
        self.myKey = myKey
        myName = name
        self.seed = seed
    }

    // MARK: - 読み出し

    var isHost: Bool { hostKey == myKey }
    var mySlot: Int? { match.participants.first { $0.peerKey == myKey && !$0.isBot }?.slot }
    /// 試合に出ている人間の数(自分を含む. ロビーでは hello を受けた人 + 自分).
    var humanCount: Int {
        status == .inMatch ? match.participants.filter { !$0.isBot && !$0.left }.count : 1 + peers.values.filter { $0.connected }.count
    }

    /// ロビーに出す名簿(自分も入る. peerKey の小さい順 = ホストが先).
    var lobbyPlayers: [(name: String, peerKey: UInt64, isHost: Bool, isMe: Bool)] {
        let all = [(myName, myKey)] + peers.values.filter { $0.connected }.map { ($0.name, $0.peerKey) }
        return all.sorted { $0.1 < $1.1 }.map { (name: $0.0, peerKey: $0.1, isHost: $0.1 == hostKey, isMe: $0.1 == myKey) }
    }

    func hostNow(local: Double) -> Double { clock.hostTime(local: local) }

    /// 相手の, 画面に出す姿(「今 - 100 ms」の補間).
    func remotePose(slot: Int, now: Double) -> RemotePose? {
        buffers[slot]?.pose(at: hostNow(local: now) - InterpolationBuffer.renderDelay)
    }

    /// 最後に届いた姿(当たり判定の位置・ホストの引きつぎに使う).
    func latestPose(slot: Int) -> RemotePose? { buffers[slot]?.latest?.pose }

    mutating func drainEvents() -> [MatchEvent] {
        defer { events = [] }
        return events
    }

    mutating func drainShots() -> [ShotFxMessage] {
        defer { shots = [] }
        return shots
    }

    // MARK: - つながる・ロビー

    /// つながった(`expectedPlayerCount == 0`)あと 1 回. 相手がいなければ(れんしゅう)すぐ ロビー(自分がホスト).
    mutating func begin(peers handles: [PeerHandle], now: Double) -> [Outgoing] {
        expected = Set(handles)
        begun = true
        evaluateLobby()
        return [Outgoing(data: MessageCodec.encode(.hello(HelloMessage(protocolVersion: MessageCodec.protocolVersion, peerKey: myKey, name: myName))),
                         to: nil, reliable: true)]
    }

    /// hello がそろったら, peerKey がいちばん小さい人がホスト.
    private mutating func evaluateLobby() {
        guard begun, status == .connecting else { return }
        let connected = expected.filter { peers[$0] != nil }
        guard connected.count == expected.count else { return }
        let keys = [myKey] + connected.compactMap { peers[$0]?.peerKey }
        hostKey = keys.min()
        status = .lobby
        if isHost { host = HostLogic(world: world, seed: seed) }
    }

    // MARK: - 試合を始める(ホスト)

    /// 「はじめる」(「もう一度」も同じ). 人間は peerKey の小さい順に slot 0 から, ボットはそのあと.
    mutating func startMatch(kind: GameMode.Kind? = nil, bots: Int = 0, now: Double) -> [Outgoing] {
        guard isHost, status == .lobby || status == .inMatch, var h = host else { return [] }
        let hn = hostNow(local: now)
        var humans: [(UInt64, String)] = [(myKey, myName)]
        for p in peers.values where p.connected { humans.append((p.peerKey, p.name)) }
        humans.sort { $0.0 < $1.0 }
        if status == .inMatch {                       // もう一度: 試合に残っている人だけ
            let stay = Set(match.participants.filter { !$0.left && !$0.isBot }.map(\.peerKey))
            humans = humans.filter { stay.contains($0.0) }
        }
        var roster = humans.enumerated().map { RosterEntry(slot: $0.offset, peerKey: $0.element.0, name: $0.element.1, isBot: false) }
        for i in 0..<max(0, min(bots, GameRules.maxPlayers - roster.count)) {
            roster.append(RosterEntry(slot: roster.count, peerKey: 0, name: "ボット\(i + 1)", isBot: true))
        }
        guard roster.count >= 2 else { return [] }
        let chosen = kind ?? GameMode.defaultKind(playerCount: roster.count)
        let matchId = match.matchId &+ 1
        let msgs = h.beginMatch(matchId: matchId, kind: chosen, roster: roster, now: hn)
        host = h
        return broadcast(msgs, now: now)
    }

    // MARK: - 毎コマ

    mutating func tick(now: Double, local: LocalSnapshot?) -> [Outgoing] {
        var out: [Outgoing] = []
        guard status != .connecting, status != .versionMismatch else { return out }
        if !isHost { clock.update(dt: max(0, now - lastTick)) }
        lastTick = now
        let hn = hostNow(local: now)
        events += match.advance(now: hn)

        if status == .inMatch {
            // 自分の状態を送る.
            if let l = local, let slot = mySlot, match.participant(slot)?.alive == true {
                let interval = humanCount >= Self.crowdedHumans ? Self.stateIntervalCrowded : Self.stateInterval
                if now - lastStateSend >= interval {
                    lastStateSend = now
                    seq &+= 1
                    let m = PlayerStateMessage(slot: slot, seq: seq, timeMs: UInt32(clamping: Int((hn * 1000).rounded())),
                                               position: l.player.position, yaw: l.player.yaw, pitch: l.player.pitch,
                                               velocity: l.player.velocity, flags: l.flags, weapon: l.weapon)
                    out.append(Outgoing(data: MessageCodec.encode(.playerState(m)), to: nil, reliable: false))
                    host?.observe(slot: slot, position: l.player.position, weapon: l.weapon)
                }
            }
        }

        // 時計合わせ(ホスト以外). 始めの 5 回は 0.3 秒ごと, そのあとは 2 秒ごと.
        if !isHost, let target = hostHandle, status == .inMatch || status == .lobby {
            let gap = pingsSent < 5 ? 0.3 : 2.0
            if now - lastPing >= gap {
                lastPing = now
                pingsSent += 1
                out.append(Outgoing(data: MessageCodec.encode(.ping(clientMs: UInt32(clamping: Int((now * 1000).rounded())))),
                                    to: [target], reliable: false))
            }
        }

        // ホストの仕事.
        if isHost, status == .inMatch, var h = host {
            let msgs = h.tick(state: match, now: hn)
            host = h
            out += broadcast(msgs, now: now)
        }
        return out
    }
    private var lastTick: Double = 0

    // MARK: - 自分の行動を送る

    /// 撃った・ひろう・ぬける など自分の行動. 申し出(hitClaim / pickupRequest)はホストへ, shotFx は全員へ.
    mutating func send(_ message: Message, now: Double) -> [Outgoing] {
        switch message {
        case .hitClaim, .pickupRequest:
            if isHost { return hostHandleLocal(message, sender: mySlot, now: now) }
            guard let target = hostHandle else { return [] }
            return [Outgoing(data: MessageCodec.encode(message), to: [target], reliable: true)]
        case .shotFx, .leave:
            return [Outgoing(data: MessageCodec.encode(message), to: nil, reliable: message.isReliable)]
        default:
            return []
        }
    }

    /// ホストが動かすボットの行動(位置・申し出). ボットの slot の人として扱う.
    mutating func submitBot(_ message: Message, now: Double) -> [Outgoing] {
        guard isHost else { return [] }
        switch message {
        case .playerState(let m):
            host?.observe(slot: m.slot, position: m.position, weapon: m.weapon)
            buffers[m.slot, default: InterpolationBuffer()].add(m)
            return [Outgoing(data: MessageCodec.encode(message), to: nil, reliable: false)]
        case .hitClaim(let c):
            return hostHandleLocal(message, sender: c.attacker, now: now)
        case .shotFx:
            return [Outgoing(data: MessageCodec.encode(message), to: nil, reliable: false)]
        default:
            return []
        }
    }

    private mutating func hostHandleLocal(_ message: Message, sender: Int?, now: Double) -> [Outgoing] {
        guard var h = host, let sender else { return [] }
        let msgs = h.handle(message, sender: sender, state: match, now: hostNow(local: now))
        host = h
        return broadcast(msgs, now: now)
    }

    /// ホストが決めたメッセージを, 自分の写しに反映して(道を 1 本にする), 全員へ送る.
    private mutating func broadcast(_ msgs: [Message], now: Double) -> [Outgoing] {
        var out: [Outgoing] = []
        let hn = hostNow(local: now)
        for m in msgs {
            // 送る形(位置は cm, 時刻は ms に丸めたもの)に直してから 自分にも反映する.
            // 全員(ホストも)が まったく同じ値の写しを持つ(丸める前の値で反映すると, 端末ごとに ごく小さくずれる).
            let data = MessageCodec.encode(m)
            let sent = MessageCodec.decode(data) ?? m
            events += match.apply(sent, now: hn)
            if case .startRound = m { didStartRound() }
            out.append(Outgoing(data: data, to: nil, reliable: m.isReliable))
        }
        return out
    }

    private mutating func didStartRound() {
        status = .inMatch
        buffers = [:]
        shots = []
    }

    // MARK: - 届いたもの

    private var hostHandle: PeerHandle? {
        peers.first { $0.value.peerKey == hostKey && $0.value.connected }?.key
    }

    private func slot(for handle: PeerHandle) -> Int? {
        guard let key = peers[handle]?.peerKey else { return nil }
        return match.participants.first { $0.peerKey == key && !$0.isBot }?.slot
    }

    private func isFromHost(_ handle: PeerHandle) -> Bool {
        peers[handle]?.peerKey == hostKey
    }

    mutating func receive(_ data: Data, from handle: PeerHandle, now: Double) -> [Outgoing] {
        guard let message = MessageCodec.decode(data) else { return [] }
        let hn = hostNow(local: now)
        switch message {
        case .hello(let m):
            if m.protocolVersion != MessageCodec.protocolVersion {
                status = .versionMismatch
                return []
            }
            peers[handle] = PeerInfo(peerKey: m.peerKey, name: m.name, connected: true)
            evaluateLobby()

        case .startRound:
            guard isFromHost(handle) else { return [] }
            events += match.apply(message, now: hn)
            didStartRound()

        case .playerState(let m):
            // 本人の slot から来たものだけ. ホストは ボットの位置も送る.
            let ownSlot = slot(for: handle)
            let fromHostForBot = isFromHost(handle) && match.participant(m.slot)?.isBot == true
            guard m.slot == ownSlot || fromHostForBot, m.slot != mySlot else { return [] }
            buffers[m.slot, default: InterpolationBuffer()].add(m)
            if isHost, !fromHostForBot { host?.observe(slot: m.slot, position: m.position, weapon: m.weapon) }

        case .shotFx(let m):
            let ownSlot = slot(for: handle)
            let fromHostForBot = isFromHost(handle) && match.participant(m.slot)?.isBot == true
            guard m.slot == ownSlot || fromHostForBot else { return [] }
            shots.append(m)

        case .ping(let ms):
            guard isHost else { return [] }
            return [Outgoing(data: MessageCodec.encode(.pong(clientMs: ms, hostMs: UInt32(clamping: Int((hn * 1000).rounded())))),
                             to: [handle], reliable: false)]

        case .pong(let c, let h):
            guard !isHost, isFromHost(handle) else { return [] }
            clock.addSample(sent: Double(c) / 1000, received: now, hostTime: Double(h) / 1000)

        case .hitClaim, .pickupRequest:
            guard isHost, let sender = slot(for: handle) else { return [] }
            return hostHandleLocal(message, sender: sender, now: now)

        case .damage, .vitals, .respawn, .lootTaken, .lootRestored, .roundEnd:
            guard isFromHost(handle) else { return [] }
            events += match.apply(message, now: hn)

        case .hostSnapshot(let m):
            guard isFromHost(handle), m.hostEpoch >= hostEpoch else { return [] }
            hostEpoch = max(hostEpoch, m.hostEpoch)
            events += match.apply(message, now: hn)

        case .leave(let leaver):
            // ホスト: 本人から来たものを元に, 「やられた扱い + ぬけた」を決めて全員へ知らせる.
            // ホスト以外: ホストが知らせたものだけを反映する(本人から直接来たものは, ホストへ知らせるためのもの. 順番が前後しない).
            if isHost, var h = host {
                guard slot(for: handle) == leaver else { return [] }
                let msgs = h.playerLeft(slot: leaver, state: match, now: hn)
                host = h
                return broadcast(msgs, now: now)
            }
            guard isFromHost(handle) else { return [] }
            events += match.apply(message, now: hn)
        }
        return []
    }

    // MARK: - 切れた・つながった

    mutating func peerChanged(_ handle: PeerHandle, connected: Bool, now: Double) -> [Outgoing] {
        guard !connected else { return [] }
        expected.remove(handle)
        guard let info = peers[handle] else { return [] }
        peers[handle]?.connected = false
        let hn = hostNow(local: now)
        let wasHost = info.peerKey == hostKey

        switch status {
        case .connecting:
            evaluateLobby()
            return []
        case .lobby:
            if wasHost { electHostInLobby() }
            return []
        case .inMatch:
            if wasHost && !isHost { return migrateHost(lost: info.peerKey, now: now) }
            // ホストが, 切れた人をやられた扱いにする.
            guard isHost, var h = host,
                  let slot = match.participants.first(where: { $0.peerKey == info.peerKey && !$0.isBot })?.slot else { return [] }
            let msgs = h.playerLeft(slot: slot, state: match, now: hn)
            host = h
            return broadcast(msgs, now: now)
        case .versionMismatch:
            return []
        }
    }

    private mutating func electHostInLobby() {
        let keys = [myKey] + peers.values.filter { $0.connected }.map(\.peerKey)
        hostKey = keys.min()
        if isHost, host == nil { host = HostLogic(world: world, seed: seed) }
    }

    /// ホストが切れた(`docs/NETCODE.md` §8). 残っている人の中で peerKey がいちばん小さい人が新しいホスト
    /// (全員が同じ計算をするので, 相談はいらない).
    private mutating func migrateHost(lost: UInt64, now: Double) -> [Outgoing] {
        let hn = hostNow(local: now)
        let connectedKeys = Set(peers.values.filter { $0.connected }.map(\.peerKey)).union([myKey])
        let candidates = match.participants.filter { !$0.isBot && !$0.left && connectedKeys.contains($0.peerKey) && $0.peerKey != lost }
        guard let newHost = candidates.map(\.peerKey).min() else { return [] }
        hostKey = newHost
        hostEpoch += 1
        if newHost == myKey {
            var h = HostLogic(world: world, seed: seed ^ (UInt64(hostEpoch) &* 0x9E37_79B9))
            h.adopt(state: match, epoch: hostEpoch, now: hn)
            for (slot, buf) in buffers {
                if let p = buf.latest?.pose { h.observe(slot: slot, position: p.position, weapon: p.weapon) }
            }
            // 自分の時計を, そのまま本物の時計にする(ずれは そのまま固定).
            var out: [Outgoing] = []
            if let oldSlot = match.participants.first(where: { $0.peerKey == lost && !$0.isBot })?.slot {
                out += broadcast(h.playerLeft(slot: oldSlot, state: match, now: hn), now: now)
            }
            let snap = h.makeSnapshot(match)
            out.append(Outgoing(data: MessageCodec.encode(.hostSnapshot(snap)), to: nil, reliable: true))
            host = h
            return out
        }
        // ほかの人: 新しいホストへ ping し直して, 時計を合わせ直す.
        clock.restart()
        pingsSent = 0
        lastPing = -1000
        if let oldSlot = match.participants.first(where: { $0.peerKey == lost && !$0.isBot })?.slot {
            events += match.apply(.leave(slot: oldSlot), now: hn)
        }
        return []
    }
}
