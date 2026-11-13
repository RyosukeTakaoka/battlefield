# 通信の設計(Game Center のリアルタイム対戦)

`GKMatch` は「参加者どうしで `Data` を送り合える」だけの仕組み. サーバーも, 部屋の主も, 時計も無い.
だから, **だれが何を決めるか** と **メッセージの形** を自分たちで決める. それがこの文書.

> GameKit の API の名前は, かならず Apple の公式ドキュメントで確かめてから書くこと(版で変わる).
> ここに書いた名前は「このあたりを使う」という道しるべ.

## 1. 方式

| こと | だれが決めるか | 送り方 |
|---|---|---|
| 自分の位置・向き | 自分の端末 | 信頼なし. 1 秒に 20 回, 全員へ |
| 撃った線(見た目) | 撃った人 | 信頼なし. 全員へ |
| 当たったか | 撃った人の端末が調べて, ホストへ申し出る(`hitClaim`) | 信頼あり. ホストへ |
| ダメージ・やられた・順位 | **ホスト** | 信頼あり. 全員へ |
| ひろうもの | ひろいたい人が申し出て, **ホスト** が早い者勝ちで決める | 信頼あり |
| 円(安全地帯) | ラウンドの開始のときにホストが全部決める. あとは時計だけ | (開始のメッセージに入れる) |
| ボット | **ホスト** が動かし, 人と同じ形で位置を送る | 信頼なし |

- 撃った人の画面で当たっていれば当たり(**撃った人に有利**). 相手は 0.1 秒前の姿で見えているので, これで
  「ねらったのに当たらない」が起きない. かわりに「かくれたのに当たった」が少し起きる. 友だち同士なら これでよい.
- ホストは申し出を **ゆるく** 確かめる(§5). ズルを完全に防ぐことは目指さない.

## 2. 部品(全部 Core. テストできる)

```swift
/// 送る・受ける だけの口. 中身は知らない.
protocol MatchTransport: AnyObject {
    var peers: [PeerHandle] { get }                     // つながっている相手(自分は入らない)
    func send(_ data: Data, to: [PeerHandle]?, reliable: Bool)   // nil = 全員
    var onReceive: ((Data, PeerHandle) -> Void)? { get set }
    var onPeerChange: ((PeerHandle, Bool) -> Void)? { get set }  // つながった / 切れた
    func disconnect()
}
typealias PeerHandle = Int      // その端末の中だけの番号(GameKitTransport が GKPlayer と対応させる)
```

- `GameKitTransport`(Services. 本番): `GKMatch` を包むだけ. **ルールを 1 行も書かない.**
- `LoopbackTransport`(Core): 相手がいない. 「れんしゅう」用.
- `SimulatedNetwork`(テスト): 何台ぶんもの `NetSession` をつなぎ, 遅れ(50〜150 ms)・抜け(10%)・順番の入れかわり
  (信頼なしだけ)を作る. 信頼ありは, 遅れるが, 送った人ごとに順番どおり届く.

`NetSession` は **値を受けて値を返す** 形にする(テストしやすい):

```swift
struct NetSession {
    mutating func receive(_ data: Data, from: PeerHandle, now: Double)      // 届いた
    mutating func peerChanged(_ peer: PeerHandle, connected: Bool, now: Double)
    mutating func tick(now: Double, local: LocalSnapshot) -> [Outgoing]     // 送るもの
    mutating func drainEvents() -> [MatchEvent]                             // 画面・音へ
    var match: MatchState { get }                                           // 写し
    var isHost: Bool { get }
    func remotePose(slot: Int, renderTime: Double) -> RemotePose?           // 補間した相手
}
struct Outgoing { var data: Data; var to: [PeerHandle]?; var reliable: Bool }
```

## 3. つながってから始まるまで

