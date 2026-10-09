import Foundation

/// HID 의 mapping 읽기·쓰기를 주입한다. test 는 실제 keyboard 를 건드리지 않는다.
final class CapsLockMapping {
    typealias Map = [[String: Any]]
    static let capsLock: UInt64 = 0x7_0000_0039
    static let rightControl: UInt64 = 0x7_0000_00E4
    static let source = "HIDKeyboardModifierMappingSrc"
    static let destination = "HIDKeyboardModifierMappingDst"

    private let read: () -> Map
    private let write: (Map) -> Bool
    private var applied: Bool?
    /// homi 가 덮기 전 Caps Lock mapping. wake 뒤에도 원래 값을 잊지 않는다.
    private var original: Map?

    init(read: @escaping () -> Map, write: @escaping (Map) -> Bool) {
        self.read = read
        self.write = write
    }

    func invalidate() { applied = nil }

    @discardableResult
    func apply(_ on: Bool) -> Bool {
        if applied == on { return true }
        let current = read()
        let previous = original ?? current.filter { Self.isCaps($0) && !Self.isOurs($0) }
        var mapping: Map
        if on {
            mapping = current.filter { !Self.isCaps($0) }
            mapping.append([Self.source: Self.capsLock, Self.destination: Self.rightControl])
        } else {
            // 다른 도구가 바꾼 Caps Lock 은 그대로 둔다. 우리 값이 남았을 때만 치운다.
            mapping = current.filter { !Self.isOurs($0) }
            if current.contains(where: Self.isOurs), !mapping.contains(where: Self.isCaps) {
                mapping += original ?? []
            }
        }
        // 같은 값이면 HID 에 쓰지 않는다. 실패는 cache 하지 않아 다음 알림에 다시 시도한다.
        let done = (current as NSArray).isEqual(to: mapping) || write(mapping)
        guard done else { return false }
        applied = on
        original = on ? previous : nil
        return true
    }

    private static func isCaps(_ entry: [String: Any]) -> Bool {
        (entry[source] as? UInt64) == capsLock
    }
    private static func isOurs(_ entry: [String: Any]) -> Bool {
        isCaps(entry) && (entry[destination] as? UInt64) == rightControl
    }
}
