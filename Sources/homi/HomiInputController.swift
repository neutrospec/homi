import AppKit
import InputMethodKit
import os

/// 입력 내용은 log 에 남기지 않는다 — 상태 전이와 bundle ID 까지만.
nonisolated let log = Logger(subsystem: "com.unocult.inputmethod.homi", category: "lifecycle")

/// IMK 가 입력칸(client) session 마다 하나씩 만드는 controller.
///
/// M0: 모든 key 를 통과시키고(= ABC 처럼 동작) lifecycle 만 기록한다.
/// IMK header 에는 actor 표시가 없어 override 들이 nonisolated 여야 한다. 불리는 곳은 main thread 다.
@objc(HomiInputController)
nonisolated final class HomiInputController: IMKInputController {
    override func activateServer(_ sender: Any!) {
        log.info("activate \(clientID(sender), privacy: .public)")
    }

    override func deactivateServer(_ sender: Any!) {
        log.info("deactivate \(clientID(sender), privacy: .public)")
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        false
    }
}

nonisolated func clientID(_ sender: Any?) -> String {
    (sender as? IMKTextInput)?.bundleIdentifier() ?? "nil"
}
