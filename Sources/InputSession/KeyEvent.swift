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
    public static let space: UInt16 = 49
    public static let delete: UInt16 = 51
    /// Caps Lock 을 이 key 로 바꿔 받는다 (homi 가 선택된 동안). 평범한 keyDown 이라 다음 key 와 같은 흐름에 온다.
    public static let f18: UInt16 = 79
}

extension KeyEvent {
    /// 한/영 전환 key — Caps Lock(→F18), Shift+Space. 오른쪽 ⌘ 는 flagsChanged 라 `CommandTap` 이 따로 판정한다.
    /// F18 에는 system 이 fn 수식키를 붙여 보낸다 (probe 로 확인) — 수식키와 무관하게 전환이다.
    var isToggle: Bool {
        keyCode == KeyCode.f18 || (keyCode == KeyCode.space && modifiers.subtracting(.capsLock) == .shift)
    }
}
