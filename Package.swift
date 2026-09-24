// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "hangul",
    platforms: [.macOS(.v27)],
    targets: [
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
