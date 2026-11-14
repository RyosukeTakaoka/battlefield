# 作業の順番

**凡例**: ☑ = 完了 / ◐ = コードは書いた(Core は Linux でテスト済み)が, **Apple の部品の層は まだ一度もビルドしていない** ので, Mac のビルドと実機の確認が残っている / ☐ = まだ.

上から順に, **1 回のセッションで 1 つ** 進める. 始める前に `docs/DESIGN.md` を読み, そのマイルストーンに書いてある節を読み直すこと.
終わったら, チェックを付けて「次の人へ」を書く.

**先に動くものを作り, 通信は後で足す** 順番にしてある:
1 人で歩ける(M3)→ 1 台でボットと 1 試合できる(M6)→ 2 台で対戦できる(M7)→ ルールを増やす(M9).

| | マイルストーン | できること | 実機での確認 |
|---|---|---|---|
| ☑ | M0 土台 | フォルダとプロジェクトがあり, `swift test` が通る | |
| ☑ | M1 世界と動き(Core) | 当たり判定と, 人の動きの計算 | |
| ☑ | M2 島のデータ | 島の高さ・地面の絵・小物の置き場 | |
| ◐ | M3 描画と操作 | **1 人で島を歩き回れる** | ★ 1 回目 |
| ☑ | M4 戦いとルール(Core) | 武器・当たり・ダメージ・ラウンド戦のルール | |
| ☑ | M5 通信(Core) | メッセージ・ホスト・時計・補間(にせの通信でテスト) | |
| ◐ | M6 ボットと「れんしゅう」 | **1 台で, ボットとラウンド戦を最後まで遊べる** | ★ 2 回目 |
| ◐ | M7 Game Center | **2 台で対戦できる** | ★ 3 回目(2 台) |
| ◐ | M8 切れたときの強さ | ホストがぬけても続く. とちゅうでやめても こわれない | ★ 4 回目 |
| ◐ | M9 ルールを増やす | キル勝負, バトルロイヤル | ★ |
| ☐ | M10 みがき | 新しい小物・キャラクター, コントローラー, ランキング など | ★ |

---

## Apple の層(M3・M6・M7 のコード. **まだビルドしていない**)

Core のあとに, Apple の部品を使う層を まとめて書いた. 文法は `swiftc -parse` で確かめたが, 型の検査(コンパイル)は Mac の Xcode でしかできない.
**次にやること: ユーザーが Mac でビルド(`docs/SETUP.md` §1)→ 出たエラーを AI に貼る → 直す → 実機で確かめる.**

| ファイル | 役目 |
|---|---|
| `App/{BattlefieldApp,AppModel,GameSettings}.swift` | 画面の行き来. 設定(UserDefaults). 「れんしゅう」「オンライン対戦」の始め方 |
| `Game/BattleController.swift` | **1 試合の司会役**. 毎コマ: 入力 → `CharacterMotor` → 撃つ(`Hitscan`・`hitClaim`) → `NetSession.tick` → ホストならボット → 出来事(音・演出・ロビー・結果) → 相手の補間 → カメラ → 描画. ロビー・結果・切断の画面の状態もここ |
| `Rendering/{SceneDirector,ArenaScene,CharacterRig,CombatEffects}.swift` | 描画. 島(4 × 4 区画 + 小物のまとめ + 海 + 空)・ひろうもの(光る箱 + 光の柱)・安全地帯(内向きの半透明の筒)・箱の人形・弾の線と火花 |
| `Services/GameCenter/{GameCenterAuth,Matchmaking,GameKitTransport,UIKitHelpers}.swift` | ログイン・人あつめの画面・招待・`GKMatch` を `MatchTransport` として包む(ルールは書かない) |
| `Services/Audio/SoundEngine.swift` | 効果音(式で波形を作る. 武器 4 種・当たり・ひろう・勝ち負け …) |
| `Features/{Root,Title,Lobby,Game,Result,Settings}/*` | タイトル・れんしゅうの設定・ロビー・ゲーム画面(HUD・ミニマップ・タッチ・ボタン)・結果・設定 |

つなぎ方の大事な約束(`BattleController`):
- 自分の姿は `NetSession.tick(now:local:)` に毎コマ渡す(試合中で生きているときだけ). 撃ったら `shotFx`(全員へ)+ `hitClaim`(ホストへ)を `NetSession.send` で.
- 出来事は `session.drainEvents()` を **1 か所で受けて**, 画面・音・`BotRunner.observe` へ配る(2 か所で drain しない).
- 自分の `Loadout` は `.roundStarting`(組で作る)・`.lootTaken`(自分の slot なら `pickUp`)・`.respawned`(`reset`)で変える.
- `now` は `ProcessInfo.processInfo.systemUptime`(0 以上の単調な値). ホストの時計は `session.hostNow(local:)`.
- `GameKitTransport` のコールバックは `DispatchQueue.main.async` でメインへ渡してから Core にさわる.
- 「れんしゅう」= `LoopbackTransport` + `begin(peers: [])` + `startMatch(kind:bots:)`. オンラインと同じ道.

