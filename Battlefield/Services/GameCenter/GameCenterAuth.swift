import GameKit
import Observation
import UIKit

/// Game Center へのログイン(`docs/NETCODE.md` §10).
/// アプリを開いたら `start()`. ログインできていないときや, 制限されているときは「オンライン対戦」を押せなくする.
@MainActor
@Observable
final class GameCenterAuth {
    enum State: Equatable {
        case checking
        case signedIn
        /// ログインしていない(設定アプリの Game Center でログインしてもらう).
        case signedOut
        /// 年齢などの制限で, 対戦が使えない.
        case restricted
    }

    private(set) var state: State = .checking
    private(set) var displayName = ""
    private(set) var message: String?
    /// ログインできたとき 1 回(招待を受ける準備をする).
    @ObservationIgnored var onSignedIn: (() -> Void)?
    @ObservationIgnored private var announced = false

    var canPlayOnline: Bool { state == .signedIn }

    func start() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            // どのスレッドから呼ばれるか決まっていないので, メインへ渡す.
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.handle(viewController: viewController, error: error) }
            }
        }
    }

    private func handle(viewController: UIViewController?, error: Error?) {
        if let viewController {
            // ログインの画面を出す必要がある.
            UIKitHelpers.topViewController()?.present(viewController, animated: true)
            return
        }
        let local = GKLocalPlayer.local
        if local.isAuthenticated {
            displayName = local.displayName
            if local.isMultiplayerGamingRestricted {
                state = .restricted
                message = "この端末では, 対戦がせいげんされています."
            } else {
                state = .signedIn
                message = nil
                if !announced { announced = true; onSignedIn?() }
            }
        } else {
            state = .signedOut
            message = error?.localizedDescription ?? "Game Center にログインすると, 友だちと対戦できます(設定アプリ → Game Center)."
        }
    }
}
