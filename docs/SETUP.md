# 動かすまでの手順(人がやること)

コードは AI が Linux の上で書きます. Linux では iPad / iPhone のアプリをビルドできないので,
**ビルドと実機での確認は, Mac を持っているあなたの仕事** です. やることは次の 3 つだけです.

## 1. Mac でビルドする(M3 から)

1. Xcode 16 以降で `Battlefield.xcodeproj` を開きます(`Package.swift` はテスト用なので, 開くのはプロジェクトの方です).
2. 左の一覧のいちばん上 → ターゲット **Battlefield** → **Signing & Capabilities**
   - Team: 自分のチーム(Airplane と同じ)
   - Bundle Identifier: `app.takaoka.com.battlefield`(変えてもかまいません. 変えたら AI に伝えてください)
   - 「Game Center」が一覧にあることを確かめます(無ければ「+ Capability」から足します)
3. 実行先を, つないだ iPad か iPhone(iOS / iPadOS 18 以降)にして ▶︎ を押します.
4. **エラーが出たら, 赤い文字をそのままコピーして AI に貼ってください.** はじめてのビルドでは, 何個か出るのがふつうです
   (AI は Apple の部品を使う所を, 動かさずに書いているためです).

## 2. Game Center を使えるようにする(M7 の前に 1 回だけ)

Game Center の対戦は, アプリが App Store Connect に登録されていないと動きません(アプリを公開する必要はありません).