```
1. Game Center にログイン(アプリを開いたとき)
2. 人あつめの画面(GKMatchmakerViewController. 友だち・近くの人・おまかせ)→ GKMatch がもらえる
     └ もらった瞬間に delegate を付ける(おくれると, 最初のメッセージを落とす)
3. 全員がつながるまで待つ(match.expectedPlayerCount == 0)
4. 全員が hello を送る(信頼あり): 通信の版, 自分で作った乱数の番号 peerKey(UInt64), 名前
5. 全員の hello がそろったら: peerKey がいちばん小さい人が ホスト
     (GKPlayer の ID の並べ方に頼らない. 乱数の番号なので, どの端末でも同じ答えになる)
6. 全員が ホストへ ping を送り始める(時計合わせ. §6)
7. ロビーの画面. ホストだけ「はじめる」を押せる
8. ホストが startRound を送る: ルール, 場所, slot の表と出発点, 武器の組, 円, ひろうものの中身,
     「ホストの時計で何 ms に始めるか」(最初は 5 秒後. 2 ラウンド目からは 3 秒後)
9. 全員が, 同じ瞬間に始める
10. ラウンドが終わったら ホストが roundEnd → (ラウンド戦で, まだ決まっていなければ)4 秒後に 次の startRound
```

- 通信の版(`protocolVersion`)が違う人がいたら, 始めずに「アプリを新しくしてください」と出す.
- **ラウンドは, 毎回 `startRound` でまるごと配り直す**(場所・出発点・武器の組・ひろうもの・今の点). 前のラウンドの状態は引きつがない.
  だから, バトルロイヤルとキル勝負は「1 ラウンドだけの試合」として, 同じ道で動く.
- 「もう一度」は, 同じ `GKMatch` のまま, ホストが試合の番号を 1 増やして, ラウンド 0 の `startRound` を送るだけ.

## 4. メッセージの形

すべてリトルエンディアン. 1 バイト目が種類. `ByteWriter` / `ByteReader`(Core/Net/ByteCoding.swift)で読み書きし,
**長さが足りない・知らない種類のときは, 落ちずに捨てる**(`nil` を返す).

小さくする約束: 位置 = `Int16`(1 = 1 cm. ±327 m), yaw = `UInt16`(0〜65535 が 0〜2π), pitch = `Int8`(±127 が ±π/2),
速度 = `Int8`(1 = 0.25 m/s), 距離 = `UInt16`(1 = 10 cm), 時刻 = `UInt32`(ホストの時計の ms).

### 信頼なし(1 個 1000 バイトより小さく. 実際は 30 バイトくらい)

| 種類 | 名前 | だれ → だれ | 中身 |
|---|---|---|---|
| 0x01 | playerState | 各自(ボットはホスト)→ 全員. 20 回/秒 | slot U8, seq U16, timeMs U32, x・y・z I16×3, yaw U16, pitch I8, vx・vy・vz I8×3, flags U8, weapon U8(計 22 バイト) |
| 0x02 | shotFx | 撃った人 → 全員 | slot U8, weapon U8, origin I16×3, count U8, [end I16×3, hitKind U8] × count |
| 0x12 | ping | 各自 → ホスト. 2 秒ごと(始めの 5 回は 0.3 秒ごと) | clientMs U32 |
| 0x13 | pong | ホスト → 送ってきた人 | clientMs U32, hostMs U32 |

- `flags`: bit0 接地, bit1 撃っている, bit2 リロード中, bit3 構えている, bit4 生きている.
- `seq` が前に受けたものより古ければ捨てる(`UInt16` が一周することを考えて比べる: 差を `Int16` にして正なら新しい).
- `hitKind`: 0 何にも当たらない, 1 地面, 2 障害物, 3 人.

### 信頼あり