実機で確かめること(★ M3 → M6 → M7 → M8 の順. 一度に全部ではなく, 動くところまでを 1 つずつ):
1. 「れんしゅう」→ ラウンド戦・ボット 1 体: 島が見える・歩ける・ジャンプできる・撃てる・ボットが撃ってくる・ラウンドの勝ち負けが出る
2. キル勝負・バトルロイヤル(ボット 3〜7 体)
3. 2 台でオンライン(SETUP §2・§3): 同じ人がホスト・撃つと相手の HP が減る・ラウンドと点が同じ・「もう一度」
4. 3〜4 台(または 2 台 + ボット)でホストのアプリを消す → 残りで続く

---

## 上限 16 人への組み直し(2026-11-13)

Apple の文書で Game Center のリアルタイム対戦の上限が 16 人と分かったので, ゲームの上限も 8 → 16 にした(`swift test` 157 件).

- `GameRules.maxPlayers = 16`, `MessageCodec.maxPlayers`(17 人以上の名簿は捨てる)も同じ値.
- 送る回数: 2〜4 人 20 回/秒, 5〜8 人 15 回/秒, 9〜16 人 10 回/秒(`NetSession.stateInterval(humans:)`). 相手を見せる遅れも 送る間隔の 2 倍(`renderDelay`. 16 人は 0.2 秒).
  `InterpolationBuffer.maxExtrapolation` を 0.25 → 0.3 秒(10 回/秒で 1 個抜けても止まらないように).
- 島のひろうもの: 44 → 64 か所(名所 10 × 4 + 道ぞい 24). 高さ・小物・地面の絵は 変えていない(`build_arena.py` の置き場だけ).
- ルール: ラウンド戦とキル勝負は 2〜4 人のまま. バトルロイヤルが 2〜16 人(5 人以上は島全体. 出発点は島のふちの 16 か所).
- 画面: 人形の色を 16 色, れんしゅうのボットは バトルロイヤルで 1〜15 体, ロビーの名簿と結果は スクロール, 点数表は 上位 5 人 + 自分.
- テスト(`SixteenPlayerTests`): 16 人のメッセージ・17 人は捨てる / 9・12・16 人の出発点が 30 m 以上はなれる /
  ボット 16 体のバトルロイヤルが終わる / 16 台をつないで(抜け 10%)最後まで同じ結果 / 人間 12 + ボット 4 で 16 人.
- **まだ確かめていないこと**: 16 台の実機での通信(遅れ・電池)と, 16 人ぶんの描画で 60 fps が出るか. 重ければ, 遠い人形を消す・小物を減らす.

---

## ロード画面から抜けられない不具合を直した(2026-11-13)

- 原因: `BattleController.load` が, 進み具合を `Task { @MainActor in loadState = .loading(p) }`(あとで実行)で書いていた.
  組み立てが終わって `.ready` にしたあとに その予約が動くと, `loadState` が「ロード中」に戻り, ロード画面のまま止まる
  (毎コマの `update` も `.ready` のときだけ動くので, ゲームも動かない).
- 直し方: 進み具合は その場で書き, `.loading` のときだけ書きかえる. `ArenaScene.build` の `progress` は `@MainActor` にした.
- ついでに: 小物の USDZ を 1 つ読むたびにバーを進めて 画面を描き直させる(`breathe()`)/ 空のドームを 2 回読まない /
  各段階の時間を コンソールに出す(`Game/LoadTimer.swift`. `[ロード] …` の行).
- Core の部分(地形・小物のまとめ・試合の準備)は, 最適化なしでも 0.4 秒ほど(`LoadBenchTests`). 遅いとすれば RealityKit 側
  (USDZ の読みこみ・メッシュを GPU へ渡す所). 実機の `[ロード]` の行で確かめる.

---

## 操作しにくい不具合を直した(2026-11-13)

ユーザーの報告: 移動しながら撃てない. ジャンプ・武器の切りかえなど, 移動以外の操作がとてもやりにくい. 原因は 4 つ重なっていた.

1. **ボタンの絵と押せる場所がずれていた**(いちばん大きい): 指の板(`TouchSurface`)は画面全体(安全な範囲の外まで)なのに,
   ボタンの絵(`ControlButtonsOverlay`)は 安全な範囲の中に描いていた. iPhone の横向きで 横 約 50 pt・縦 約 20 pt ずれ,
   撃つボタンを押しても「視点の指」になっていた. → 絵を `controller.touch`(当たり判定と同じデータ)から描き, 両方 画面全体に置く.
   ボタンは `TouchLayout.insets`(`safeAreaInsets`)の内側に置く.
2. **すばやいタップが消えていた**: 指が 0 本になるたびに `cancelAll()` を呼び, まだ読んでいない「押した」記録を消していた.
   → 指は 1 本ずつはなすだけ. `cancelAll` も押した記録は消さない. 撃つボタンも「押した瞬間」を記録する(1 コマより短いタップでも撃つ).
