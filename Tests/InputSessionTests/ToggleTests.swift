import Testing

@testable import InputSession

let f18 = KeyEvent(keyCode: KeyCode.f18, modifiers: .function)  // Caps Lock 이 remap 되어 오는 모양 그대로
let shiftSpace = KeyEvent(keyCode: KeyCode.space, modifiers: .shift)

@Test("전환 key 는 먹고 모드를 바꾼다", arguments: [f18, shiftSpace, KeyEvent(keyCode: KeyCode.f18)])
func toggleKeys(key: KeyEvent) {
    var session = Session()
    let toKorean = session.handle(key, mode: .english)
    let toEnglish = session.handle(key, mode: .korean)
    #expect(toKorean == Outcome(handled: true, actions: [], mode: .korean))
    #expect(toEnglish == Outcome(handled: true, actions: [], mode: .english))
}

@Test("Shift+Space 가 아닌 space 조합은 전환이 아니다", arguments: [
    KeyEvent(keyCode: KeyCode.space),
    KeyEvent(keyCode: KeyCode.space, modifiers: [.shift, .command]),
    KeyEvent(keyCode: KeyCode.space, modifiers: .control),
])
func notToggle(key: KeyEvent) {
    var session = Session()
    let outcome = session.handle(key, mode: .english)
    #expect(outcome == Outcome(handled: false, actions: [], mode: .english))
}

@Test("Caps Lock 이 켜져 있어도 Shift+Space 는 전환")
func shiftSpaceWithCapsLock() {
    var session = Session()
    let outcome = session.handle(KeyEvent(keyCode: KeyCode.space, modifiers: [.shift, .capsLock]), mode: .korean)
    #expect(outcome.mode == .english)
}

@Test("영문 모드는 모든 key 를 그대로 넘긴다")
func englishPassesThrough() {
    var session = Session()
    let result = press([key("g"), key("K"), backspace, space, key("c", .command)], &session, mode: .english)
    #expect(result.handled == [false, false, false, false, false])
    #expect(result.actions.isEmpty)
    #expect(result.mode == .english)
}

@Test("조합 중에 전환하면 먼저 확정한다")
func toggleCommits() {
    var session = Session()
    _ = press("gks", &session)
    let outcome = session.handle(f18, mode: .korean)
    #expect(outcome == Outcome(handled: true, actions: [.insert("한")], mode: .english))
    #expect(session.composing.isEmpty)
}

// 이 입력기가 존재하는 이유 — "한글 모드인데 첫 자음이 영문" 이 구조로 불가능함을 고정한다.
// 전환 key 와 다음 key 가 같은 흐름에서 차례로 처리되므로, 전환 바로 뒤의 key 는 반드시 새 모드다.

@Test("전환 → 다음 key: 영문에서 전환한 직후의 첫 key 는 한글로 조합된다")
func firstKeyAfterToggleToKorean() {
    var session = Session()
    let result = press([f18, key("g"), key("k"), key("s")], &session, mode: .english)
    #expect(result.handled == [true, true, true, true])
    #expect(result.actions == [.mark("ㅎ"), .mark("하"), .mark("한")])
    #expect(result.mode == .korean)
}

@Test("전환 → 다음 key: 한글에서 전환한 직후의 첫 key 는 영문으로 넘어간다")
func firstKeyAfterToggleToEnglish() {
    var session = Session()
    let result = press([key("g"), key("k"), f18, key("g")], &session, mode: .korean)
    #expect(result.handled == [true, true, true, false])
    #expect(result.actions == [.mark("ㅎ"), .mark("하"), .insert("하")])
    #expect(result.mode == .english)
}

@Test("전환을 여러 번 빠르게 해도 key 마다 모드가 정확하다")
func rapidToggles() {
    var session = Session()
    let keys = [f18, key("r"), f18, key("r"), shiftSpace, key("r"), f18, f18, key("r")]
    let result = press(keys, &session, mode: .english)
    // 영 →한 ㄱ →(확정)영 r(통과) →한 ㄱ →(확정)영 →한 ㄱ
    #expect(result.handled == [true, true, true, false, true, true, true, true, true])
    #expect(result.actions == [.mark("ㄱ"), .insert("ㄱ"), .mark("ㄱ"), .insert("ㄱ"), .mark("ㄱ")])
    #expect(result.mode == .korean)
}

@Test("오른쪽 ⌘ — 사이에 아무것도 없이 짧게 누르면 tap")
func commandTap() {
    var tap = CommandTap()
    tap.press(at: 10.0, activity: [1, 2, 3])
    let tapped1 = tap.release(at: 10.1, activity: [1, 2, 3])
    #expect(tapped1)
}

@Test("오른쪽 ⌘ — ⌘C·⌘Tab 처럼 사이에 key 가 눌렸으면 tap 이 아니다 (입력기가 그 key 를 못 봤어도)")
func commandTapWithKeyInBetween() {
    var tap = CommandTap()
    tap.press(at: 10.0, activity: [1, 2, 3])
    let tapped2 = tap.release(at: 10.1, activity: [2, 2, 3])
    #expect(!tapped2)
}

@Test("오른쪽 ⌘ — 오래 눌렀다 떼면 tap 이 아니다")
func commandTapTooLong() {
    var tap = CommandTap()
    tap.press(at: 10.0, activity: [1])
    let tapped3 = tap.release(at: 10.0 + CommandTap.limit, activity: [1])
    #expect(!tapped3)
}

@Test("오른쪽 ⌘ — 다른 수식키가 끼면 취소, 누른 적 없이 떼면 아무것도 아니다")
func commandTapCancelled() {
    var tap = CommandTap()
    tap.press(at: 10.0, activity: [1])
    tap.cancel()
    let tapped4 = tap.release(at: 10.1, activity: [1])
    #expect(!tapped4)
    let tapped5 = tap.release(at: 10.2, activity: [1])
    #expect(!tapped5)
}