| 種類 | 名前 | だれ → だれ | 中身 |
|---|---|---|---|
| 0x10 | hello | 各自 → 全員 | protocol U8, peerKey U64, nameLen U8, name(UTF-8. 24 バイトまで) |
| 0x11 | startRound | ホスト → 全員 | matchId U32, round U8, mode U8(0 ラウンド戦 / 1 キル勝負 / 2 バトルロイヤル), mapId U8, startAtHostMs U32, arena [cx I16, cz I16, r U16(10 cm)], loadoutSet U8(0 = ハンドガンだけで開始), 人数 U8, [slot U8, peerKey U64(ボットは 0), isBot U8, score U8, spawn x・y・z I16×3, spawnYaw U16, nameLen U8, name] × 人数, 円の数 U8, [cx I16, cz I16, r U16(10 cm)] × 数, ひろうものの数 U8, [lootId U8, kind U8] × 数 |
| 0x20 | hitClaim | 撃った人 → ホスト | shotId U16, attacker U8, target U8, weapon U8, zone U8(0 体 / 1 頭), pellets U8, distance U16 |
| 0x21 | damage | ホスト → 全員 | target U8, attacker U8(255 = 円, 254 = 切断), weapon U8, hp U8, shield U8, flags U8(bit0 やられた, bit1 頭), alive U8 |
| 0x22 | vitals | ホスト → 全員 | slot U8, hp U8, shield U8(回復のとき) |
| 0x23 | respawn | ホスト → 全員(キル勝負だけ) | slot U8, x・y・z I16×3, yaw U16, atHostMs U32(この時刻に, HP 100・ハンドガンで生き返る. そこから 2 秒は無敵) |
| 0x30 | pickupRequest | ひろう人 → ホスト | lootId U8, slot U8 |
| 0x31 | lootTaken | ホスト → 全員 | lootId U8, slot U8 |
| 0x32 | lootRestored | ホスト → 全員(キル勝負だけ) | lootId U8, kind U8(取られて 20 秒後に, また出す) |
| 0x40 | roundEnd | ホスト → 全員 | matchId U32, round U8, winner U8(255 = なし), final U8(1 = これで試合も終わり), 人数 U8, [placement U8, kills U8, score U8] × 人数 |
| 0x41 | hostSnapshot | ホスト → 全員. 2 秒ごと + ホストが替わった直後 | matchId U32, round U8, hostEpoch U8, phase U8, 人数 U8, [hp U8, shield U8, kills U8, placement U8(0 = 生きている), score U8] × 人数, ひろうものの取られた印(ビット列) |
| 0x50 | leave | やめる人 → 全員 | slot U8 |

大事な約束:

- ホストからのメッセージには **「いくつ減ったか」ではなく「今いくつか」** を入れる(`damage` の hp・shield). 同じものが 2 回届いても,
  順番が少し前後しても, こわれない.
- `damage` で やられた人の順位は `alive + 1`(`alive` = そのあと生きている人数).
- ホストだけが出してよい種類(0x11, 0x21, 0x22, 0x23, 0x31, 0x32, 0x40, 0x41)を, **今のホスト以外** から受け取ったら捨てる.
- `matchId` と `round` が今のものと違う `damage` などは捨てる(前のラウンドの おくれて届いたものを まぜない).
  そのため 0x21・0x22・0x23・0x31・0x32 の先頭にも `round U8` を 1 バイト入れる(表では省いた).
- 自分の HP は, 自分で減らさない. ホストの `damage` を待つ(画面のヒットの印だけは, 先に出してよい).

## 5. ホストの仕事(`HostLogic`)

**`hitClaim` を受けたら**(全部 通ったら `damage` を出す):
1. 撃った人も 撃たれた人も 生きている. 自分自身ではない
2. 武器が, その人の最新の `playerState.weapon` と同じ
3. 連射が速すぎない(前の申し出から, その武器の間隔 × 0.7 より あいている. ショットガンは 1 発 = 1 つの申し出で `pellets` 1〜8)
4. `distance` が届く距離 × 1.1 より近く, ホストが知っている 2 人の距離と 5 m より大きくは ずれていない
5. ダメージ = `WeaponSpec.damage(distance, head) × pellets`. シールドから減らし, 残りを HP から

**`pickupRequest` を受けたら**: まだ取られていない・その人が生きている・置き場から 4 m 以内 → `lootTaken`.
回復なら `vitals` も出す. 武器の入れかえは, ひろった人の端末が `lootTaken`(自分の slot)を見てから自分でやる.

