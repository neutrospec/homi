// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "hangul",
    platforms: [.macOS(.v27)],
    targets: [
        // 입력기 app. Bundle/ 은 Info.plist·resource — scripts/app.sh 가 bundle 에 넣는다.
        .executableTarget(
            name: "homi",
            path: "Sources/homi",
            exclude: ["Bundle"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        // 개발 도구 — 제품이 아니다 (tools/)
        .executableTarget(
            name: "tis",
            path: "tools/tis",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .executableTarget(
            name: "probe",
            path: "tools/probe",
            exclude: ["Info.plist"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
