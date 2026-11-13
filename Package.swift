// swift-tools-version:5.9
//
// ゲームの「頭脳」(Battlefield/Core: 世界・動き・戦い・ルール・通信の中身)だけを
// 取り出してテストするためのパッケージ. 描画(RealityKit)・画面(SwiftUI)・GameKit は
// 含まないので, Mac でも Linux でも `swift test` で確かめられる.
//
// アプリ本体は Battlefield.xcodeproj で開く(同じ Core のファイルをそのまま使う).
import PackageDescription

let package = Package(
    name: "BattleCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "BattleCore", targets: ["BattleCore"]),
    ],
    targets: [
        .target(name: "BattleCore", path: "Battlefield/Core"),
        .testTarget(name: "BattleCoreTests", dependencies: ["BattleCore"], path: "Tests/BattleCoreTests"),
    ]
)
