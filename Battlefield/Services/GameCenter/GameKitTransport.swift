import GameKit

/// `GKMatch` を `MatchTransport` として包む(`docs/NETCODE.md` §2). **ルールは 1 行も書かない**: データを送る・受ける だけ.
///
/// - 相手は `GKPlayer`. こちらでは `PeerHandle`(0 から数える番号)で呼ぶ.
/// - `GKMatchDelegate` はどのスレッドで呼ばれるか決まっていないので, かならずメインへ渡してから Core にさわる.
/// - 送るのに失敗しても落とさない(ログに出して続ける).
@MainActor
final class GameKitTransport: NSObject, MatchTransport, GKMatchDelegate {
    private let match: GKMatch
    private var players: [PeerHandle: GKPlayer] = [:]
    private var handles: [GKPlayer: PeerHandle] = [:]
    private var connected: Set<PeerHandle> = []
    private var nextHandle = 0

    var onReceive: ((Data, PeerHandle) -> Void)?
    var onPeerChange: ((PeerHandle, Bool) -> Void)?
    /// 全員がつながった(`expectedPlayerCount == 0`)とき 1 回.
    var onAllConnected: (() -> Void)?
    /// 自分だけ通信が切れた(全員と切れた)とき.
    var onFailure: ((String) -> Void)?
    private var announcedAll = false

    init(match: GKMatch) {
        self.match = match
        super.init()
        for p in match.players { register(p) }
        // 最初のメッセージを落とさないよう, `GKMatch` をもらったらすぐ delegate を付ける.
        match.delegate = self
    }

    // GKMatch.players に自分は入っていない.
    var peers: [PeerHandle] { connected.sorted() }
    var expectedPlayerCount: Int { match.expectedPlayerCount }

    /// 画面から呼ぶ: まだ待っているなら onAllConnected を後で呼ぶ. 揃っていれば すぐ呼ぶ.
    func startListening() {
        checkAllConnected()
    }

    private func checkAllConnected() {
        guard !announcedAll, match.expectedPlayerCount == 0 else { return }
        announcedAll = true
        onAllConnected?()
    }

    @discardableResult
    private func register(_ player: GKPlayer) -> PeerHandle {
        if let h = handles[player] { return h }
        let h = nextHandle
        nextHandle += 1
        players[h] = player
        handles[player] = h
        connected.insert(h)
        return h
    }

    func send(_ data: Data, to targets: [PeerHandle]?, reliable: Bool) {
        let mode: GKMatch.SendDataMode = reliable ? .reliable : .unreliable
        do {
            if let targets {
                let list = targets.compactMap { connected.contains($0) ? players[$0] : nil }
                guard !list.isEmpty else { return }
                try match.send(data, to: list, dataMode: mode)
            } else {
                guard !connected.isEmpty else { return }
                try match.sendData(toAllPlayers: data, with: mode)
            }
        } catch {
            NSLog("GameKitTransport: send failed: \(error.localizedDescription)")
        }
    }

    func disconnect() {
        match.disconnect()
        match.delegate = nil
    }

    // MARK: GKMatchDelegate(どのスレッドから呼ばれても メインへ渡す)

    nonisolated func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let h = self.handles[player] ?? self.register(player)
                self.onReceive?(data, h)
            }
        }
    }

    nonisolated func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                switch state {
                case .connected:
                    let h = self.register(player)
                    self.connected.insert(h)
                    self.onPeerChange?(h, true)
                    self.checkAllConnected()
                case .disconnected:
                    if let h = self.handles[player] {
                        self.connected.remove(h)
                        self.onPeerChange?(h, false)
                    }
                default:
                    break
                }
            }
        }
    }

    nonisolated func match(_ match: GKMatch, didFailWithError error: Error?) {
        let text = error?.localizedDescription ?? "通信が切れました."
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                for h in self.connected.sorted() { self.onPeerChange?(h, false) }
                self.connected = []
                self.onFailure?(text)
            }
        }
    }
}