3. **120 Hz の画面でジャンプが消えていた**: 物理(1/60 秒)を進めないコマで押したジャンプを捨てていた. → `pendingJump` で次の物理まで覚える.
4. **画面のはしで iOS の操作が先だった** → `.defersSystemGestures(on: .all)`.

あわせて: ボタンを大きく(押せる範囲は見た目の 1.3 倍・近い方のボタン)・文字の説明つき / 移動スティックを画面に出す /
スティックのまん中に遊び(0.12)・指が外へ出たら まん中がついてくる / どの武器も 押しっぱなしで撃ち続ける(連射の速さは武器ごと) /
「もちかえる」は出ているときだけ押せる. テスト(`TouchLayoutTests`)に 動きながら撃つ・すばやいタップ・安全な範囲・押せる範囲 を足した.

押しっぱなしの連射は「予定の時刻 + 間隔」で次を決める(2026-11-14). 以前は画面のコマを待つぶん遅れ, アサルトライフルが 9 発/秒 → 約 8.6 発/秒 になっていた.

**実機で確かめること**: ボタンの大きさと場所(親指が届くか). 合わなければ `TouchLayout.buttons` の数字(はしからの pt)を変える.

---

## 当たらない・ダメージが分からない を直した(2026-11-14)

ユーザーの報告: 相手に何ダメージ与えたか分かりにくい. 全然当たらない(腕前かも). 構えるボタンを左手に.

- **照準がずれていた**(不具合): 照準は 安全な範囲のまん中, カメラは 画面全体のまん中 をねらっていた. iPhone の横向きで 約 10 pt
  (30 m 先で 約 0.8 m)上にずれていた. → 照準まわり(照準・スコープ・撃たれた向き・円の外の色・ダメージの数字)は 画面全体に置く.
- **オンラインで当たりが消えていた**(不具合): ホストの連射の確かめが きびしすぎ, かたまって届いた申し出を捨てていた → 持ち点(バケツ)に.
- ねらいの助け(`Core/Combat/AimAssist.swift`. 数字は `GameRules.aimAssist*`. 設定で切れる)/ 腰だめのばらつきを小さく /
  ボットの横の動きを 強さで変える(やさしい 0.3・ふつう 0.55・つよい 0.8).
- ダメージの数字(`BattleController.screenPopups` → `HUDView.DamagePopups`)と 相手の体力バー(`TargetBar`).
- 「構える」: 反対の手(右ききなら左)に移し, タップで 入/切(`BattleController.aimOn`).
- テスト: `AimAssistTests`(近くの敵へ寄せる・遠い/大きくずれた/かべの向こうは寄せない・いちばん近い敵・視点のブレーキ),
  `AimButtonTests`, `testClaimBurstsAreFineButSpamIsCapped`.

**実機で確かめること**: 照準のまん中に 弾が飛ぶか / 助けが強すぎ・弱すぎないか(`GameRules.aimAssistDegrees` など)/ 数字が読みやすいか.

---

## M0 土台

**目的**: 何も無いリポジトリを, Airplane と同じ形にする.

1. Swift を確かめる(`swift --version`). 無ければ入れる. 公式の手順(swift.org の Install → Linux → swiftly)を見て,
   その通りに. `download.swift.org` へは届くことを確かめてある. どうしても入らなければ, そこで止めてユーザーに伝える.
2. Airplane を手元に用意する(となりのフォルダ `../Airplane` に無ければ, `RyosukeTakaoka/Airplane` を clone する).
3. `docs/DESIGN.md` の「フォルダ」のとおりにフォルダを作る.
4. `docs/DESIGN.md` §4 の表で「そのまま写す」「写す」となっているファイル・モデル・画像を写す.
   `TerrainMesher.swift` は, `CourseWorld` に頼っている関数(`riverWater` など)を消して, コンパイルが通る形にする.
5. `Package.swift`: パッケージ名 `BattleCore`, ターゲットの場所 `Battlefield/Core`, テスト `Tests/BattleCoreTests`
   (Airplane の `Package.swift` と同じ形).
6. Xcode のプロジェクト: `PaperPlane.xcodeproj` を `Battlefield.xcodeproj` に写し, 中の `PaperPlane` を `Battlefield` に置きかえる
   (`project.pbxproj` と `xcshareddata/xcschemes/*.xcscheme`. フォルダ同期なので, ファイルの一覧は書かなくてよい).
   - `PRODUCT_BUNDLE_IDENTIFIER = app.takaoka.com.battlefield`, `TARGETED_DEVICE_FAMILY = "1,2"`(iPhone と iPad)
   - `Config/Battlefield.entitlements`: `com.apple.developer.game-center` = true だけ(CloudKit は入れない)
   - `Config/Info.plist`: Airplane のものを写し, 表示名を仮の名前に. 横向きだけ.
7. `App/BattlefieldApp.swift` と, 文字だけのタイトル画面.
8. `.gitignore`(Airplane のものを写す), `docs/SETUP.md` の表に, 写したファイルが使う API を書く.

