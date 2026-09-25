import AppKit
import InputMethodKit
import InputSession
import Synchronization

/// 한/영 모드 — M3 는 모든 app 이 하나를 나눠 쓴다 (M4 부터 app 별). key 처리 안에서 동기적으로 읽고 쓴다.
nonisolated let modeStore = Mutex(Mode.english)

/// IMK 가 입력칸(client) session 마다 하나씩 만드는 controller. 입력의 판단은 `Session` 이 하고,
/// 여기서는 event 를 넘기고 결과를 client 에 옮길 뿐이다 (AGENTS.md 결정 7).
///
/// IMK header 에는 actor 표시가 없어 override 들이 nonisolated 여야 한다. 불리는 곳은 main thread 다.
@objc(HomiInputController)
nonisolated final class HomiInputController: IMKInputController {
    private var session = Session()
    private var commandTap = CommandTap()

    private static let rightCommand: UInt16 = 54

    /// flagsChanged 는 오른쪽 ⌘ tap 을 보려고 받는다. 그러면 IMK 의 기본 mouse 처리
    /// (조합 영역 밖을 click 하면 commitComposition) 가 꺼지므로 leftMouseDown 도 받아 직접 확정한다 — IMKInputController.h.
    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask([.keyDown, .flagsChanged, .leftMouseDown]).rawValue)
    }

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
        commandTap.cancel()
        commit()
    }

    /// client 가 조합을 끝내 달라고 할 때 — focus 이동, input source 전환.
    override func commitComposition(_ sender: Any!) {
        record("commitComposition \(clientID(sender))")
        commit()
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, let proxy = sender as? any IMKTextInput & NSObjectProtocol else { return false }
        switch event.type {
        case .keyDown:
            return keyDown(event, client: Client(proxy: proxy))
        case .flagsChanged:
            modifiersChanged(event, client: Client(proxy: proxy))
            return false
        case .leftMouseDown:
            record("mouseDown")
            commit()
            return false
        default:
            return false
        }
    }

    private func keyDown(_ event: NSEvent, client: Client) -> Bool {
        commandTap.cancel()
        let key = KeyEvent(event)
        record("key \(key)")
        let mode = modeStore.withLock { $0 }
        // 상태 변경을 끝낸 뒤에 client 를 부른다 — insertText 도중에 IMK 가 deactivate 를 끼워 부를 수 있다.
        let outcome = session.handle(key, mode: mode)
        switchMode(to: outcome.mode, from: mode)
        client.apply(outcome.actions)
        record(outcome.handled ? "  handled" : "  passed")
        return outcome.handled
    }

    /// 오른쪽 ⌘ 를 단독으로 눌렀다 떼면 전환. 판정은 `CommandTap` — ⌘C·⌘Tab 은 system 의 key 누름 횟수로 걸러진다.
    private func modifiersChanged(_ event: NSEvent, client: Client) {
        guard event.keyCode == Self.rightCommand else {
            commandTap.cancel()
            return
        }
        let flags = event.modifierFlags
        if flags.contains(.command) {
            if flags.isDisjoint(with: [.shift, .control, .option, .function]) {
                commandTap.press(at: event.timestamp, activity: Activity.now())
            } else {
                commandTap.cancel()
            }
        } else if commandTap.release(at: event.timestamp, activity: Activity.now()) {
            record("right command tap")
            let mode = modeStore.withLock { $0 }
            let outcome = session.toggle(from: mode)
            switchMode(to: outcome.mode, from: mode)
            client.apply(outcome.actions)
        }
    }

    private func switchMode(to mode: Mode, from old: Mode) {
        guard mode != old else { return }
        modeStore.withLock { $0 = mode }
        record("mode \(mode)")
        // menu bar 표시는 key 처리 밖에서 — 결정 4
        Task { @MainActor in Indicator.shared.show(mode) }
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

/// system 전체의 key·mouse 누름 횟수. 입력기가 못 본 key(⌘C 의 C, ⌘Tab 의 Tab)도 센다 — 권한이 필요 없다.
nonisolated enum Activity {
    static func now() -> [UInt32] {
        [CGEventType.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel].map {
            CGEventSource.counterForEventType(.hidSystemState, eventType: $0)
        }
    }
}
