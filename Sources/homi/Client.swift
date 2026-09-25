import AppKit
import InputMethodKit
import InputSession

extension KeyEvent {
    /// NSEvent 에서 판단에 쓰는 것만 옮긴다.
    nonisolated init(_ event: NSEvent) {
        let flags = event.modifierFlags
        let pairs: [(NSEvent.ModifierFlags, Modifiers)] = [
            (.shift, .shift), (.control, .control), (.option, .option),
            (.command, .command), (.capsLock, .capsLock), (.function, .function),
        ]
        let modifiers = pairs.reduce(into: Modifiers()) { result, pair in
            if flags.contains(pair.0) { result.insert(pair.1) }
        }
        self.init(keyCode: event.keyCode, modifiers: modifiers)
    }
}

/// IMK 의 client proxy 에 Session 이 정한 일을 한다.
/// replacementRange 는 늘 NSNotFound — 문서 위치를 믿지 않는다 (AGENTS.md 결정 5).
nonisolated struct Client {
    let proxy: any IMKTextInput & NSObjectProtocol

    private static let nowhere = NSRange(location: NSNotFound, length: 0)

    func apply(_ actions: [Action]) {
        for action in actions {
            switch action {
            case .mark(let text):
                record("  mark \"\(text)\"")
                let caret = NSRange(location: (text as NSString).length, length: 0)
                proxy.setMarkedText(text, selectionRange: caret, replacementRange: Self.nowhere)
            case .insert(let text):
                record("  insert \"\(text)\"")
                proxy.insertText(text, replacementRange: Self.nowhere)
            }
        }
    }
}

nonisolated func clientID(_ sender: Any?) -> String {
    (sender as? IMKTextInput)?.bundleIdentifier() ?? "nil"
}
