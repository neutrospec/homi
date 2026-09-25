import Testing

@testable import InputSession

/// QWERTY 글자 자리의 key. 대문자는 Shift.
func key(_ letter: Character, _ modifiers: Modifiers = []) -> KeyEvent {
    let ansi: [Character: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
        "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32, "i": 34, "p": 35,
        "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
    ]
    let shift: Modifiers = letter.isUppercase ? .shift : []
    return KeyEvent(keyCode: ansi[Character(letter.lowercased())]!, modifiers: modifiers.union(shift))
}

let space = KeyEvent(keyCode: 49)
let backspace = KeyEvent(keyCode: KeyCode.delete)

/// key 들을 차례로 넣은 결과 — 각 key 를 먹었는지와, client 에게 한 일을 이어 붙인 것.
func press(_ keys: [KeyEvent], _ session: inout Session) -> (handled: [Bool], actions: [Action]) {
    let outcomes = keys.map { session.handle($0) }
    return (outcomes.map(\.handled), outcomes.flatMap(\.actions))
}

func press(_ letters: String, _ session: inout Session) -> (handled: [Bool], actions: [Action]) {
    press(letters.map { key($0) }, &session)
}

@Test("자모 key 는 먹고, 조합 중인 글자를 marked text 로 보인다")
func composingIsMarked() {
    var session = Session()
    let result = press("gks", &session)
    #expect(result.handled == [true, true, true])
    #expect(result.actions == [.mark("ㅎ"), .mark("하"), .mark("한")])
}

@Test("음절이 끝나면 확정하고 새 음절을 marked text 로")
func syllableCommits() {
    var session = Session()
    let result = press("dkssud", &session)  // 안녕
    #expect(result.actions == [.mark("ㅇ"), .mark("아"), .mark("안"), .insert("안"), .mark("ㄴ"), .mark("녀"), .mark("녕")])
}

@Test("도깨비불은 앞 음절을 확정하고 넘어간 자음으로 새 marked text")
func dokkaebibul() {
    var session = Session()
    _ = press("rkr", &session)  // 각
    let outcome = session.handle(key("k"))  // + ㅏ
    #expect(outcome == Outcome(handled: true, actions: [.insert("가"), .mark("가")]))
}

@Test("Shift 는 쌍자음, Caps Lock 은 무시", arguments: [
    (key("T"), "ㅆ"),
    (key("O"), "ㅒ"),
    (key("g", .capsLock), "ㅎ"),
    (key("G", .capsLock), "ㅎ"),
])
func shiftAndCapsLock(event: KeyEvent, expected: String) {
    var session = Session()
    let outcome = session.handle(event)
    #expect(outcome == Outcome(handled: true, actions: [.mark(expected)]))
}

@Test("자모가 아닌 key 는 조합을 확정하고 app 으로 넘긴다", arguments: [
    49, 36, 48, 53,  // space return tab esc
    123, 124, 125, 126,  // 화살표
    117,  // forward delete
    18, 29,  // 1 0
    50, 43, 47, 41,  // ` , . ;
] as [UInt16])
func nonJamoCommits(keyCode: UInt16) {
    var session = Session()
    _ = press("gks", &session)
    let outcome = session.handle(KeyEvent(keyCode: keyCode))
    #expect(outcome == Outcome(handled: false, actions: [.insert("한")]))
    #expect(session.composing.isEmpty)
}

@Test("⌘·⌃·⌥·fn 조합은 조합을 확정하고 app 으로 넘긴다", arguments: [
    Modifiers.command, .control, .option, .function, [.command, .shift], [.option, .shift],
])
func modifiedKeysCommit(modifiers: Modifiers) {
    var session = Session()
    _ = press("gks", &session)
    let outcome = session.handle(key("c", modifiers))
    #expect(outcome == Outcome(handled: false, actions: [.insert("한")]))
}

@Test("조합 중인 것이 없으면 자모가 아닌 key 는 아무것도 하지 않고 넘긴다")
func nothingToCommit() {
    var session = Session()
    let result = press([space, key("c", .command)], &session)
    #expect(result.handled == [false, false])
    #expect(result.actions.isEmpty)
}

@Test("Backspace — 조합 중이면 자모 하나를 되돌리고 먹는다")
func backspaceWhileComposing() {
    var session = Session()
    _ = press("ekfr", &session)  // 닭
    let result = press([backspace, backspace, backspace, backspace], &session)
    #expect(result.handled == [true, true, true, true])
    #expect(result.actions == [.mark("달"), .mark("다"), .mark("ㄷ"), .mark("")])
}

@Test("Backspace — 조합 중인 것이 없으면 app 이 지운다")
func backspaceWhenEmpty() {
    var session = Session()
    let outcome = session.handle(backspace)
    #expect(outcome == Outcome(handled: false, actions: []))
}

@Test("commit 은 조합 중인 글자를 확정하고, 두 번째는 아무것도 하지 않는다")
func commitIsIdempotent() {
    var session = Session()
    _ = press("gks", &session)
    let first = session.commit()
    let second = session.commit()
    #expect(first == [.insert("한")])
    #expect(second.isEmpty)
    #expect(session.composing.isEmpty)
}
