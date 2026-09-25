import AppKit
import Carbon
import IOKit.hidsystem
import InputSession
import Synchronization

/// menu bar 의 한/A 표시. homi 가 선택된 동안에만 보인다.
/// system 의 input menu icon 은 늘 "호" 로 고정이고, 모드는 여기서만 보인다 (AGENTS.md 열린 결정 — (a)).
final class Indicator {
    static let shared = Indicator()

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    private init() {
        item.isVisible = false
        show(.english)
    }

    func show(_ mode: Mode) {
        item.button?.title = mode == .korean ? "한" : "A"
    }

    func setVisible(_ visible: Bool) {
        item.isVisible = visible
    }
}

/// homi 가 선택됐는지 지켜본다 — 선택된 동안에만 Caps Lock 을 오른쪽 Control 로 바꾸고 한/A 를 보인다.
/// 다른 input source(비밀번호 칸의 ABC 포함)에서는 Caps Lock 이 원래대로 동작한다.
final class SourceWatcher: NSObject {
    private var remapped: Bool?

    override init() {
        super.init()
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(sourceChanged(_:)),
            name: .init(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil,
            suspensionBehavior: .deliverImmediately)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(woke(_:)), name: NSWorkspace.didWakeNotification, object: nil)
        update()
    }

    @objc func sourceChanged(_ note: Notification) { update() }

    /// 잠에서 깨면 key mapping 이 풀렸을 수 있다 — 다시 건다.
    @objc func woke(_ note: Notification) {
        remapped = nil
        update()
    }

    /// 지금 선택된 input source 가 homi 인가.
    static func homiSelected() -> Bool {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let id = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
            .map { Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String } ?? ""
        return id.hasPrefix("com.unocult.inputmethod.homi")
    }

    private func update() {
        let selected = Self.homiSelected()
        if selected != remapped {
            CapsLockRemap.apply(selected)
            remapped = selected
        }
        Indicator.shared.setVisible(selected)
    }
}

/// Caps Lock 을 오른쪽 Control 로 바꾼다 — 누름·뗌이 flagsChanged 로 오고, 수식키라 어느 app 에도 글자가 새지 않는다.
/// (F18 로 바꿨을 때는 Ghostty·iTerm2 가 입력기가 먹은 F18 을 terminal 로 보냈다 — docs/macos-input.md.)
/// MacBook 에는 물리 오른쪽 Control 이 없어 헷갈릴 key 도 없다. 관리자 권한이 필요 없다 (macOS 27 에서 확인).
/// 다른 도구가 건 mapping 은 건드리지 않는다.
enum CapsLockRemap {
    private static let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
    private static let capsLock: UInt64 = 0x7_0000_0039
    private static let rightControl: UInt64 = 0x7_0000_00E4
    private static let source = "HIDKeyboardModifierMappingSrc"
    private static let destination = "HIDKeyboardModifierMappingDst"

    static func apply(_ on: Bool) {
        let key = kIOHIDUserKeyUsageMapKey as CFString
        let current = IOHIDEventSystemClientCopyProperty(client, key) as? [[String: Any]] ?? []
        var mapping = current.filter { ($0[source] as? UInt64) != capsLock }
        if on { mapping.append([source: capsLock, destination: rightControl]) }
        let done = IOHIDEventSystemClientSetProperty(client, key, mapping as CFArray)
        log.info("caps lock → right control \(on ? "on" : "off", privacy: .public): \(done, privacy: .public)")
        record("caps lock remap \(on ? "on" : "off") \(done)")
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
