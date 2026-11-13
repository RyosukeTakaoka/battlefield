import GameKit
import UIKit

/// 人あつめの画面(友だち・近くの人・おまかせ)と, 招待を受ける(`docs/NETCODE.md` §10).
@MainActor
final class Matchmaking: NSObject, GKMatchmakerViewControllerDelegate, GKLocalPlayerListener {
    /// 人がそろって `GKMatch` ができた.
    var onMatch: ((GKMatch) -> Void)?
    var onCancel: (() -> Void)?
    var onError: ((String) -> Void)?

    private var isPresenting = false

    /// Game Center が許す人数の上限(Apple の文書では 16. ただし 決め打ちせず, 起動時に聞く).
    static var maxPlayersAllowed: Int { GKMatchRequest.maxPlayersAllowedForMatch(of: .peerToPeer) }

    /// ゲームが耐えられる人数(`GameRules.maxPlayers`)と, Game Center の上限の小さい方.
    static var maxPlayers: Int { min(GameRules.maxPlayers, maxPlayersAllowed) }

    /// 招待を受けられるようにする(ログインできたあとに 1 回).
    func registerInviteListener() {
        GKLocalPlayer.local.register(self)
    }

    /// 人あつめの画面を出す.
    func present() {
        guard !isPresenting else { return }
        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = Self.maxPlayers
        guard let vc = GKMatchmakerViewController(matchRequest: request) else {
            onError?("人あつめの画面を開けませんでした.")
            return
        }
        vc.matchmakerDelegate = self
        isPresenting = true
        UIKitHelpers.topViewController()?.present(vc, animated: true)
    }

    // MARK: 招待(GKLocalPlayerListener / GKInviteEventListener)

    nonisolated func player(_ player: GKPlayer, didAccept invite: GKInvite) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.present(invite: invite) }
        }
    }

    private func present(invite: GKInvite) {
        guard !isPresenting, let vc = GKMatchmakerViewController(invite: invite) else { return }
        vc.matchmakerDelegate = self
        isPresenting = true
        UIKitHelpers.topViewController()?.present(vc, animated: true)
    }

    // MARK: GKMatchmakerViewControllerDelegate

    nonisolated func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFind match: GKMatch) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.isPresenting = false
                viewController.dismiss(animated: true)
                self.onMatch?(match)
            }
        }
    }

    nonisolated func matchmakerViewControllerWasCancelled(_ viewController: GKMatchmakerViewController) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.isPresenting = false
                viewController.dismiss(animated: true)
                self.onCancel?()
            }
        }
    }

    nonisolated func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFailWithError error: Error) {
        let text = error.localizedDescription
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.isPresenting = false
                viewController.dismiss(animated: true)
                self.onError?(text)
            }
        }
    }
}