**終わりの条件**: `swift test` が通る(写した `Heightfield`・`Vector` のテストを 3 つ以上書く).
Airplane から写したファイルの一覧が「次の人へ」に書いてある.

**次の人へ**(M0 完了):

- Swift 6.4.2 を `/opt/swift/swift-6.4.2-RELEASE-ubuntu24.04/usr/bin` に入れた(新しいセッションでは無いかもしれない.
  `swift --version` で確かめ, 無ければ `https://download.swift.org/swift-6.4.2-release/ubuntu2404/swift-6.4.2-RELEASE/swift-6.4.2-RELEASE-ubuntu24.04.tar.gz` を `/opt/swift` に展開する).
- Airplane から写したもの:
  - Core: `Math/Vector.swift`, `Math/Noise.swift`, `World/Heightfield.swift` はそのまま. `World/TerrainMesher.swift` は **四角い区画用に書き直した**
    (`chunk(hf, xMin:xMax:zMin:zMax:, image:, splitRock:, uv:)`. `image` = 地面の絵 1 枚が覆う範囲. 川・遠景は消した).
    `PropInstance` は `World/PropInstance.swift` へ.
  - Rendering: `AssetLibrary.swift`, `PostProcess/{Fog.metal,PostProcessor.swift}` はそのまま. `Materials.swift` は地面・崖・水・小物・空・重ねる板だけ残し,
    `glow`(色だけの光る面)と `character`(人形の部品)を足した.
  - Features/Services: `Theme.swift`, `GameView.swift`(まだ `FlightController` を参照している → **M3 で書き直す**), `SoundEngine.swift`(Airplane の音のまま → M6 で作りかえる)
  - Resources: 小物 USDZ 14 個(木・岩・家・山小屋・丸太・石のアーチ・草)と `SkyDome.usdz`, 色見本 `PropAtlas.png`, 空 `Sky_island.png`(Airplane の谷の空のコピー), `Rock_valley.jpg`, `Water_Normal.png`, `FX_*.png`.
    AppIcon は Airplane のものを仮に使っている.
- **Xcode ではまだビルドしていない.** `GameView.swift` と `SoundEngine.swift` は Airplane の他のファイルに頼っている可能性があるので,
  M3 までのあいだにビルドするときは, この 2 つをいったんターゲットから外すか直す.
- `swift test` は 9 件通る(`FoundationTests`).

---

## M1 世界と動き(Core)

**読む所**: DESIGN §3 の「座標」「World」「Player」.

- `SeededRandom`(SplitMix64), `MapData`, `ArenaWorld`(`groundHeight`・`resolveMove`・`raycast`・`arenaSpawns`),
  `PlayerInput`, `PlayerState`, `CharacterMotor`.
- テスト用に, コードで作る小さなマップ(平らな地面 + 箱 + 円柱 + 坂 + 水)を `Tests/.../TestSupport.swift` に用意する.

**終わりの条件(テスト)**:
- 平らな所を 1 秒走ると 6.0 m ± 0.1 進む. 60 fps でも 30 fps でも同じ場所に着く(固定の刻み)
- 箱に ななめにぶつかると, 止まらずに かべにそって すべる. 通りぬけない(速さ 20 m/s でも)
- ジャンプの高さが 1.1〜1.3 m. 空中でジャンプできない
- 法線の y が 0.62 より小さい坂は登れない. 水(高さ -1 m より下)へ入れない
- 高さ 0.5 m の箱には乗れる. 1.0 m の箱には乗れず, 止まる
- `raycast`: 地面・箱(回したものも)・円柱に, 正しい距離(±0.1 m)で当たる. 何も無ければ `nil`
- `arenaSpawns`: 2・3・4 人で, 全員が陸の上・障害物の外・たがいに 30 m 以上

**次の人へ**(M1 完了. `swift test` 37 件):

- 追加したファイル: `Math/SeededRandom.swift`, `Match/GameRules.swift`(プレイヤーの数字だけ. 武器・円は M4 で足す),
  `World/MapData.swift`, `World/ArenaWorld.swift`, `Player/{PlayerInput,PlayerState,CharacterMotor}.swift`.
- `MapData` の JSON の決まり(DESIGN の例から変えた所): `props` は **配列形式** `[名前, 番号, x, y, z, 向き, sx, sy, sz]`(Airplane と同じ.
  たくさんあるので短く). 障害物: `box` = `p` が **中心**・`half` が半分の大きさ・`yaw` が Y まわりの回転(小物の向きと同じ約束),
  `cyl` = `p` が **底の中心**・`r`・`h`. 名所 `pois[].p` は `[x, z]`.
- `ArenaWorld`: `surfaceHeight(x:z:feetY:)`(足から段差ぶんまでの天面にだけ乗れる), `resolveMove`(半径の半分ずつ分けて動かすので薄いかべもすりぬけない),
  `raycast`, `arenaSpawns(centerX:centerZ:radius:count:fraction:angleOffset:)`(見つからなければ `nil`), `isClear`.
