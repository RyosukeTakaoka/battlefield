# battlefield(仮の名前)

iPad / iPhone 用の **3D 対戦シューティング**. Game Center のリアルタイム対戦(GameKit の `GKMatch`)で,
友だちと同じ島で撃ち合います. 3D の作り方は [Airplane(石油王の旅)](https://github.com/RyosukeTakaoka/Airplane) と同じです.

**今の状態**: ルール・通信・ボット・カメラ・入力などの「頭脳」(`Battlefield/Core/`)は書き終わり, Linux で **150 件のテストが通っています**
(ボット 4 体のラウンド戦 100 回が すべて 12 ラウンド以内に終わる, ホストが切れても続く, など).
画面・3D の描画・Game Center をつなぐ層も書きましたが, **まだ Mac で一度もビルドしていません**. 次は `docs/SETUP.md` の手順でビルドして, 出たエラーを AI に伝えてください.

| ルール | 人数 | ひとことで |
|---|---|---|
| **ラウンド戦**(最初に作る) | 2〜4 人 | せまい場所で, 全員同じ武器. 最後の 1 人がラウンドを取る. 先に 3 ラウンド取った人の勝ち |
| キル勝負 | 2〜4 人 | やられても 3 秒で復活. 先に 10 キル(3〜4 人なら 15 キル) |
| バトルロイヤル | 2〜8 人 | 武器をひろい, せばまる円の中で最後の 1 人をめざす. 2〜4 人のときは せまい範囲で始まる(約 3 分) |

| 技術 | 使い方 |
|---|---|
| Swift / SwiftUI | 画面(タイトル・ロビー・数字の表示・設定) |
| RealityKit | 3D の描画(ARView を AR なしで使用). 地形は高さマップから組み立てる |
| GameKit | ログイン, 人あつめ, `GKMatch` でのデータの送り合い |
| Python | 島のデータ(高さ・地面の絵・小物の置き場)を作る |

## 文書

| ファイル | 中身 |
|---|---|
| [`docs/DESIGN.md`](docs/DESIGN.md) | ルール・数字・全体の構成・Airplane から流用するもの |
| [`docs/NETCODE.md`](docs/NETCODE.md) | 通信の設計(だれが何を決めるか・メッセージの形・ホストの引きつぎ) |
| [`docs/TASKS.md`](docs/TASKS.md) | 作る順番(M0〜M10)と, 終わったと言える条件 |
| [`docs/SETUP.md`](docs/SETUP.md) | Mac と App Store Connect で人がやること |
| [`CLAUDE.md`](CLAUDE.md) | このリポジトリで作業する AI への約束 |

## AI に作業を頼むとき

新しいセッションを **battlefield と Airplane の両方のリポジトリ** を付けて始め, 次のように伝えます(数字だけ変えて, 1 つずつ):

```
battlefield リポジトリの CLAUDE.md と docs/DESIGN.md, docs/TASKS.md を読んで,
M0 を進めてください. 終わったら docs/TASKS.md にチェックと「次の人へ」を書いて, push してください.
```

★ の付いたマイルストーン(M3・M6・M7・M8)のあとは, `docs/SETUP.md` を見ながら実機で確かめ,
出たエラーや感想を, 同じセッションで AI に伝えてください.
