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
        show(modeStore.withLock { $0 })
    }

    func show(_ mode: Mode) {
        item.button?.title = mode == .korean ? "한" : "A"
    }

    func setVisible(_ visible: Bool) {
        item.isVisible = visible
    }
}

/// homi 가 선택됐는지 지켜본다 — 선택된 동안에만 Caps Lock 을 F18 로 바꾸고 한/A 를 보인다.
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

    private func update() {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let id = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
            .map { Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String } ?? ""
        let selected = id.hasPrefix("com.unocult.inputmethod.homi")
        if selected != remapped {
            CapsLockRemap.apply(selected)
            remapped = selected
        }
        Indicator.shared.setVisible(selected)
    }
}

/// Caps Lock 을 F18 로 바꿔 평범한 keyDown 으로 받는다 — 대문자 고정·불빛·누름 지연·system 의 전환이 끼어들 자리가 없다.
/// 관리자 권한이 필요 없다 (macOS 27 에서 확인). 다른 도구가 건 mapping 은 건드리지 않는다.
enum CapsLockRemap {
    private static let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
    private static let capsLock: UInt64 = 0x7_0000_0039
    private static let f18: UInt64 = 0x7_0000_006D
    private static let source = "HIDKeyboardModifierMappingSrc"
    private static let destination = "HIDKeyboardModifierMappingDst"

    static func apply(_ on: Bool) {
        let key = kIOHIDUserKeyUsageMapKey as CFString
        let current = IOHIDEventSystemClientCopyProperty(client, key) as? [[String: Any]] ?? []
        var mapping = current.filter { ($0[source] as? UInt64) != capsLock }
        if on { mapping.append([source: capsLock, destination: f18]) }
        let done = IOHIDEventSystemClientSetProperty(client, key, mapping as CFArray)
        log.info("caps lock → F18 \(on ? "on" : "off", privacy: .public): \(done, privacy: .public)")
        record("caps lock remap \(on ? "on" : "off") \(done)")
    }
}
