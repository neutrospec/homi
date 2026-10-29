import AppKit
import Carbon
import IOKit.hidsystem
import InputSession
import Synchronization

/// menu bar 의 한/A 표시. homi 가 선택된 동안에만 보인다. 한/영 전환 없는 app 에서는 "–".
/// system 의 input menu icon 은 늘 "호" 로 고정이고, 모드는 여기서만 보인다 (AGENTS.md 열린 결정 — (a)).
/// 누르면 설정 menu 가 열린다.
final class Indicator: NSObject {
    static let shared = Indicator()

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    private override init() {
        super.init()
        item.isVisible = false
        let menu = NSMenu()
        let settings = NSMenuItem(title: "homi 설정…", action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        item.menu = menu
        show(.english)
    }

    /// nil 이면 한/영 전환 없는 app 이다.
    func show(_ mode: Mode?) {
        item.button?.title = mode.map { $0 == .korean ? "한" : "A" } ?? "–"
    }

    @objc private func openSettings() {
        SettingsWindow.shared.show()
    }

    func setVisible(_ visible: Bool) {
        item.isVisible = visible
    }
}

/// homi 가 선택됐는지 지켜본다 — 선택된 동안에만 한/A 를 보이고, Caps Lock 을 오른쪽 Control 로 바꾼다.
/// 전환 key 로 고른 Caps Lock 은 일반 app 에서 오른쪽 Control, Windows App 전달 옵션에서는 고른 key 로 바꾼다.
/// Emacs 전달 옵션에서는 F18 로 보내 Emacs 자체 입력기의 전환 명령을 실행한다.
/// 그 밖(다른 input source, 비밀번호 칸의 ABC, 다른 한/영 전환 없는 app)에서는 Caps Lock 이 원래대로 동작한다.
final class SourceWatcher: NSObject {
    override init() {
        super.init()
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(sourceChanged(_:)),
            name: .init(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil,
            suspensionBehavior: .deliverImmediately)
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(woke(_:)), name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(
            self, selector: #selector(appActivated(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(sourceChanged(_:)), name: .homiPreferencesChanged, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(terminating(_:)), name: NSApplication.willTerminateNotification, object: nil)
        update()
    }

    @objc func sourceChanged(_ note: Notification) {
        let selected = update()
        let controllerID = ActiveInputSession.controller?.traceID ?? "none"
        log.info("source notification, homi selected: \(selected), active controller: \(ActiveInputSession.controller != nil), controller: \(controllerID, privacy: .public)")
        ActiveInputSession.controller?.sourceChanged(selected: selected)
    }

    @objc func appActivated(_ note: Notification) {
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        update(front: app?.bundleIdentifier)
    }

    /// 잠에서 깨면 key mapping 이 풀렸을 수 있다 — 다시 건다.
    @objc func woke(_ note: Notification) {
        CapsLockRemap.invalidate()
        ModifierActivityObserver.shared.setContext(app: nil, force: true)
        sourceChanged(note)
    }

    @objc func terminating(_ note: Notification) {
        CapsLockRemap.apply(.system)
    }

    /// 지금 선택된 input source 가 homi 인가.
    static func homiSelected() -> Bool {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let id = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
            .map { Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String } ?? ""
        return id.hasPrefix("com.unocult.inputmethod.homi")
    }

    @discardableResult
    private func update(front: String? = nil) -> Bool {
        let selected = Self.homiSelected()
        let settings = preferences.withLock { $0 }
        let app = front ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        let route = CapsLockRoute.resolve(homiSelected: selected, app: app, preferences: settings)
        CapsLockRemap.apply(route)
        ModifierActivityObserver.shared.setContext(app: selected ? app : nil)
        Indicator.shared.setVisible(selected)
        return selected
    }
}

/// Caps Lock 을 오른쪽 Control 로 바꾼다 — 누름·뗌이 flagsChanged 로 오고, 수식키라 어느 app 에도 글자가 새지 않는다.
/// (F18 로 바꿨을 때는 Ghostty·iTerm2 가 입력기가 먹은 F18 을 terminal 로 보냈다 — docs/macos-input.md.)
/// MacBook 에는 물리 오른쪽 Control 이 없어 헷갈릴 key 도 없다. 관리자 권한이 필요 없다 (macOS 27 에서 확인).
/// Windows App 전달 옵션에서는 LANG1 또는 오른쪽 Option 으로 바꾼다. 원격 검증 범위는 docs/apps/windows-app.md.
/// Emacs 전달 옵션에서는 F18 로 바꾼다 (docs/apps/emacs.md).
/// 다른 도구가 건 mapping 은 보존한다.
enum CapsLockRemap {
    // Windows 전달부터 쓰던 저장 key 를 유지해 기존 소유 기록을 읽는다. Emacs 전달도 같은 복원값을 공유한다.
    private static let ownershipKey = "windowsCapsLockOriginalMapping"
    private static let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
    private static let mapping = CapsLockMapping(read: {
        IOHIDEventSystemClientCopyProperty(client, kIOHIDUserKeyUsageMapKey as CFString) as? [[String: Any]] ?? []
    }, write: { value in
        IOHIDEventSystemClientSetProperty(client, kIOHIDUserKeyUsageMapKey as CFString, value as CFArray)
    }, forwardedOriginal: UserDefaults.standard.array(forKey: ownershipKey) as? [[String: Any]], saveForwardedOriginal: { value in
        // key 처리 경로가 아니라 source·app·설정 알림에서만 저장한다.
        if let value { UserDefaults.standard.set(value, forKey: ownershipKey) }
        else { UserDefaults.standard.removeObject(forKey: ownershipKey) }
    })

    static func invalidate() { mapping.invalidate() }

    static func apply(_ route: CapsLockRoute) {
        let done = mapping.apply(route)
        if !done { log.error("caps lock remap failed") }
    }
}

/// 대문자 고정 — Caps Lock 을 길게 누르면 homi 가 직접 뒤집는다 (macOS 의 Caps Lock 과 같게). 불빛도 따라 바뀐다.
nonisolated enum CapsLockState {
    /// 뒤집고 새 상태(켜졌으면 true)를 돌려준다.
    @discardableResult
    static func toggle() -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        defer { IOObjectRelease(service) }
        var connect: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connect) == KERN_SUCCESS else {
            log.error("caps lock state: cannot open IOHIDSystem")
            return false
        }
        defer { IOServiceClose(connect) }
        var on = false
        IOHIDGetModifierLockState(connect, Int32(kIOHIDCapsLockState), &on)
        IOHIDSetModifierLockState(connect, Int32(kIOHIDCapsLockState), !on)
        record("caps lock state \(on ? "off" : "on")")
        return !on
    }
}