**1 秒ごと**: 円の外にいる人(最新の位置で見る)に, 円のダメージの `damage`(attacker = 255. シールドは通りぬける).

**いつも**: ボットを進める. 2 秒ごとに `hostSnapshot`. ルール(`GameMode`)に合わせて, 終わりを見る:

| ルール | ラウンドの終わり | そのあと |
|---|---|---|
| ラウンド戦 | 生きている人が 1 人以下 | 勝った人の `score` を 1 増やして `roundEnd`. だれかが 3 点(または 12 ラウンド)なら `final = 1`. そうでなければ 4 秒後に, 次の名所・次の武器の組で `startRound` |
| キル勝負 | だれかが目標のキル数 / 5 分たった(同じ数なら, 次の 1 キルまで続ける) | `roundEnd`(`final = 1`). やられた人には 3 秒後の時刻で `respawn`, 取られた物には 20 秒後に `lootRestored` |
| バトルロイヤル | 生きている人が 1 人以下 | `roundEnd`(`final = 1`) |

- キル勝負の無敵(復活して 2 秒. その人の `playerState` の「撃っている」が立ったら終わり)のあいだの `hitClaim` は通さない.

**だれかが切れたら**: その人を やられた扱いにする `damage`(attacker = 254).

## 6. 時計を合わせる(`ClockSync`)

「ホストの時計」= ホストが `NetSession` を作ってからの ms. みんなは, 自分の時計との **ずれ** を覚える.

```
ping を送る(自分の時刻 t0)→ ホストが pong(t0, ホストの時刻 h)→ 受け取る(自分の時刻 t1)
往復の時間 rtt = t1 - t0      ずれの見つもり = h + rtt/2 - t1
```

- 直近 8 回のうち, **rtt がいちばん小さい回** のずれを使う(速く届いた回がいちばん正確).
- ずれを直すときは, 1 秒かけて なめらかに(急に時刻が飛ぶと, 相手の動きがガクッとなる). 0.5 秒より大きく違うときだけ, すぐ合わせる.
- 試合の時刻 `matchTime = ホストの時計 - startAtHostMs`. 円も, カウントダウンも, これで決まる.

## 7. 相手を なめらかに見せる(`InterpolationBuffer`)

- slot ごとに, 届いた `playerState` を時刻の順に 1 秒ぶん ためる.
- 画面に出すのは **「今 - 100 ms」の時刻**(送る間隔の 2 倍. 1 個抜けても つなげる). 前後の 2 つを時刻の割合でまっすぐ補間.
  yaw は近い回り方で補間する(359° → 1° を 逆に回らない).
- 新しいものが来ない(バッファの先に出た)ときは, 最後の速度で 250 ms まで先へのばし, それより長いときは止める.
- 5 m より大きく飛んだら(やり直し・通信の乱れ), 補間せずに その場所へ移す.
- 当たり判定に使う相手の位置は, **この補間した位置**(画面に見えている姿と同じ).

## 8. ホストが切れたとき(引きつぎ)

全員が `MatchState` の写しを持っているので, 引きつぎは簡単:

1. `onPeerChange(ホスト, false)` を受けたら, 残っている人の中で peerKey がいちばん小さい人が新しいホスト
   (全員が同じ計算をするので, 相談はいらない).
2. 新しいホストは `hostEpoch` を 1 増やし, すぐ `hostSnapshot` を送る. 自分の「ホストの時計の見つもり」を, そのまま本物の時計にする.
3. ほかの人は, 新しいホストへ ping を送り直して, 時計を合わせ直す.
4. 前のホストが動かしていたボットは, 最後に届いた位置から, 新しいホストが動かす.
5. 前のホストは, やられた扱い(切断)にする.

引きつぎの前後で `hitClaim` が 1〜2 個 消えることがある. それは受け入れる(撃ち直せばよい).

## 9. 切れたとき・閉じたとき