- 向きの約束: `yaw` 0 で -Z, 時計回りが +. 前 = (sin yaw, 0, -cos yaw), 右 = (cos yaw, 0, sin yaw). 箱の `yaw` は小物と同じ(`PropInstance` を `append` する式).
- 地上の動きは入力にすぐ追いつく(加速なし). 空中は `airControl` で少しだけ. ジャンプ中の横の速さは地上の速さを引きつぐ.
- 1 m の箱は, かべに寄ってジャンプすれば乗れる(0.5 m までは歩いて乗る).
- テストの世界(`TestSupport.makeWorld`): 高さ 2 m の平地, x > 30 は海, z > 20 は急な坂. 開始位置を z > 20 に置くと坂の上になるので注意.

---

## M2 島のデータ

**読む所**: DESIGN §3 の `MapData`, §4 の「島」.

`Tools/map/build_arena.py` を書く(**numpy と Pillow だけ**. Blender は使わない). 作るもの:

| ファイル | 中身 |
|---|---|
| `Resources/Maps/island.height` | 高さ. `PPHF` 形式(Airplane の `build_courses.py` の `write_heightfield` と同じ). 257 × 257, 2 m 間隔 |
| `Resources/Maps/island.json` | `MapData` |
| `Resources/Ground/island_0〜3.jpg` | 地面の絵 2 × 2 枚(1024 px). 草・砂浜・岩・道・木の下の影 |
| `Resources/Ground/island_minimap.jpg` | ミニマップ(512 px) |

- 高さの関数: 島の形(中心から 200 m で海へ落ちる)× なだらかな丘(高さ 25 m まで. Airplane の `common.py` の `fbm` の考え方).
  名所の所は平らにならす.
- **名所 4 つ**(半径 60 m. たがいに 120 m 以上はなす): 村(家・山小屋 6 軒)/ 製材所(丸太の山・丸太)/ 岩場(岩・石のアーチ)/ 森の広場(木がまばら).
  それぞれ, かくれる物が 8 個以上・ひろうものの置き場が 6 か所以上(DESIGN の `MapData` の下の注意).
- 小物の当たり判定の大きさ: USDZ の大きさを測って `Tools/map/prop_sizes.json` に書き出す(`pip install usd-core` で
  `pxr` が使える. だめなら Airplane の `props.py` の数字から). 家 = 箱, 木 = 幹だけの円柱(半径 0.4 m. 葉は弾が通る), 岩 = 円柱.
- 道: 名所どうしを結ぶ, 土の色の線(絵だけ).

**終わりの条件**: スクリプトが 1 分以内に終わり, 同じ種(seed)で同じ結果. テストで, `island.json` と `island.height` が読め,
出発点 16 か所・置き場が全部 陸の上・障害物の外. 4 つの名所で `arenaSpawns(count: 4)` が成功. ミニマップの絵をユーザーに見せる.

**次の人へ**(M2 完了. `swift test` 45 件):

- `python3 -I Tools/map/build_arena.py`(約 20 秒. numpy と Pillow だけ. 種 `SEED` が同じなら出力は完全に同じ. `--check` で今あるファイルの確かめだけ).
  `Tools/map/measure_props.py`(`pip install usd-core`)は小物の USDZ の大きさを測る道具. 結果は `prop_sizes.json`(当たり判定の数字を決めるのに使った).
- できた島: 半径 約 195 m, 高さ -7〜13.8 m(陸は 41%), 小物 1265 個(木・茂み・岩・草・家・山小屋・丸太・石のアーチ), 当たり判定 423 個,
  出発点 16, ひろうもの 44, 名所 4(村 (-80,40) / 製材所 (70,60) / 岩場 (80,-70) / 森の広場 (-50,-90). 半径 60 m).
- **絵の約束**: `Ground/island_0..3.jpg` は 1 枚 256 m 四方(0 = 西北, 1 = 東北, 2 = 西南, 3 = 東南. 絵の上が z の大きい方).
  `TerrainMesher.chunk` の `image: ImageRect` に, 区画が属する絵の範囲を渡す(例: 絵 0 = xMin -256, xMax 0, zMin 0, zMax 256).
  `island_minimap.jpg` は 512 px で **上が -Z(前)**, 右が +X, 1 px = 1 m(ほかと上下が逆なので注意).
- 当たり判定は木 = 幹の円柱(葉は通る), 家・山小屋・丸太・丸太の山 = 箱, 岩 = 円柱, 石のアーチ = 足の箱 2 つ. 茂みと草は無し.
- 確かめ(`IslandTests`): 出発点・置き場が陸の上で固いものから離れている / 4 つの名所で 2〜4 人の `arenaSpawns` が通る /
  バトルロイヤル小(半径 90・120 m)の出発点が島のあちこちで通る / 各名所にかくれる物 8 個以上・ひろうもの 6 か所以上.
- **まだ弱い所**: 名所の中心から見通せない割合は 20〜28%(目標の「半分くらい」より低い). 実機で遊んで広すぎると感じたら,
  `place_all` の家・岩・丸太の数を増やす(スクリプトの数字を変えて作り直すだけ).
