/// key 하나 — AppKit 의 NSEvent 에서 homi 가 판단에 쓰는 것만 옮긴 값.
public struct KeyEvent: Sendable, Equatable {
    public var keyCode: UInt16
    public var modifiers: Modifiers

    public init(keyCode: UInt16, modifiers: Modifiers = []) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

public struct Modifiers: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let shift = Modifiers(rawValue: 1 << 0)
    public static let control = Modifiers(rawValue: 1 << 1)
    public static let option = Modifiers(rawValue: 1 << 2)
    public static let command = Modifiers(rawValue: 1 << 3)
    public static let capsLock = Modifiers(rawValue: 1 << 4)
    public static let function = Modifiers(rawValue: 1 << 5)
}

extension KeyEvent: CustomStringConvertible {
    /// 기록용: `kc=5 ⇧`
    public var description: String {
        let symbols: [(Modifiers, String)] = [
            (.capsLock, "⇪"), (.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘"), (.function, "fn"),
        ]
        let flags = symbols.filter { modifiers.contains($0.0) }.map(\.1).joined()
        return flags.isEmpty ? "kc=\(keyCode)" : "kc=\(keyCode) \(flags)"
    }
}

/// 판단에 쓰는 key 자리 (macOS virtual key code, ANSI).
public enum KeyCode {
    public static let delete: UInt16 = 51
}
