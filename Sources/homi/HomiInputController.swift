import AppKit
import InputMethodKit
import InputSession

/// IMK 가 입력칸(client) session 마다 하나씩 만드는 controller. 한글 입력의 판단은 `Session` 이 하고,
/// 여기서는 NSEvent 를 넘기고 결과를 client 에 옮길 뿐이다 (AGENTS.md 결정 7).
///
/// M2: 한글 전용. 한/영 전환은 M3.
/// IMK header 에는 actor 표시가 없어 override 들이 nonisolated 여야 한다. 불리는 곳은 main thread 다.
@objc(HomiInputController)
nonisolated final class HomiInputController: IMKInputController {
    private var session = Session()

    override func activateServer(_ sender: Any!) {
        // homi 가 넘긴 key 는 이 layout 으로 문자가 된다 — 늘 ABC (한글 모드의 ` 도 ` 가 된다).
        (sender as? IMKTextInput)?.overrideKeyboard(withKeyboardNamed: "com.apple.keylayout.ABC")
        let id = clientID(sender)
        log.info("activate \(id, privacy: .public)")
        record("activate \(id)")
    }

    override func deactivateServer(_ sender: Any!) {
        let id = clientID(sender)
        log.info("deactivate \(id, privacy: .public)")
        record("deactivate \(id)")
        commit()
    }

    /// client 가 조합을 끝내 달라고 할 때 — click, focus 이동, input source 전환.
    override func commitComposition(_ sender: Any!) {
        record("commitComposition \(clientID(sender))")
        commit()
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, event.type == .keyDown, let proxy = sender as? any IMKTextInput & NSObjectProtocol else {
            return false
        }
        let key = KeyEvent(event)
        record("key \(key)")
        // 상태 변경을 끝낸 뒤에 client 를 부른다 — insertText 도중에 IMK 가 deactivate 를 끼워 부를 수 있다.
        let outcome = session.handle(key)
        Client(proxy: proxy).apply(outcome.actions)
        record(outcome.handled ? "  handled" : "  passed")
        return outcome.handled
    }

    /// 조합 중인 글자를 이 controller 가 맡은 client 에 확정한다.
    /// deactivate·commitComposition 의 sender 는 이미 다른 client 일 수 있어 쓰지 않는다 (docs/research).
    private func commit() {
        let actions = session.commit()
        guard !actions.isEmpty, let proxy = client() else { return }
        Client(proxy: proxy).apply(actions)
    }

    override func menu() -> NSMenu! {
        let menu = NSMenu()
        menu.addItem(withTitle: "최근 key 기록 저장", action: #selector(saveRecentRecord(_:)), keyEquivalent: "")
        return menu
    }

    @objc func saveRecentRecord(_ sender: Any?) {
        do {
            let file = try saveRecord()
            log.info("record saved: \(file.path, privacy: .public)")
            NSWorkspace.shared.activateFileViewerSelecting([file])
        } catch {
            log.error("record save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