- 島の絵は, まだ実機で見ていない. 地面の絵の向き(UV の上下)は `AssetLibrary.detectUVOrigin` が起動時に判定する.
- **作業の順番を変えた**: 次は M3 ではなく **M4 → M5 → M6 の Core 部分**(テストできる所)を先に進め, Apple の部品(RealityKit / SwiftUI / GameKit)を使う層は
  まとめて後で書く. 理由: Linux では Core しかコンパイル・テストできず, Core がそろってから描画をつなぐ方が, ユーザーの実機確認の回数が少なくて済むため.

---

## M3 描画と操作(★ 実機 1 回目)

**読む所**: DESIGN §3「Camera」「Input」, §4 全部. Airplane の `SceneDirector.swift`・`CourseScene.swift`(最初の 300 行)・`GameScreen.swift`.

- Core: `ThirdPersonCamera`, `TouchLayout`(テストを書く: 2 本の指を同時に追える. 指をはなすとスティックが 0 に戻る.
  かべの手前でカメラが寄る).
- Rendering: `SceneDirector`, `ArenaScene`(地形 16 区画・小物のまとめ・海・空), `CharacterRig`(箱の人形. 歩きの動き).
- Features: `GameScreen`(`GameView` + `TouchControlsView` + 仮の HUD). タイトルの「れんしゅう」で島に入れる.
- Game: `BattleController`(入力 → `CharacterMotor` → カメラ → 描画. まだ 1 人).

**終わりの条件**: `swift test` が通る. `docs/SETUP.md` の表に, 使った API が全部ある.
**ユーザーに頼む**: SETUP §1 のとおりにビルド. 出たエラーを貼ってもらい, 直す. 確かめること: 島が見える・絵の向きが合っている・
歩ける・ジャンプできる・家を通りぬけない・視点が指についてくる・60 fps 出ているか.

**次の人へ**:

---

## M4 戦いとルール(Core)

**読む所**: DESIGN §1 全部(とくにラウンド戦), §3「Combat」「Match」. NETCODE §4・§5(メッセージの名前と, ホストの確かめ方).

- `WeaponSpec`, `Loadout`, `Hitscan`(2 段階の線. 人のカプセルと頭の球), `GameRules`(数字), `GameMode`(まずラウンド戦だけ),
  `Zone`, `Loot`, `MatchState`, `MatchEvent`, `HostLogic`.
- メッセージは, この段階では **Swift の値(`enum Message`)のまま** 受けわたす(バイト列にするのは M5).

**終わりの条件(テスト)**:
- 武器の表の数字どおり: 連射の間隔, 弾倉が空で撃てない, リロードの時間, 距離でのダメージ(境目の値), 頭の倍率
- 線が, 手前の箱で止まる(かべごしに当たらない). 頭と体の当たりの区別. 自分には当たらない
- シールドから減り, 残りが HP から減る. 円のダメージはシールドを通りぬける
- ホストは, 正しい申し出を通し, おかしい申し出(遠すぎ・速すぎ・やられた人)を通さない
- ラウンド戦を, 入力を台本で与えて最後まで: 3 点先取で `final`. 武器の組が全員同じ・続けて同じにならない.
  同時にやられたら点が入らない. ひろうものは早い者勝ち. 円が表のとおりにせばまる

**次の人へ**(M4 完了. `swift test` 95 件):

- ファイル: `Combat/{WeaponSpec,Loadout,Hitscan}.swift`, `Match/{GameMode,Zone,Loot,Message,MatchEvent,MatchState,HostLogic}.swift`.
- **3 つのルールを全部実装した**(順番を前倒し. M9 の「ルールを増やす」は, 画面からえらべるようにする作業だけが残る).
  数字はすべて `GameMode.make(kind:playerCount:)` と `WeaponSpec.all` にある(設計書の表と同じ).
- **道は 1 本**: `HostLogic` は試合の状態を持たず, 渡された `MatchState` を読んでメッセージを返す. 返ったメッセージを
  自分の `MatchState.apply` に当てて全員へ送る(`MatchHarness`(テスト)と `NetSession.broadcast` がそうしている).
- 申し出の確かめ(`processClaim`): 試合中・どちらも生きている・無敵でない・武器がホストの見た武器と同じ・連射の間隔 × 0.7 以上・
  距離が届く範囲 × 1.1 以内・ホストの知っている距離と 5 m 以内・同じ `shotId` を 2 度通さない・送り主 = 撃った人.
- 円のダメージ(1 秒ごと)は **全員に当ててから** 勝ち負けを決める(同時にやられたら, だれにも点は入らない).
- 当たり判定の体: カプセル(半径 0.35, 足もと +0.35〜+1.05)+ 頭の球(半径 0.25, +1.62). DESIGN の数字を直した.
- ラウンド戦の場所は `pois[round % 4]`(村 → 製材所 → 岩場 → 森の広場). キル勝負は `pois[(matchId + round) % 4]`.
- クライアント側でやること(M6 の画面): 自分の `Loadout` は `loadoutSet` で作る(`GameMode.weapons(forSet:)`), 武器ひろいは `.lootTaken` の自分の slot
  を見て `Loadout.pickUp`, キル勝負で `.respawned` の自分の slot のとき `Loadout.reset`. 撃った結果は `Hitscan.fire` → `hitClaim`.

