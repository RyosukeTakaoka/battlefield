# 作業の順番

上から順に, **1 回のセッションで 1 つ** 進める. 始める前に `docs/DESIGN.md` を読み, そのマイルストーンに書いてある節を読み直すこと.
終わったら, チェックを付けて「次の人へ」を書く.

**先に動くものを作り, 通信は後で足す** 順番にしてある:
1 人で歩ける(M3)→ 1 台でボットと 1 試合できる(M6)→ 2 台で対戦できる(M7)→ ルールを増やす(M9).

| | マイルストーン | できること | 実機での確認 |
|---|---|---|---|
| ☑ | M0 土台 | フォルダとプロジェクトがあり, `swift test` が通る | |
| ☐ | M1 世界と動き(Core) | 当たり判定と, 人の動きの計算 | |
| ☐ | M2 島のデータ | 島の高さ・地面の絵・小物の置き場 | |
| ☐ | M3 描画と操作 | **1 人で島を歩き回れる** | ★ 1 回目 |
| ☐ | M4 戦いとルール(Core) | 武器・当たり・ダメージ・ラウンド戦のルール | |
| ☐ | M5 通信(Core) | メッセージ・ホスト・時計・補間(にせの通信でテスト) | |
| ☐ | M6 ボットと「れんしゅう」 | **1 台で, ボットとラウンド戦を最後まで遊べる** | ★ 2 回目 |
| ☐ | M7 Game Center | **2 台で対戦できる** | ★ 3 回目(2 台) |
| ☐ | M8 切れたときの強さ | ホストがぬけても続く. とちゅうでやめても こわれない | ★ 4 回目 |
| ☐ | M9 ルールを増やす | キル勝負, バトルロイヤル | ★ |
| ☐ | M10 みがき | 新しい小物・キャラクター, コントローラー, ランキング など | ★ |

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

**次の人へ**:

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

**次の人へ**:

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

**次の人へ**:

---

## M5 通信(Core)

**読む所**: NETCODE 全部.

- `ByteCoding`, `Messages`(全部の種類の読み書き), `Transport`(`MatchTransport`・`LoopbackTransport`),
  `ClockSync`, `InterpolationBuffer`, `NetSession`, テスト用の `SimulatedNetwork`.
- M4 の `HostLogic`・`MatchState` を `NetSession` の中につなぐ.

**終わりの条件**: NETCODE §11 の表のテストが, `HostMigrationTests` を除いて全部通る(引きつぎは M8).

**次の人へ**:

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

**次の人へ**:

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
  バトルロイヤルは **2〜4 人の小さい版を先に** 作る(DESIGN「安全地帯」の下の表. 2 台で確かめられる). 5〜8 人の島全体の版は, その数字ちがい.
  `GameModeTests`(2・3・4・8 人で: 始めの円が陸に おさまる・置き場が足りる・出発点がたがいに 30 m 以上・約 3 分 / 約 4〜5 分で終わる). ロビーでえらべるようにする.
- **ルールごとの `if` を `HostLogic` に散らさない.** 足りない数字は `GameMode` に足す.

**次の人へ**:

---

## M10 みがき(順番は, ユーザーと相談)

- Blender のスクリプトで新しい小物(木箱・かべ・土のう・やぐら), 武器のモデル, キャラクターの部品
  (Airplane の `Tools/blender/props.py`・`common.py`・`build_carpet.py` を写して使う. じゅうたんの帯と同じく, 部品ごとに名前を付けて書き出す)
- 島をもう 1 つ / 名所を増やす
- バトルロイヤルの始まりを, 空から魔法のじゅうたんで降りる形に(Airplane の `FlightModel` を使う)
- ゲームコントローラー(`GCController`), ねらいの助け(敵の近くで視点を少しおそく), 自動で撃つ設定
- Game Center のランキング(勝った数)と実績
- 3 人以上のときの 2 対 2 のチーム戦
