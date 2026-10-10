import Foundation
import InputSession

/// HID 의 mapping 읽기·쓰기를 주입한다. test 는 실제 keyboard 를 건드리지 않는다.
final class CapsLockMapping {
    typealias Map = [[String: Any]]
    static let capsLock: UInt64 = 0x7_0000_0039
    static let rightControl: UInt64 = 0x7_0000_00E4
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
    /// Windows mapping 은 저장한 소유 기록으로 복원한다. 기록 없는 LANG1·오른쪽 Option 은 임의로 지우지 않는다.
    private var ownsWindowsMapping: Bool
    private let saveWindowsOriginal: (Map?) -> Void

    init(
        read: @escaping () -> Map, write: @escaping (Map) -> Bool,
        windowsOriginal: Map? = nil, saveWindowsOriginal: @escaping (Map?) -> Void = { _ in }
    ) {
        self.read = read
        self.write = write
        self.original = windowsOriginal
        self.ownsWindowsMapping = windowsOriginal != nil
        self.saveWindowsOriginal = saveWindowsOriginal
    }

    func invalidate() { applied = nil }

    @discardableResult
    func apply(_ on: Bool) -> Bool {
        apply(on ? .homi : .system)
    }

    @discardableResult
    func apply(_ route: CapsLockRoute) -> Bool {
        if applied == route { return true }
        let current = read()
        let previous = original ?? current.filter { Self.isCaps($0) && !isOurs($0) }
        var mapping: Map
        if let destination = Self.destination(for: route) {
            mapping = current.filter { !Self.isCaps($0) }
            mapping.append([Self.source: Self.capsLock, Self.destination: destination])
            if case .windows = route, !ownsWindowsMapping {
                // HID 쓰기 전에 복원값을 남긴다. 실패·process 종료 뒤에도 이 값으로만 되돌린다.
                saveWindowsOriginal(previous)
                ownsWindowsMapping = true
                original = previous
            }
        } else {
            // 다른 도구가 바꾼 Caps Lock 은 그대로 둔다. 우리 값이 남았을 때만 치운다.
            mapping = current.filter { !isOurs($0) }
            if current.contains(where: isOurs), !mapping.contains(where: Self.isCaps) {
                mapping += original ?? []
            }
        }
        // 같은 값이면 HID 에 쓰지 않는다. 실패는 cache 하지 않아 다음 알림에 다시 시도한다.
        let done = (current as NSArray).isEqual(to: mapping) || write(mapping)
        guard done else { return false }
        applied = route
        original = route == .system ? nil : previous
        if route == .system, ownsWindowsMapping {
            saveWindowsOriginal(nil)
            ownsWindowsMapping = false
        }
        return true
    }

    private static func isCaps(_ entry: [String: Any]) -> Bool {
        (entry[source] as? UInt64) == capsLock
    }
    private func isOurs(_ entry: [String: Any]) -> Bool {
        let target = entry[Self.destination] as? UInt64
        return Self.isCaps(entry) && (target == Self.rightControl
            || (ownsWindowsMapping && (target == Self.language1 || target == Self.rightOption)))
    }

    private static func destination(for route: CapsLockRoute) -> UInt64? {
        switch route {
        case .system: nil
        case .homi: rightControl
        case .windows(.hangul): language1
        case .windows(.rightAlt): rightOption
        }
    }
}