---

## M5 通信(Core)

**読む所**: NETCODE 全部.

- `ByteCoding`, `Messages`(全部の種類の読み書き), `Transport`(`MatchTransport`・`LoopbackTransport`),
  `ClockSync`, `InterpolationBuffer`, `NetSession`, テスト用の `SimulatedNetwork`.
- M4 の `HostLogic`・`MatchState` を `NetSession` の中につなぐ.

**終わりの条件**: NETCODE §11 の表のテストが, `HostMigrationTests` を除いて全部通る(引きつぎは M8).

**次の人へ**(M5 完了. `swift test` 129 件. **M8 の Core 部分(ホストの引きつぎ)も入っている**):

- ファイル: `Net/{ByteCoding,Messages,Transport,ClockSync,InterpolationBuffer,NetSession}.swift`. メッセージは NETCODE §4 の形(`playerState` は 22 バイト).
  `MessageCodec.decode` は短い・余る・知らない種類・範囲外の数字をすべて `nil`(でたらめなデータ 2 万個でも落ちない).
- `NetSession` の使い方(M6・M7 でつなぐ側が呼ぶ): `begin(peers:now:)` → `receive(_:from:now:)` / `peerChanged(_:connected:now:)` / `tick(now:local:)` →
  どれも `[Outgoing]` を返すので `MatchTransport.send` へ. ホストは `startMatch(kind:bots:now:)`(「もう一度」も同じ). 自分の行動は `send(_:now:)`
  (`hitClaim`・`pickupRequest` はホストへ, `shotFx` は全員へ). 画面は `match`・`drainEvents()`・`drainShots()`・`remotePose(slot:now:)` を読む.
  **`now` は「自分の端末の時計(秒. 起動してからの経過時間など 0 以上の単調な値)」**.
- **ホストも, 送った内容を「読み直した形(cm・ms に丸めたもの)」で自分に反映する**(`broadcast`). こうしないと端末ごとに写しが 1 cm 未満ずれる.
- `leave`: ホストは本人から来たものを元に `playerLeft`(やられた扱い + ぬけた)を出す. ホスト以外は **ホストが知らせたものだけ** 反映する.
- ホストの引きつぎ(`migrateHost`): 切れたのがホストなら, 残った人の peerKey 最小が新ホスト(全員が同じ計算). `hostEpoch` を 1 増やし,
  新ホストは `HostLogic.adopt` で続き(ラウンドのあいだなら次のラウンドも始める)・古いホストをぬけた扱い・スナップショットを送る.
  新ホストの時計は 今のずれのまま固定され, ほかの人は ping を撃ち直して合わせる. テスト: 4 台でホストを切っても円・勝ち負け・次のラウンドが続く.
- テスト用の `Cluster`(`Tests/BattleCoreTests/Cluster.swift`)が, 遅れ 50〜150 ms・抜け(信頼なしだけ)・順番の入れかわり・時計のずれを再現する.
- 時計合わせの誤差は 20 ms 以内(`ClockSyncTests`), 同時スタートは ±50 ms 以内(`NetSessionTests`)を確かめた.
- **まだ無いもの**: ボット(`NetSession.submitBot` の口だけある → M6 の `BotBrain`), `GameKitTransport`(M7).

---

## M6 ボットと「れんしゅう」(★ 実機 2 回目)

**読む所**: DESIGN §3「Bots」, §4「新しく作る見た目」.

- Core: `BotBrain`(強さ 3 段階). テスト: ボット 4 体だけのラウンド戦が, 3 点先取まで かならず終わる(100 回. 1 試合 12 ラウンド以内).
  ボットが水・かべで止まり続けない.
- `BattleController` を `NetSession` + `LoopbackTransport` につなぐ(自分がホスト, 相手はボット 1〜3 体).
- 見た目と音: 弾の線・銃口の光・火花・ひろうもの・円の筒・やられたときの動き・観戦カメラ. `SoundEngine`(撃つ音 4 種・当たった・
  ひろった・やられた・円の警告・勝ち負け).
- 画面: HUD 全部(DESIGN §4), ラウンドのあいだの表示(だれが取ったか・点), 結果, 設定(感度・上下反対・左きき・ボットの数と強さ).

**終わりの条件**: `swift test` が通る.
**ユーザーに頼む**: 1 台で「れんしゅう」を最後まで. 確かめること: ねらいやすいか(感度), ボットが強すぎ・弱すぎないか,
1 ラウンドの長さ, 武器ごとの強さ, 音, 60 fps. 感想をもらい, `GameRules` の数字を直す(直したら DESIGN の表も).

**次の人へ**(M6 の Core 部分は完了. `swift test` 149 件. 画面・音・演出(Apple の部品)は下の「Apple の層」を参照):

