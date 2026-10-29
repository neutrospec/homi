// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "hangul",
    platforms: [.macOS(.v27)],
    targets: [
        // 두벌식 조합 엔진 — AppKit·IMK 를 모른다. 규칙은 docs/spec.md
        .target(name: "HangulCore"),
        .testTarget(name: "HangulCoreTests", dependencies: ["HangulCore"]),
        // key → client 호출. 역시 AppKit·IMK 를 모른다 — fake client 로 test 한다.
        .target(name: "InputSession", dependencies: ["HangulCore"]),
        .testTarget(name: "InputSessionTests", dependencies: ["InputSession", "HangulCore"]),
        // 입력기 app. Bundle/ 은 Info.plist·resource — scripts/app.sh 가 bundle 에 넣는다.
        .executableTarget(
            name: "homi",
            dependencies: ["InputSession", "HangulCore"],
            path: "Sources/homi",
            exclude: ["Bundle"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "HomiTests", dependencies: ["homi"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .executableTarget(name: "replace-app", path: "tools/replace-app"),
        .testTarget(name: "InstallTests", dependencies: ["replace-app"]),
        // 개발 도구 — 제품이 아니다 (tools/)
        .executableTarget(name: "caps-probe", path: "tools/caps-probe"),
        .executableTarget(
            name: "tis",
            path: "tools/tis",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .executableTarget(
            name: "probe",
            dependencies: ["InputSession"],
            path: "tools/probe",
            exclude: ["Info.plist", "browser.html", "browser-trace.js"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
