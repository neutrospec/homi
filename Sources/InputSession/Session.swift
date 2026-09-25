import HangulCore

/// 한/영 모드. 영문은 key 를 그대로 넘긴다.
public enum Mode: Sendable, Equatable {
    case korean
    case english

    public var toggled: Mode { self == .korean ? .english : .korean }
}

/// 입력칸(client)에 할 일.
public enum Action: Sendable, Equatable {
    /// 조합 중인 글자를 marked text 로 보인다. 빈 문자열이면 marked text 를 지운다.
    case mark(String)
    /// 글자를 확정해 넣는다. marked text 가 있으면 그 자리를 대신한다.
    case insert(String)
}

/// key 하나를 처리한 결과.
public struct Outcome: Sendable, Equatable {
    /// true 면 homi 가 먹었다 — app 은 이 key 를 모른다. false 면 app 이 이어서 처리한다.
    public var handled: Bool
    /// client 에게 이 순서대로 한다.
    public var actions: [Action]
    /// 이 key 다음의 모드. 다음 key 는 이 모드로 처리된다.
    public var mode: Mode

    public init(handled: Bool, actions: [Action], mode: Mode) {
        self.handled = handled
        self.actions = actions
        self.mode = mode
    }
}

/// 입력칸(client) session 하나의 입력. IMK 를 모른다 — 조합 규칙은 docs/spec.md.
///
/// client 를 직접 부르지 않고 할 일을 돌려준다. IMK 는 우리의 `insertText` 도중에 deactivate 를 끼워 부를 수 있어서,
/// 상태를 바꾸는 중에 client 를 부르면 그 사이에 다시 들어온 `commit` 과 겹친다 (docs/research/app-compat-and-hangul.md §1).
/// 조합 중인 글자는 marked text 로만 보이고, 이미 확정한 글자는 다시 쓰지 않는다 (AGENTS.md 결정 5).
///
/// 모드는 session 밖(app 별 기억)에 있고 key 마다 받아서 돌려준다. 전환은 그 key 처리 안에서 끝난다 —
/// 그래서 "전환 → 다음 key" 순서가 구조로 보장된다 (결정 1·3).
public struct Session: Sendable {
    private var composer = Composer()

    public init() {}

    /// 조합 중인 글자.
    public var composing: String { composer.composing }

    public mutating func handle(_ key: KeyEvent, mode: Mode) -> Outcome {
        if key.isToggle { return toggle(from: mode) }
        guard mode == .korean else {
            // 영문: 그대로 넘긴다. (조합이 남아 있을 수 없지만, 있다면 잃지 않게 확정한다.)
            return Outcome(handled: false, actions: commit(), mode: mode)
        }
        // ⌘·⌃·⌥·fn 조합은 app·system 의 몫이다. ⌥ 도 영문일 때와 같게 넘긴다 (2026-09-25 주인 결정).
        if !key.modifiers.isDisjoint(with: [.command, .control, .option, .function]) {
            return Outcome(handled: false, actions: commit(), mode: mode)
        }
        if key.keyCode == KeyCode.delete {
            guard composer.backspace() else { return Outcome(handled: false, actions: [], mode: mode) }
            return Outcome(handled: true, actions: [.mark(composer.composing)], mode: mode)
        }
        guard let jamo = Dubeolsik.jamo(keyCode: key.keyCode, shift: key.modifiers.contains(.shift)) else {
            // Space·Return·문장부호·화살표…: 확정하고, 문자는 아래 layout 이 만들게 넘긴다.
            return Outcome(handled: false, actions: commit(), mode: mode)
        }
        let committed = composer.type(jamo)
        let actions: [Action] = committed.isEmpty ? [] : [.insert(committed)]
        return Outcome(handled: true, actions: actions + [.mark(composer.composing)], mode: mode)
    }

    /// 한/영 전환 — 조합 중이면 먼저 확정한다. 전환 key 는 먹는다.
    public mutating func toggle(from mode: Mode) -> Outcome {
        Outcome(handled: true, actions: commit(), mode: mode.toggled)
    }

    /// 조합 중인 글자를 확정한다 — 입력칸을 떠날 때, client 가 요청할 때, 넘기는 key 앞에서.
    /// 비우면서 돌려주므로 두 번 불려도 한 번만 들어간다.
    public mutating func commit() -> [Action] {
        let text = composer.flush()
        return text.isEmpty ? [] : [.insert(text)]
    }
}