- `Bots/BotRunner.swift`: ホストが全ボットを動かす. `reset(match:)`(ラウンドの始まりで自動), `update(now:dt:match:humans:) -> [Message]`
  (`playerState`・`shotFx`・`hitClaim`・`pickupRequest` を返す → `NetSession.submitBot`), `observe(events:match:now:)`(武器をひろった・生き返った).
  強さ 3 段階 `BotDifficulty.easy/normal/hard`(反応の遅れ・ねらいの誤差・振り向く速さ). 動きは人と同じ `CharacterMotor`, 当たりは `Hitscan`.
- 確かめ: ボットが島を歩く・水に落ちない・撃ち合ってダメージが入る・人が立っていれば見つけて撃つ・武器の組が合う・同じ種で同じ試合.
  **ボット 4 体のラウンド戦 100 回が すべて終わった(平均 5.9 ラウンド・最大 10 ≤ 12)**: `BOT_STRESS=100 swift test --filter testFourBotRoundBattlesAlwaysFinish`.
- `Camera/ThirdPersonCamera.swift`(肩ごし. かべで手前へ寄る・構えると近づく・スナイパーは画角 15°), `Input/TouchLayout.swift`(指を 1 本ずつ追う:
  左 = 移動スティック, 右 = 視点, ボタン. 撃ちながら視点. 左きき・上下反対)を作った. どちらも テストあり.
- `BotMatch`(テスト): ホスト + ボットだけで試合を動かす道具.

---

## M7 Game Center(★ 実機 3 回目. 2 台いる)

**読む所**: NETCODE §3・§10. SETUP §2・§3. **Apple の公式ドキュメントで, 使う API の今の形を確かめてから書く.**

- `GameCenterAuth`, `Matchmaking`, `GameKitTransport`.
- 画面: タイトルの「オンライン対戦」(ログインできていないときは理由を出して押せなくする), ロビー(名前の一覧・ホストの印・
  ルールえらび・「はじめる」・「ぬける」), 招待を受けたときに そのままロビーへ.
- 画面の下に, 通信のようす(往復の時間 ms・ホストかどうか)を小さく出す切りかえを, 設定に入れる(確かめるため).

**終わりの条件**: `swift test` が通る(Core は変えないのが理想). SETUP の表に GameKit の API が全部ある.
**ユーザーに頼む**: SETUP §2(App Store Connect)→ §3(2 台で試す). 確かめること: 2 台とも同じ人をホストと言う・同じ瞬間に始まる・
相手が なめらかに動く・撃つと相手の HP が減る・ラウンドと点が 2 台で同じ・「もう一度」ができる.
**「通信のようす」に出る「Game Center の人数の上限」の数字を教えてもらい, DESIGN §0 の「人数」の行に書く**(4 でも 8 より大きくても, 作りは変えなくてよい).

**次の人へ**:

---

## M8 切れたときの強さ(★ 実機 4 回目)

**読む所**: NETCODE §8・§9.

- ホストの引きつぎ(`HostMigrationTests` を通す), 切れた人の処理, アプリを閉じたとき, 版が違うとき, おくれて来た `hello`.
- 3〜4 台(または 2 台 + ボット)で: ホストがアプリを消す → 残りで続く.

**次の人へ**:

---

## M9 ルールを増やす

- `GameMode` にキル勝負とバトルロイヤルを足す(`respawn`・`lootRestored`・円 5 段階・武器をひろう).
  バトルロイヤルは **2〜4 人の小さい版を先に** 作る(DESIGN「安全地帯」の下の表. 2 台で確かめられる). 5〜16 人の島全体の版は, その数字ちがい.
  `GameModeTests`(2・3・4・8・16 人で: 始めの円が陸に おさまる・置き場が足りる・出発点がたがいに 30 m 以上・約 3 分 / 約 4〜5 分で終わる). ロビーでえらべるようにする.
- **ルールごとの `if` を `HostLogic` に散らさない.** 足りない数字は `GameMode` に足す.

**次の人へ**:

---

## M10 みがき(順番は, ユーザーと相談)

- **落ちている武器の見た目**(ユーザーの希望. 今は色つきの箱): 武器 4 種と 回復・シールドの 小さなモデルを Blender のスクリプトで作り,
  `ArenaScene.setLoot` の箱と差しかえる. 手に持つ武器(`CharacterRig.setWeapon`)も 同じモデルを使う
- Blender のスクリプトで新しい小物(木箱・かべ・土のう・やぐら), 武器のモデル, キャラクターの部品
  (Airplane の `Tools/blender/props.py`・`common.py`・`build_carpet.py` を写して使う. じゅうたんの帯と同じく, 部品ごとに名前を付けて書き出す)
- 島をもう 1 つ / 名所を増やす
- バトルロイヤルの始まりを, 空から魔法のじゅうたんで降りる形に(Airplane の `FlightModel` を使う)
- ゲームコントローラー(`GCController`), ねらいの助け(敵の近くで視点を少しおそく), 自動で撃つ設定
- Game Center のランキング(勝った数)と実績
- 3 人以上のときの 2 対 2 のチーム戦
