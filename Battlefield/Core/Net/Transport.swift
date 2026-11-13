import Foundation

/// その端末の中だけで通じる, 相手の番号(`GameKitTransport` が `GKPlayer` と対応させる).
typealias PeerHandle = Int

/// 送る・受ける だけの口. 中身(ルール)は知らない. `docs/NETCODE.md` §2.
/// 実物は 3 つ: `GameKitTransport`(本番) / `LoopbackTransport`(1 人 + ボット) / テスト用の `SimulatedNetwork`.
protocol MatchTransport: AnyObject {
    /// つながっている相手(自分は入らない).
    var peers: [PeerHandle] { get }
    /// to が nil なら全員へ. reliable は「かならず届く(少しおそい)」.
    func send(_ data: Data, to: [PeerHandle]?, reliable: Bool)
    var onReceive: ((Data, PeerHandle) -> Void)? { get set }
    /// つながった(true) / 切れた(false).
    var onPeerChange: ((PeerHandle, Bool) -> Void)? { get set }
    func disconnect()
}

/// 相手がいない口(「れんしゅう」: 自分がホストで, 相手はボット).
final class LoopbackTransport: MatchTransport {
    var peers: [PeerHandle] { [] }
    var onReceive: ((Data, PeerHandle) -> Void)?
    var onPeerChange: ((PeerHandle, Bool) -> Void)?
    func send(_ data: Data, to: [PeerHandle]?, reliable: Bool) {}
    func disconnect() {}
}

/// `NetSession` が「送りたいもの」として返す 1 通.
struct Outgoing: Equatable {
    var data: Data
    /// nil = つながっている全員.
    var to: [PeerHandle]?
    var reliable: Bool
}
