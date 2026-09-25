// homi — macOS 한글 입력기.
//
// 입력기는 system(imklaunchagent)이 띄우는 background app 이다. IMKServer 를 열어 두면
// app 들이 Info.plist 의 InputMethodConnectionName 으로 이 process 를 찾아오고,
// IMK 가 입력칸(client) session 마다 HomiInputController 를 하나씩 만든다.

import AppKit
import InputMethodKit

guard let connection = Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String,
    let server = IMKServer(name: connection, bundleIdentifier: Bundle.main.bundleIdentifier)
else {
    fatalError("cannot create IMKServer — is homi running from its app bundle?")
}

log.info("started")
let watcher = SourceWatcher()
withExtendedLifetime((server, watcher)) {
    NSApplication.shared.run()
}
