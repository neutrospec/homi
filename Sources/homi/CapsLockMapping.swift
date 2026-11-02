import Foundation
import InputSession

/// HID 의 mapping 읽기·쓰기를 주입한다. test 는 실제 keyboard 를 건드리지 않는다.
final class CapsLockMapping {
    typealias Map = [[String: Any]]
    static let capsLock: UInt64 = 0x7_0000_0039
    static let rightControl: UInt64 = 0x7_0000_00E4
    /// homi route 동안 물리 오른쪽 Control 을 보내는 곳 — Caps Lock 과 섞이지 않게 (2026-11-03 주인).
    static let leftControl: UInt64 = 0x7_0000_00E0
    /// Emacs 의 toggle-input-method 에 연결하는 F18.
    static let f18: UInt64 = 0x7_0000_006D
    /// Windows App 이 오른쪽 Alt 로 바꾸는 Mac 오른쪽 Option.
    static let rightOption: UInt64 = 0x7_0000_00E6
    /// Apple 의 LANG1 — Korean keyboard 의 한/영 key 이며, Japanese keyboard 의 Kana key 에도 해당한다.
    static let language1: UInt64 = 0x7_0000_0090
    static let source = "HIDKeyboardModifierMappingSrc"
    static let destination = "HIDKeyboardModifierMappingDst"

    private let read: () -> Map
    private let write: (Map) -> Bool
    private var applied: CapsLockRoute?
    /// homi 가 덮기 전 Caps Lock mapping. wake 뒤에도 원래 값을 잊지 않는다.
    private var original: Map?
    /// app 에 전달하는 mapping 은 소유 기록으로 복원한다. 기록 없는 F18·LANG1·오른쪽 Option 은 지우지 않는다.
    private var ownsForwardedMapping: Bool
    private let saveForwardedOriginal: (Map?) -> Void

    init(
        read: @escaping () -> Map, write: @escaping (Map) -> Bool,
        forwardedOriginal: Map? = nil, saveForwardedOriginal: @escaping (Map?) -> Void = { _ in }
    ) {
        self.read = read
        self.write = write
        self.original = forwardedOriginal
        self.ownsForwardedMapping = forwardedOriginal != nil
        self.saveForwardedOriginal = saveForwardedOriginal
    }

    func invalidate() { applied = nil }

    @discardableResult
    func apply(_ on: Bool) -> Bool {
        apply(on ? .homi : .system)
    }

    @discardableResult
    func apply(_ route: CapsLockRoute) -> Bool {
        if applied == route {
            // homi 밖(.system)은 cache 를 믿는다 — 다시 읽어 치우면 다른 도구의 mapping 과 다툰다.
            guard let destination = Self.destination(for: route) else { return true }
            // mapping 은 keyboard service 의 수명에 묶이고 다른 도구도 바꾼다 (docs/macos-input.md). 우리 값이 그대로일 때만 믿는다.
            let current = read()
            let caps = current.filter(Self.isCaps)
            let rightControlReady = destination != Self.rightControl || current.contains(where: Self.isRightControlSource)
            if caps.count == 1, (caps[0][Self.destination] as? UInt64) == destination, rightControlReady { return true }
            // 다른 도구가 Caps Lock 을 새로 바꿨으면 그 값을 해제 때의 복원값으로 삼는다. 지워졌으면 기존 복원값을 지킨다.
            let replaced = caps.filter { !isOurs($0) }
            if !replaced.isEmpty {
                original = replaced
                if ownsForwardedMapping { saveForwardedOriginal(replaced) }
            }
            applied = nil
            return apply(route, current: current)
        }
        return apply(route, current: read())
    }

    private func apply(_ route: CapsLockRoute, current: Map) -> Bool {
        let previous = original ?? current.filter { Self.isCaps($0) && !isOurs($0) }
        var mapping: Map
        if let destination = Self.destination(for: route) {
            mapping = current.filter { !Self.isCaps($0) && !Self.isOurRightControl($0) }
            mapping.append([Self.source: Self.capsLock, Self.destination: destination])
            // Caps Lock 을 오른쪽 Control 로 받는 동안 물리 오른쪽 Control 은 왼쪽 Control 로 보낸다 — 단축키는 그대로, 혼자 눌러도 전환되지 않게.
            // 다른 도구가 오른쪽 Control 을 바꿨으면 이미 Caps Lock 과 구별되므로 그대로 둔다 (2026-11-03 주인).
            if destination == Self.rightControl, !mapping.contains(where: Self.isRightControlSource) {
                mapping.append([Self.source: Self.rightControl, Self.destination: Self.leftControl])
            }
            let forwardsKey: Bool = switch route {
            case .windows, .emacs: true
            case .system, .homi: false
            }
            if forwardsKey, !ownsForwardedMapping {
                // HID 쓰기 전에 복원값을 남긴다. 실패·process 종료 뒤에도 이 값으로만 되돌린다.
                saveForwardedOriginal(previous)
                ownsForwardedMapping = true
                original = previous
            }
        } else {
            // 다른 도구가 바꾼 Caps Lock 은 그대로 둔다. 우리 값이 남았을 때만 치운다.
            mapping = current.filter { !isOurs($0) && !Self.isOurRightControl($0) }
            if current.contains(where: isOurs), !mapping.contains(where: Self.isCaps) {
                mapping += original ?? []
            }
        }
        // 같은 값이면 HID 에 쓰지 않는다. 실패는 cache 하지 않아 다음 알림에 다시 시도한다.
        let done = (current as NSArray).isEqual(to: mapping) || write(mapping)
        guard done else { return false }
        applied = route
        original = route == .system ? nil : previous
        if route == .system, ownsForwardedMapping {
            saveForwardedOriginal(nil)
            ownsForwardedMapping = false
        }
        return true
    }

    private static func isCaps(_ entry: [String: Any]) -> Bool {
        (entry[source] as? UInt64) == capsLock
    }
    private static func isRightControlSource(_ entry: [String: Any]) -> Bool {
        (entry[source] as? UInt64) == rightControl
    }
    /// homi 가 거는 값과 같은 오른쪽 Control → 왼쪽 Control 은 homi 의 것으로 본다 — 이전 process 가 남긴 것도 치울 수 있게.
    private static func isOurRightControl(_ entry: [String: Any]) -> Bool {
        isRightControlSource(entry) && (entry[destination] as? UInt64) == leftControl
    }
    private func isOurs(_ entry: [String: Any]) -> Bool {
        let target = entry[Self.destination] as? UInt64
        return Self.isCaps(entry) && (target == Self.rightControl
            || (ownsForwardedMapping && (target == Self.language1 || target == Self.rightOption || target == Self.f18)))
    }

    private static func destination(for route: CapsLockRoute) -> UInt64? {
        switch route {
        case .system: nil
        case .homi: rightControl
        case .windows(.hangul): language1
        case .windows(.rightAlt): rightOption
        case .emacs: f18
        }
    }
}
