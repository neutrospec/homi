// homi — macOS 한글 입력기.
//
// 입력기는 system(imklaunchagent)이 띄우는 background app 이다. IMKServer 를 열어 두면
// app 들이 Info.plist 의 InputMethodConnectionName 으로 이 process 를 찾아오고,
// IMK 가 입력칸(client) session 마다 HomiInputController 를 하나씩 만든다.

import AppKit
import InputMethodKit

@main
enum HomiApp {
    static func main() {
        let executableUUID = BinaryIdentity.current
        let processID = ControllerTraceID.process
        // 앱 객체가 먼저 있어야 한다 — 없을 때 만든 menu bar 표시(NSStatusItem)는 조용히 생기지 않는다 (2026-09-25).
        let app = NSApplication.shared
        guard let connection = Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String,
            let server = IMKServer(name: connection, bundleIdentifier: Bundle.main.bundleIdentifier)
        else {
            fatalError("cannot create IMKServer — is homi running from its app bundle?")
        }
        log.info("started, executable UUID: \(executableUUID, privacy: .public), process: \(processID, privacy: .public)")
        ModifierActivityObserver.shared.start()
        // 첫 renderer 판별(commitComposition 안)의 cold 비용은 directory 읽기(~1ms)가 아니라 NSWorkspace 의 실행 app 목록 첫 구성(5–9ms)이었다.
        // 시작 때 한 번 미리 만들어 둔다 — 판별 시점·정책은 그대로다 (docs/stability-review.md 후속 4번, 2026-11-03).
        _ = NSWorkspace.shared.runningApplications
        let watcher = SourceWatcher()
        withExtendedLifetime((server, watcher)) { app.run() }
    }
}
