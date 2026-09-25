import AppKit
import InputMethodKit
import InputSession
import Synchronization

/// IMK 가 입력칸(client) session 마다 하나씩 만드는 controller. 입력의 판단은 `Session` 과 `AppRules` 가 하고,
/// 여기서는 event 를 넘기고 결과를 client 에 옮길 뿐이다 (AGENTS.md 결정 7).
///
/// 한/영 모드는 app 별 기억(`memory`)에 있고, key 마다 이 입력칸의 app 으로 읽는다 —
/// activate 알림이 늦거나 빠져도 틀리지 않는다.
/// IMK header 에는 actor 표시가 없어 override 들이 nonisolated 여야 한다. 불리는 곳은 main thread 다.
@objc(HomiInputController)
nonisolated final class HomiInputController: IMKInputController {
    private var session = Session()
    private var commandTap = ModifierTap()
    private var capsLockTap = ModifierTap()
    /// 이 controller 가 맡은 입력칸의 app — controller 는 client 하나에 묶여 있어 바뀌지 않는다.
    private var app: String?

    private static let rightCommand: UInt16 = 54
    /// Caps Lock 은 homi 가 선택된 동안 오른쪽 Control 로 remap 되어 온다 (`CapsLockRemap`).
    private static let capsLock: UInt16 = 62

    /// flagsChanged 는 수식키 tap(오른쪽 ⌘, Caps Lock)을 보려고 받는다. 그러면 IMK 의 기본 mouse 처리
    /// (조합 영역 밖을 click 하면 commitComposition) 가 꺼지므로 leftMouseDown 도 받아 직접 확정한다 — IMKInputController.h.
    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask([.keyDown, .flagsChanged, .leftMouseDown]).rawValue)
    }

    override func activateServer(_ sender: Any!) {
        // homi 가 넘긴 key 는 이 layout 으로 문자가 된다 — 늘 ABC (한글 모드의 ` 도 ` 가 된다).
        (sender as? IMKTextInput)?.overrideKeyboard(withKeyboardNamed: "com.apple.keylayout.ABC")
        let app = resolveApp(sender)
        let profile = AppRules.profile(for: app)
        let (mode, changed) = memory.withLock { memory in
            let before = memory
            let mode = memory.activate(app, profile: profile)
            return (mode, memory != before ? memory : nil)
        }
        if let changed { Memory.save(changed) }
        log.info("activate \(app, privacy: .public)")
        record("activate \(app) \(mode)")
        Task { @MainActor in Indicator.shared.show(mode) }
    }

    override func deactivateServer(_ sender: Any!) {
        log.info("deactivate \(clientID(sender), privacy: .public)")
        record("deactivate \(clientID(sender))")
        commandTap.cancel()
        capsLockTap.cancel()
        commit()
    }

    /// client 가 조합을 끝내 달라고 할 때 — focus 이동, input source 전환.
    override func commitComposition(_ sender: Any!) {
        record("commitComposition \(clientID(sender))")
        commit()
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, let proxy = sender as? any IMKTextInput & NSObjectProtocol else { return false }
        let app = resolveApp(sender)
        switch event.type {
        case .keyDown:
            return keyDown(event, app: app, client: Client(proxy: proxy))
        case .flagsChanged:
            modifiersChanged(event, app: app, client: Client(proxy: proxy))
            return false
        case .leftMouseDown:
            record("mouseDown")
            commit()
            return false
        default:
            return false
        }
    }

    private func keyDown(_ event: NSEvent, app: String, client: Client) -> Bool {
        commandTap.cancel()
        capsLockTap.cancel()
        let key = KeyEvent(event)
        record("key \(key)")
        let mode = memory.withLock { $0.mode(for: app) }
        // 상태 변경을 끝낸 뒤에 client 를 부른다 — insertText 도중에 IMK 가 deactivate 를 끼워 부를 수 있다.
        var outcome = session.handle(key, mode: mode, profile: AppRules.profile(for: app))
        if outcome.resend && !Resend.allowed() {
            // 다시 보낼 수 없으면 먹지 않는다 — key 를 잃는 것보다 예전처럼 넘기는 게 낫다.
            outcome.handled = false
            outcome.resend = false
            record("  resend not allowed — passed")
        }
        switchMode(to: outcome.mode, from: mode, app: app)
        client.apply(outcome.actions)
        if outcome.resend {
            record("  resend")
            Resend.post(event)
        }
        record(outcome.handled ? "  handled" : "  passed")
        return outcome.handled
    }

    /// 수식키 tap — 오른쪽 ⌘: 짧게 = 전환. Caps Lock: 짧게 = 전환, 길게 = 대문자 고정 (macOS 와 같게).
    /// 판정은 `ModifierTap` — ⌘C·⌘Tab 처럼 사이에 key 가 눌린 것은 system 의 key 누름 횟수로 걸러진다.
    private func modifiersChanged(_ event: NSEvent, app: String, client: Client) {
        let flags = event.modifierFlags
        switch event.keyCode {
        case Self.rightCommand:
            capsLockTap.cancel()
            let others: NSEvent.ModifierFlags = [.shift, .control, .option, .function]
            if track(&commandTap, event, down: flags.contains(.command), others: others) == .tap {
                record("right command tap")
                toggle(app: app, client: client)
            }
        case Self.capsLock:
            commandTap.cancel()
            let others: NSEvent.ModifierFlags = [.shift, .command, .option, .function]
            switch track(&capsLockTap, event, down: flags.contains(.control), others: others) {
            case .tap:
                record("caps lock tap")
                toggle(app: app, client: client)
            case .hold:
                record("caps lock hold")
                CapsLockState.toggle()
            case .none:
                break
            }
        default:
            // 다른 수식키가 끼었다. (대문자 고정을 뒤집을 때 오는 echo 도 여기로 — 이미 판정이 끝난 뒤다.)
            commandTap.cancel()
            capsLockTap.cancel()
        }
    }

    /// 수식키 하나의 누름·뗌을 판정기에 넘긴다. 누를 때 다른 수식키가 함께면 tap 이 아니다.
    private func track(_ tap: inout ModifierTap, _ event: NSEvent, down: Bool, others: NSEvent.ModifierFlags)
        -> ModifierTap.Result
    {
        if down {
            if event.modifierFlags.isDisjoint(with: others) {
                tap.press(at: event.timestamp, activity: Activity.now())
            } else {
                tap.cancel()
            }
            return .none
        }
        return tap.release(at: event.timestamp, activity: Activity.now())
    }

    private func toggle(app: String, client: Client) {
        let mode = memory.withLock { $0.mode(for: app) }
        let outcome = session.toggle(from: mode)
        switchMode(to: outcome.mode, from: mode, app: app)
        client.apply(outcome.actions)
    }

    private func switchMode(to mode: Mode, from old: Mode, app: String) {
        guard mode != old else { return }
        let updated = memory.withLock { memory in
            memory.remember(mode, for: app)
            return memory
        }
        Memory.save(updated)
        record("mode \(mode)")
        // menu bar 표시는 key 처리 밖에서 — 결정 4
        Task { @MainActor in Indicator.shared.show(mode) }
    }

    /// 이 입력칸의 app. client 가 bundle ID 를 모르면 맨 앞 app 으로 (조사: nil 일 수 있다).
    private func resolveApp(_ sender: Any?) -> String {
        if let app { return app }
        let id = (sender as? IMKTextInput)?.bundleIdentifier() ?? ""
        let resolved = id.isEmpty ? frontmostApp() : id
        app = resolved
        return resolved
    }

    private func frontmostApp() -> String {
        MainActor.assumeIsolated { NSWorkspace.shared.frontmostApplication?.bundleIdentifier } ?? "unknown"
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

/// 먹은 key 를 app 에 다시 보낸다 (`Outcome.resend`) — 손쉬운 사용 권한이 필요하다.
/// 다시 보낸 key 는 event 대기열의 끝에 붙는다: 그 key 뒤 수 ms 안에 이미 눌린 key 가 있으면 순서가 바뀔 수 있다 (AGENTS.md).
nonisolated enum Resend {
    private static let requested = Mutex(false)

    /// 권한이 있는가. 없으면 한 번만 요청한다 — System Settings 의 손쉬운 사용에 homi 가 나타난다.
    static func allowed() -> Bool {
        if CGPreflightPostEventAccess() { return true }
        let first = requested.withLock { asked in
            defer { asked = true }
            return !asked
        }
        if first {
            log.info("requesting post-event access")
            _ = CGRequestPostEventAccess()
        }
        return false
    }

    /// 새 key event 를 만들어 실제 keyboard 와 같은 경로(HID)로 보낸다 — key code 와 수식키만 옮긴다.
    /// 원래 event 를 복사해 보냈더니 Telegram 에 닿지 않았다 ("틱" 소리, 2026-09-25): 복사본에 원래 event 의 창·시각이 따라간다.
    /// 원래 key 처리가 끝난 뒤에 보낸다 — app 이 아직 그 key 를 처리하는 도중이다.
    static func post(_ event: NSEvent) {
        let keyCode = CGKeyCode(event.keyCode)
        let flags = event.cgEvent?.flags ?? []
        DispatchQueue.main.async {
            let source = CGEventSource(stateID: .hidSystemState)
            for down in [true, false] {
                guard let key = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else { continue }
                key.flags = flags
                key.post(tap: .cghidEventTap)
            }
            record("  resent kc=\(keyCode)")
        }
    }
}