| 出来事 | どうするか |
|---|---|
| 相手が切れた | ホストが やられた扱いにする. 画面に「○○ が ぬけました」 |
| 自分だけになった | 勝ち(ホストの処理が そう決める) |
| `match(_:didFailWithError:)`, 全員と切れた | 「通信が切れました」→ タイトルへ |
| アプリを閉じた(バックグラウンド) | `leave` を送って `disconnect()`. 開き直したらタイトル(v1 では, 試合に戻らない) |
| 試合中に来た `hello`(おくれて入った人) | v1 では入れない. その人は次の試合から |

## 10. GameKit の使い方(`Services/GameCenter/`)

| ファイル | やること | 使う API(公式ドキュメントで確かめる) |
|---|---|---|
| `GameCenterAuth` | アプリを開いたらログイン. できない・制限されているときは「オンライン対戦」を押せなくする | `GKLocalPlayer.local.authenticateHandler`, `isAuthenticated`, `isMultiplayerGamingRestricted`, `GKAccessPoint` |
| `Matchmaking` | 人あつめの画面を出す. 招待を受ける | `GKMatchRequest`(`minPlayers` 2, `maxPlayers` 8), `GKMatchmakerViewController`, `GKMatchmakerViewControllerDelegate`, `GKLocalPlayerListener`(`player(_:didAccept:)`), `GKMatchmaker.shared().finishMatchmaking(for:)` |
| `GameKitTransport` | `MatchTransport` の実物 | `GKMatch.delegate`, `players`, `expectedPlayerCount`, `send(_:to:dataMode:)`, `sendData(toAllPlayers:with:)`, `disconnect()`, `GKMatchDelegate` の `match(_:didReceive:fromRemotePlayer:)`・`match(_:player:didChange:)`・`match(_:didFailWithError:)` |

気をつけること:

- delegate は, どのスレッドで呼ばれるか決まっていないと考える. かならずメインへ渡してから Core にさわる.
- `GKMatch.players` に **自分は入っていない**.
- 送るのに失敗(`throws`)しても落とさない. ログに出して続ける.
- SwiftUI から UIKit の画面(`GKMatchmakerViewController`)を出すには, いちばん上の `UIViewController` を取って `present` する.
- 試合が始まったら `finishMatchmaking(for:)` を呼ぶ(おまかせで, 途中から人が入ってこないように).

## 11. テスト(`Tests/BattleCoreTests/`. 全部 Linux で動く)

| テスト | 確かめること |
|---|---|
| `MessagesTests` | 全部の種類が「書く → 読む」で元に戻る. 途中で切れた・でたらめな `Data` で落ちない. `playerState` が 22 バイト |
| `ClockSyncTests` | 遅れが ばらつく通信で, ずれの見つもりが 20 ms 以内に入る |
| `InterpolationTests` | まっすぐ歩く相手が なめらか. 1 個抜けても つながる. 順番が入れかわっても戻らない. yaw が 0 をまたぐ |
| `HostLogicTests` | 正しい申し出は通る. 遠すぎる・速すぎる・やられた人の申し出は通らない. シールドから減る. 早い者勝ち |
| `NetSessionTests` | `SimulatedNetwork` で 2 台・4 台: 全員が同じホストをえらぶ. 同じ瞬間に始まる(±50 ms). ラウンド戦を 3 点先取まで進め, 全員の `MatchState` が同じ・勝者が同じ. ラウンドをまたいで前のラウンドのメッセージが まざらない |
| `GameModeTests` | 3 つのルールそれぞれ: 出発点が人数ぶん・陸の上・たがいに 30 m 以上はなれている. ラウンド戦は全員同じ武器の組で, 続けて同じ組が出ない. キル勝負は復活して 2 秒 無敵・目標のキル数で終わる |
| `HostMigrationTests` | 試合中にホストを切る → 残りが同じ新ホストをえらび, 円のダメージと勝敗が続く |
| `LossTests` | 信頼なしが 30% 抜けても, 試合が最後まで進む |
