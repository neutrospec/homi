import Testing

@testable import InputSession

let shiftSpace = KeyEvent(keyCode: 49, modifiers: .shift)

/// 전환(`toggle`)과 key 들을 흐름 순서대로 — app 층이 하는 그대로, 앞의 모드로 다음 것을 처리한다.
enum Step {
    case key(KeyEvent)
    case toggle
}

func run(_ steps: [Step], _ session: inout Session, mode: Mode)
    -> (handled: [Bool], actions: [Action], mode: Mode)
{
    var mode = mode
    var handled: [Bool] = []
    var actions: [Action] = []
    for step in steps {
        let outcome =
            switch step {
            case .key(let key): session.handle(key, mode: mode)
            case .toggle: session.toggle(from: mode)
            }
        handled.append(outcome.handled)
        actions += outcome.actions
        mode = outcome.mode
    }
    return (handled, actions, mode)
}

@Test("전환은 모드를 뒤집는다")
func toggleFlips() {
    var session = Session()
    let toKorean = session.toggle(from: .english)
    let toEnglish = session.toggle(from: .korean)
    #expect(toKorean == Outcome(handled: true, actions: [], mode: .korean))
    #expect(toEnglish == Outcome(handled: true, actions: [], mode: .english))
}

@Test("조합 중에 전환하면 먼저 확정한다")
func toggleCommits() {
    var session = Session()
    _ = press("gks", &session)
    let outcome = session.toggle(from: .korean)
    #expect(outcome == Outcome(handled: true, actions: [.insert("한")], mode: .english))
    #expect(session.composing.isEmpty)
}

@Test("Shift+Space 는 전환이 아니다 — 영문에서는 그대로, 한글에서는 확정하고 space 로 넘어간다 (2026-09-25 주인 결정)")
func shiftSpaceIsSpace() {
    var session = Session()
    let english = session.handle(shiftSpace, mode: .english)
    #expect(english == Outcome(handled: false, actions: [], mode: .english))
    _ = press("gks", &session)
    let korean = session.handle(shiftSpace, mode: .korean)
    #expect(korean == Outcome(handled: false, actions: [.insert("한")], mode: .korean))
}

@Test("영문 모드는 모든 key 를 그대로 넘긴다")
func englishPassesThrough() {
    var session = Session()
    let result = press([key("g"), key("K"), backspace, space, key("c", .command)], &session, mode: .english)
    #expect(result.handled == [false, false, false, false, false])
    #expect(result.actions.isEmpty)
    #expect(result.mode == .english)
}

// 이 입력기가 존재하는 이유 — "한글 모드인데 첫 자음이 영문" 이 구조로 불가능함을 고정한다.
// 전환 key 와 다음 key 가 같은 흐름에서 차례로 처리되므로, 전환 바로 뒤의 key 는 반드시 새 모드다.

@Test("전환 → 다음 key: 영문에서 전환한 직후의 첫 key 는 한글로 조합된다")
func firstKeyAfterToggleToKorean() {
    var session = Session()
    let result = run([.toggle, .key(key("g")), .key(key("k")), .key(key("s"))], &session, mode: .english)
    #expect(result.actions == [.mark("ㅎ"), .mark("하"), .mark("한")])
    #expect(result.mode == .korean)
}

@Test("전환 → 다음 key: 한글에서 전환한 직후의 첫 key 는 영문으로 넘어간다")
func firstKeyAfterToggleToEnglish() {
    var session = Session()
    let result = run([.key(key("g")), .key(key("k")), .toggle, .key(key("g"))], &session, mode: .korean)
    #expect(result.handled == [true, true, true, false])
    #expect(result.actions == [.mark("ㅎ"), .mark("하"), .insert("하")])
    #expect(result.mode == .english)
}

@Test("전환을 여러 번 빠르게 해도 key 마다 모드가 정확하다")
func rapidToggles() {
    var session = Session()
    let r = Step.key(key("r"))
    let result = run([.toggle, r, .toggle, r, .toggle, r, .toggle, .toggle, r], &session, mode: .english)
    // 영 →한 ㄱ →(확정)영 r(통과) →한 ㄱ →(확정)영 →한 ㄱ
    #expect(result.handled == [true, true, true, false, true, true, true, true, true])
    #expect(result.actions == [.mark("ㄱ"), .insert("ㄱ"), .mark("ㄱ"), .insert("ㄱ"), .mark("ㄱ")])
    #expect(result.mode == .korean)
}

// MARK: - 수식키 tap (오른쪽 ⌘, Caps Lock)

@Test("짧게 단독으로 눌렀다 떼면 tap")
func modifierTap() {
    var tap = ModifierTap()
    tap.press(at: 10.0, activity: [1, 2, 3])
    let result = tap.release(at: 10.1, activity: [1, 2, 3])
    #expect(result == .tap)
}

@Test("오래 단독으로 누르고 있다가 떼면 hold — Caps Lock 은 대문자 고정")
func modifierHold() {
    var tap = ModifierTap()
    tap.press(at: 10.0, activity: [1])
    let result = tap.release(at: 10.0 + ModifierTap.holdAfter, activity: [1])
    #expect(result == .hold)
}

@Test("⌘C·⌘Tab 처럼 사이에 key 가 눌렸으면 아무것도 아니다 (입력기가 그 key 를 못 봤어도)")
func modifierWithKeyInBetween() {
    var tap = ModifierTap()
    tap.press(at: 10.0, activity: [1, 2, 3])
    let short = tap.release(at: 10.1, activity: [2, 2, 3])
    tap.press(at: 20.0, activity: [1, 2, 3])
    let long = tap.release(at: 21.0, activity: [1, 3, 3])
    #expect(short == .none)
    #expect(long == .none)
}

@Test("다른 수식키가 끼면 취소, 누른 적 없이 떼면 아무것도 아니다")
func modifierCancelled() {
    var tap = ModifierTap()
    tap.press(at: 10.0, activity: [1])
    tap.cancel()
    let afterCancel = tap.release(at: 10.1, activity: [1])
    let withoutPress = tap.release(at: 10.2, activity: [1])
    #expect(afterCancel == .none)
    #expect(withoutPress == .none)
}

@Test("누르고 있는 채로 hold 시간이 지나면 그때 hold — 뗄 때는 아무것도 아니다 (macOS 의 Caps Lock 처럼)")
func holdReachedWhilePressed() {
    var tap = ModifierTap()
    tap.press(at: 10.0, activity: [1])
    let reached = tap.holdReached(activity: [1])
    let again = tap.holdReached(activity: [1])
    let released = tap.release(at: 11.0, activity: [1])
    #expect(reached)
    #expect(!again)
    #expect(released == .none)
}

@Test("hold 시간 전에 다른 key 가 눌렸으면 hold 가 아니다")
func holdNotReachedWithKey() {
    var tap = ModifierTap()
    tap.press(at: 10.0, activity: [1])
    let reached = tap.holdReached(activity: [2])
    let released = tap.release(at: 10.1, activity: [2])
    #expect(!reached)
    #expect(released == .none)
}

@Test("누른 적 없거나 이미 뗀 뒤의 timer 는 아무것도 아니다")
func holdReachedAfterRelease() {
    var tap = ModifierTap()
    let before = tap.holdReached(activity: [1])
    tap.press(at: 10.0, activity: [1])
    _ = tap.release(at: 10.1, activity: [1])
    let after = tap.holdReached(activity: [1])
    #expect(!before)
    #expect(!after)
}