1. Apple Developer Program(有料の開発者登録)に入っていることを確かめます. Airplane を実機で動かせているなら大丈夫です.
2. [App Store Connect](https://appstoreconnect.apple.com) →「アプリ」→「+」→「新規 App」
   - プラットフォーム: iOS / バンドル ID: 上で決めたもの / 名前: 仮の名前(あとで変えられます)
3. 作ったアプリのページで **Game Center を有効** にします.
4. 画面の名前や場所は, ときどき変わります. 見つからないときは, AI に「App Store Connect で Game Center を有効にする今の手順を調べて」と頼んでください.

## 3. 2 台で対戦を試す(M7 から)

- **端末が 2 台, Apple Account が 2 つ** 必要です(同じアカウントどうしでは対戦できません). 家族や友だちの端末を借りるのが簡単です.
- 2 台とも: 「設定」→「Game Center」でログインし, Xcode からアプリを入れます.
- 試し方は 2 つあります.
  - **友だちとして呼ぶ**: 片方で「オンライン対戦」→ 相手を招待 → もう片方に通知が来る
  - **おまかせ**: 2 台で同時に「オンライン対戦」→「今すぐプレイ」のようなボタン(同じアプリを開いている人どうしがつながります)
- 同じ Wi-Fi にいると, つながりやすいです. 学校の Wi-Fi は, 端末どうしの通信を止めていることがあります. だめなら家の Wi-Fi か, テザリングで.
- うまくいかないときに AI に伝えること: 2 台それぞれの画面に何が出たか / Xcode の下の欄(コンソール)の文字 / 設定で「通信のようす」を出したときの表示.

## 4. Core のテスト(Mac でも Linux でも. AI が毎回やります)

```sh
swift test
```

## 5. 島のデータを作り直す(M2 から. AI がやります)

```sh
pip install numpy pillow
python3 Tools/map/build_arena.py
```

---

## 最初のビルドで確かめること(AI が書き足していく表)

Linux で書いたため, Apple の部品を使うファイルは **まだ一度もコンパイルしていません**(文法だけは `swiftc -parse` で確かめた).
Core(`Battlefield/Core/`)は Linux で 167 件のテストが通っています. 下の表のとおり, 使っている API の一覧です.
エラーが出たら, 赤い文字を そのまま AI に貼ってください.

| 場所 | 使っている API | 根拠 |
|---|---|---|
| `Rendering/AssetLibrary.swift`, `PostProcess/*`, `Materials.swift` | `Entity.load(named:in:)`, `MeshResource.contents`, `TextureResource.load`, `ARView.renderCallbacks.postProcess`, `PhysicallyBasedMaterial`, `UnlitMaterial` | Airplane でそのまま使用ずみ |
| `Rendering/SceneDirector.swift` | `ARView(frame:cameraMode:automaticallyConfigureSession:)`, `renderOptions`, `EnvironmentResource(equirectangular:)`, `DirectionalLightComponent.Shadow`, `SceneEvents.Update`, `PerspectiveCamera` | Airplane の `SceneDirector` と同じ |
| `Rendering/ArenaScene.swift` | `ModelEntity(mesh:materials:)`, `MeshResource.generateBox(size:)`, `Task.detached` で作ったメッシュを `MeshData.meshResource` へ | Airplane の `CourseScene.build` と同じ形 |
| `Rendering/CharacterRig.swift` | `ModelEntity()`, `ModelComponent(mesh:materials:)`, `MeshResource.generateBox(size:cornerRadius:)`, `generateSphere(radius:)`, `simd_quatf` | 新しく書いた(RealityKit の基本の API) |
| `Rendering/CombatEffects.swift` | `Entity.look(at:from:relativeTo:)`, `isEnabled`, `scale` | 新しく書いた |
| `Game/BattleController.swift` | `@Observable`, `@ObservationIgnored`, `ProcessInfo.systemUptime` | iOS 17 の Observation |
| `Features/Game/TouchControlsView.swift` | `UIViewRepresentable`, `touchesBegan / Moved / Ended / Cancelled`, `isMultipleTouchEnabled`, `UIView.safeAreaInsets`, `safeAreaInsetsDidChange()`, `TimelineView(.periodic)` | 新しく書いた |
| `Features/Game/GameScreen.swift` | `.defersSystemGestures(on:)`(画面のはしのタッチを iOS より先にゲームへ) | iOS 16 から |
| `Features/Game/HUDView.swift`, `MinimapView.swift` | `Canvas`, `Path`, `.blendMode(.destinationOut)` + `compositingGroup()`, `Image(uiImage:)` | 新しく書いた |
| `Features/*` | `@Environment(AppModel.self)`, `@Bindable`, `confirmationDialog`, `Picker(.segmented)` | iOS 17 |
| `Services/Audio/SoundEngine.swift` | `AVAudioEngine`, `AVAudioPlayerNode`, `AVAudioPCMBuffer` | Airplane の方式 |
| `Services/GameCenter/GameCenterAuth.swift` | `GKLocalPlayer.local.authenticateHandler`, `isAuthenticated`, `isMultiplayerGamingRestricted`, `displayName` | Apple の文書で確認(2026-11-13) |
| `Services/GameCenter/Matchmaking.swift` | `GKMatchRequest`(`minPlayers`, `maxPlayers`, `maxPlayersAllowedForMatch(of:)`), `GKMatchmakerViewController(matchRequest:)` / `(invite:)`, `matchmakerDelegate`, `GKMatchmakerViewControllerDelegate`(`didFind` / `WasCancelled` / `didFailWithError`), `GKLocalPlayer.local.register(_:)`, `GKInviteEventListener.player(_:didAccept:)` | Apple の文書で確認 |
| `Services/GameCenter/GameKitTransport.swift` | `GKMatch`(`players`, `expectedPlayerCount`, `delegate`, `send(_:to:dataMode:)`, `sendData(toAllPlayers:with:)`, `disconnect()`), `GKMatch.SendDataMode`(`.reliable` / `.unreliable`), `GKMatchDelegate`(`match(_:didReceive:fromRemotePlayer:)`, `match(_:player:didChange:)`, `match(_:didFailWithError:)`), `GKPlayerConnectionState` | Apple の文書で確認 |

特に エラーが出やすそうな所(コンパイルしていないため):
- `GameKitTransport` / `Matchmaking` の `nonisolated` なデリゲートの書き方(Swift の並行処理の設定で 警告が出ることがある. 警告なら そのままで動く).
- `ArenaScene.build` の `Task.detached`(Airplane と同じ形).
- `HUDView` の `ScopeOverlay`(穴あきのマスク).

## 実機で見て確かめること(Airplane と同じ注意)

- **ロードの時間**: Xcode の下の欄(コンソール)に `[ロード] 小物の形を読む(13 種類): 0.82 秒(ここまで 1.10 秒)` のような行が出る.
  「島をつくっています」が長いと感じたら, この行を全部 AI に貼る(どこが遅いか分かる)

- **島の絵の向き**: 村の広場(灰色の円)が 実際の村の家の下にあるか. ずれていたら `AssetLibrary.detectUVOrigin` の判定か `ArenaScene.build` の絵の割りふり(`island_0〜3` = 西北・東北・西南・東南)を確かめる
- **ボタンの大きさ・場所**: iPhone / iPad で押しやすいか(`Core/Input/TouchLayout.swift` の `buttons`)
- **ねらいやすさ**: 感度(設定)・構えたときの感度(`BattleController.update` の `sens`)
- 地面の絵の向き: 絵の道と, 実際の名所の場所が合っているか(UV の上下は `AssetLibrary.detectUVOrigin` が起動時に判定)
- 明るさ: 白く飛ぶ・暗すぎるときは `SceneDirector` の太陽と環境光の数字を直す
- 霧: 真っ白・真っ黒になるときは, いったん `PostProcessor` を外して確かめる
- 速さ: 60 fps が出ないときは, 木の数・影の距離を減らす
