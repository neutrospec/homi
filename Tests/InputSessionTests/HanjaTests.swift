import Foundation
import HangulCore
import Testing

@testable import InputSession

/// 실제 사전 — 번들에 들어가는 그 file.
let dictionary: HanjaDictionary = {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Sources/homi/Bundle/Resources/hanja.txt")
    return try! HanjaDictionary(contentsOf: url)
}()

let optionReturn = KeyEvent(keyCode: KeyCode.returnKey, modifiers: .option)
func digit(_ n: Int) -> KeyEvent { KeyEvent(keyCode: KeyCode.digits[n]) }

func hanjaSession(typing letters: String = "") -> Session {
    var session = Session(hanja: dictionary)
    _ = press(letters, &session)
    return session
}

/// app 이 ⌥↩ 에 답하는 커서 앞 글자 — 확정된 `text` 가 문서 위치 `start` 부터 있고, 조합 중인 글자는 그 바로 뒤다.
func document(_ text: String, start: Int = 10) -> (Int) -> (text: String, end: Int)? {
    { count in count <= text.count ? (String(text.suffix(count)), start + text.utf16.count) : nil }
}

func range(_ location: Int, _ length: Int) -> NSRange { NSRange(location: location, length: length) }

/// 열린 후보 창에서 `hanja` 까지 ↓ 로 옮겨 Enter 로 고른다.
func choose(_ hanja: String, from opened: Outcome, _ session: inout Session) -> Outcome? {
    guard case .showCandidates(let list, _) = opened.actions.last,
        let index = list.firstIndex(where: { $0.hanja == hanja })
    else { return nil }
    for _ in 0..<index { _ = session.handle(KeyEvent(keyCode: KeyCode.down), mode: .korean) }
    return session.handle(KeyEvent(keyCode: KeyCode.returnKey), mode: .korean)
}

@Test("조합 중 ⌥↩ — 그 글자의 후보를 연다")
func openForComposing() {
    var session = hanjaSession(typing: "gks")  // 한
    let outcome = session.handle(optionReturn, mode: .korean)
    #expect(outcome.handled)
    guard case .showCandidates(let list, let selected) = outcome.actions.first else {
        Issue.record("후보 창이 열리지 않았다: \(outcome.actions)")
        return
    }
    #expect(list.first?.hanja == "韓")
    #expect(selected == 0)
    #expect(session.composing == "한")  // 고르는 동안 조합은 그대로
}

@Test("숫자로 고르면 조합 중인 글자를 그 한자가 대신한다")
func pickByDigit() {
    var session = hanjaSession(typing: "gks")
    _ = session.handle(optionReturn, mode: .korean)
    let outcome = session.handle(digit(2), mode: .korean)
    #expect(outcome == Outcome(handled: true, actions: [.hideCandidates, .insert("漢")], mode: .korean))
    #expect(session.composing.isEmpty)
}

@Test("↓ 로 옮기고 Enter·Space 로 확정", arguments: [KeyCode.returnKey, KeyCode.space])
func pickByArrowAndConfirm(confirm: UInt16) {
    var session = hanjaSession(typing: "gks")
    _ = session.handle(optionReturn, mode: .korean)
    let moved = session.handle(KeyEvent(keyCode: KeyCode.down), mode: .korean)
    guard case .showCandidates(_, let selected) = moved.actions.first else {
        Issue.record("후보 창이 고쳐지지 않았다")
        return
    }
    #expect(selected == 1)
    let outcome = session.handle(KeyEvent(keyCode: confirm), mode: .korean)
    #expect(outcome == Outcome(handled: true, actions: [.hideCandidates, .insert("漢")], mode: .korean))
}

@Test("→ 는 다음 쪽 — 그 쪽의 숫자는 그 쪽 후보를 고른다")
func nextPage() {
    var session = hanjaSession(typing: "gks")
    let opened = session.handle(optionReturn, mode: .korean)
    guard case .showCandidates(let list, _) = opened.actions.first, list.count > Session.page else {
        Issue.record("한 쪽을 넘는 후보가 있어야 한다")
        return
    }
    _ = session.handle(KeyEvent(keyCode: KeyCode.right), mode: .korean)
    let outcome = session.handle(digit(1), mode: .korean)
    #expect(outcome.actions == [.hideCandidates, .insert(list[Session.page].hanja)])
}

@Test("ESC 는 취소 — 조합 중이던 글자는 남는다")
func cancel() {
    var session = hanjaSession(typing: "gks")
    _ = session.handle(optionReturn, mode: .korean)
    let outcome = session.handle(KeyEvent(keyCode: KeyCode.escape), mode: .korean)
    #expect(outcome == Outcome(handled: true, actions: [.hideCandidates], mode: .korean))
    #expect(session.composing == "한")
}

@Test("다른 key 는 후보를 닫고 평소처럼 처리한다")
func otherKeyCloses() {
    var session = hanjaSession(typing: "gks")
    _ = session.handle(optionReturn, mode: .korean)
    let outcome = session.handle(key("r"), mode: .korean)
    #expect(outcome == Outcome(handled: true, actions: [.hideCandidates, .insert("한"), .mark("ㄱ")], mode: .korean))
}

@Test("선택한 단어 — 선택 영역에서 조합을 시작하고, 고르면 insert 가 그 자리를 대신한다")
func selectedWord() {
    var session = Session(hanja: dictionary)
    let opened = session.handle(optionReturn, mode: .korean, selectedText: { "한자" })
    #expect(opened.actions.first == .mark("한자"))
    let picked = choose("漢字", from: opened, &session)
    #expect(picked == Outcome(handled: true, actions: [.hideCandidates, .insert("漢字")], mode: .korean))
}

@Test("선택한 단어를 고르지 않고 끝내면 그 한글을 그대로 확정한다 — ESC, 다른 key, 입력칸 떠나기")
func selectedWordRestored() {
    var cancelled = Session(hanja: dictionary)
    _ = cancelled.handle(optionReturn, mode: .korean, selectedText: { "한자" })
    let escape = cancelled.handle(KeyEvent(keyCode: KeyCode.escape), mode: .korean)
    #expect(escape.actions == [.hideCandidates, .insert("한자")])

    var typed = Session(hanja: dictionary)
    _ = typed.handle(optionReturn, mode: .korean, selectedText: { "한자" })
    let other = typed.handle(key("r"), mode: .korean)
    #expect(other.actions == [.hideCandidates, .insert("한자"), .mark("ㄱ")])

    var left = Session(hanja: dictionary)
    _ = left.handle(optionReturn, mode: .korean, selectedText: { "한자" })
    #expect(left.commit() == [.hideCandidates, .insert("한자")])
}

@Test("terminal 의 선택 영역은 출력이다 — 바꾸지 않고 ⌥↩ 를 넘긴다")
func selectedWordInTerminal() {
    var session = Session(hanja: dictionary)
    let outcome = session.handle(
        optionReturn, mode: .korean, profile: AppProfile(convertsEnteredText: false), selectedText: { "한자" })
    #expect(outcome == Outcome(handled: false, actions: [], mode: .korean))
}

@Test("선택한 한글에 후보가 없어도 ⌥↩ 는 먹는다 — 넘기면 app 이 선택 영역을 줄바꿈으로 바꾼다")
func selectedWithoutCandidates() {
    var session = Session(hanja: dictionary)
    let outcome = session.handle(optionReturn, mode: .korean, selectedText: { "홙홙" })
    #expect(outcome == Outcome(handled: true, actions: [], mode: .korean))
}

@Test("조합도 한글 선택도 없으면 ⌥↩ 는 평소대로 넘긴다", arguments: [nil, "abc", "한a"] as [String?])
func notHanja(selection: String?) {
    var session = Session(hanja: dictionary)
    let outcome = session.handle(optionReturn, mode: .korean, selectedText: { selection })
    #expect(outcome == Outcome(handled: false, actions: [], mode: .korean))
}

@Test("영문 모드의 ⌥↩ 는 한자 변환이 아니다")
func englishOptionReturn() {
    var session = Session(hanja: dictionary)
    let outcome = session.handle(optionReturn, mode: .english, selectedText: { "한자" })
    #expect(outcome == Outcome(handled: false, actions: [], mode: .english))
}

@Test("후보를 고르는 중에 입력칸을 떠나면 창을 닫고 조합은 확정한다")
func commitWhileChoosing() {
    var session = hanjaSession(typing: "gks")
    _ = session.handle(optionReturn, mode: .korean)
    let actions = session.commit()
    #expect(actions == [.hideCandidates, .insert("한")])
}

@Test("app 이 커서 앞 글자에 답하지 않으면(교체를 제대로 받지 않는 client) 조합 중인 글자만")
func committedTextStays() {
    var session = hanjaSession(typing: "gkswk")  // 한 확정, 자 조합 중
    let opened = session.handle(optionReturn, mode: .korean)
    guard case .showCandidates(let list, _) = opened.actions.first, opened.actions.count == 1 else {
        Issue.record("조합 중인 글자의 후보만 열려야 한다: \(opened.actions)")
        return
    }
    #expect(list.first?.hanja == dictionary.candidates(for: "자").first?.hanja)
    #expect(session.composing == "자")
}

@Test("후보가 열린 채 ⌥↩ 를 다시 누르면 그대로 — app 에 넘기지 않는다")
func hanjaKeyAgain() {
    var session = hanjaSession(typing: "gks")
    _ = session.handle(optionReturn, mode: .korean)
    let again = session.handle(optionReturn, mode: .korean)
    #expect(again == Outcome(handled: true, actions: [], mode: .korean))
    let picked = session.handle(digit(1), mode: .korean)
    #expect(picked.actions == [.hideCandidates, .insert("韓")])
}

// MARK: - 방금 친 단어 (Apple 입력기처럼 선택 없이 — 교체를 제대로 받는 client 에서만)

@Test("방금 친 단어 — 조합 중인 글자를 확정하고, 단어를 marked text 로 되돌려 후보를 연다")
func recentWord() {
    var session = hanjaSession(typing: "gkswk")  // 한 확정(10), 자 조합 중(11)
    let opened = session.handle(optionReturn, mode: .korean, textBefore: document("한"))
    #expect(Array(opened.actions.prefix(2)) == [.insert("자"), .markCommitted("한자", range: range(10, 2))])
    #expect(session.composing.isEmpty)
    let picked = choose("漢字", from: opened, &session)
    #expect(picked == Outcome(handled: true, actions: [.hideCandidates, .insert("漢字")], mode: .korean))
}

@Test("사전에 있는 가장 긴 끝부분 — 앞은 두고 확인도 그만큼만 묻는다")
func recentWordLongestSuffix() {
    var session = hanjaSession(typing: "sksmsgkswk")  // 나는한 확정, 자 조합 중
    var asked: [Int] = []
    let ask = document("나는한")
    let opened = session.handle(optionReturn, mode: .korean, textBefore: { asked.append($0); return ask($0) })
    #expect(asked == [1])
    #expect(Array(opened.actions.prefix(2)) == [.insert("자"), .markCommitted("한자", range: range(12, 2))])
}

@Test("app 의 글자가 기억과 다르면 조합 중인 글자만 바꾼다")
func recentWordMismatch() {
    var session = hanjaSession(typing: "gkswk")
    let opened = session.handle(optionReturn, mode: .korean, textBefore: document("가"))
    guard case .showCandidates(let list, _) = opened.actions.first, opened.actions.count == 1 else {
        Issue.record("조합 중인 글자의 후보만 열려야 한다: \(opened.actions)")
        return
    }
    #expect(list.first?.hanja == dictionary.candidates(for: "자").first?.hanja)
    #expect(session.composing == "자")
}

@Test("⌥↩ 를 다시 누르면 더 짧은 단어로, 마지막 다음은 처음으로")
func recentWordCycle() {
    var session = hanjaSession(typing: "gkswk")
    _ = session.handle(optionReturn, mode: .korean, textBefore: document("한"))
    let shorter = session.handle(optionReturn, mode: .korean)
    #expect(Array(shorter.actions.prefix(2)) == [.insert("한자"), .markCommitted("자", range: range(11, 1))])
    let back = session.handle(optionReturn, mode: .korean)
    #expect(Array(back.actions.prefix(2)) == [.insert("자"), .markCommitted("한자", range: range(10, 2))])
}

@Test("고르지 않고 끝내면 되돌린 단어를 그대로 확정한다 — ESC, 다른 key, 입력칸 떠나기")
func recentWordRestored() {
    var cancelled = hanjaSession(typing: "gkswk")
    _ = cancelled.handle(optionReturn, mode: .korean, textBefore: document("한"))
    let escape = cancelled.handle(KeyEvent(keyCode: KeyCode.escape), mode: .korean)
    #expect(escape.actions == [.hideCandidates, .insert("한자")])
    // 다시 ⌥↩ — 조합 중인 글자 없이 커서 앞 단어를 연다
    let again = cancelled.handle(optionReturn, mode: .korean, textBefore: document("한자"))
    #expect(again.actions.first == .markCommitted("한자", range: range(10, 2)))

    var typed = hanjaSession(typing: "gkswk")
    _ = typed.handle(optionReturn, mode: .korean, textBefore: document("한"))
    let other = typed.handle(key("r"), mode: .korean)
    #expect(other.actions == [.hideCandidates, .insert("한자"), .mark("ㄱ")])

    var left = hanjaSession(typing: "gkswk")
    _ = left.handle(optionReturn, mode: .korean, textBefore: document("한"))
    #expect(left.commit() == [.hideCandidates, .insert("한자")])
}

@Test("이미 입력된 글자를 바꾸지 않는 app(terminal·Office)은 조합 중인 글자만 — app 에게 묻지도 않는다")
func recentWordNotConverted() {
    var session = hanjaSession(typing: "gkswk")
    var asked = false
    let opened = session.handle(
        optionReturn, mode: .korean, profile: AppProfile(convertsEnteredText: false),
        textBefore: { _ in asked = true; return nil })
    #expect(!asked)
    #expect(opened.actions.count == 1)
    #expect(session.composing == "자")
}

@Test("넘긴 key(Space 등) 뒤로는 기억이 없다 — 새 단어만")
func recentWordAfterSpace() {
    var session = Session(hanja: dictionary)
    _ = press([key("g"), key("k"), key("s"), space, key("w"), key("k")], &session)  // 한, Space, 자
    var asked = false
    let opened = session.handle(optionReturn, mode: .korean, textBefore: { _ in asked = true; return nil })
    #expect(!asked)
    #expect(opened.actions.count == 1)
}

@Test("Backspace 로 지운 글자는 기억에서도 뺀다")
func recentWordAfterBackspace() {
    var session = hanjaSession(typing: "gkswk")
    _ = press([backspace, backspace], &session)  // 자 → ㅈ → (없음)
    var copy = session
    let opened = copy.handle(optionReturn, mode: .korean, textBefore: document("한"))
    #expect(opened.actions.first == .markCommitted("한", range: range(10, 1)))

    let erased = session.handle(backspace, mode: .korean)  // app 이 "한" 을 지운다
    #expect(!erased.handled)
    let nothing = session.handle(optionReturn, mode: .korean, textBefore: document("한"))
    #expect(nothing == Outcome(handled: false, actions: [], mode: .korean))
}

// MARK: - 한자 key 와 방식 (주인 설정)

@Test("한자 key 가 수식키 tap 이면 ⌥↩ 는 평소대로 넘어가고, tap 이 후보를 연다")
func hanjaKeyTap() {
    let profile = AppProfile(hanjaKey: .rightOption)
    var session = hanjaSession(typing: "gks")  // 한
    let passed = session.handle(optionReturn, mode: .korean, profile: profile)
    #expect(!passed.handled)  // ⌥ 조합은 확정하고 넘긴다

    var tapped = hanjaSession(typing: "gks")
    guard let opened = tapped.hanjaTapped(mode: .korean, profile: profile),
        case .showCandidates(let list, _) = opened.actions.last
    else {
        Issue.record("tap 이 후보를 열어야 한다")
        return
    }
    #expect(list.first?.hanja == "韓")
    #expect(tapped.hanjaTapped(mode: .english, profile: profile) != nil)  // 열린 채 다시 — 먹는다
}

@Test("tap 으로 방금 친 단어 — 다시 tap 하면 더 짧은 단어로")
func hanjaKeyTapCycles() {
    let profile = AppProfile(hanjaKey: .rightCommand)
    var session = hanjaSession(typing: "gkswk")
    let opened = session.hanjaTapped(mode: .korean, profile: profile, textBefore: document("한"))
    #expect(opened?.actions.prefix(2).elementsEqual([.insert("자"), .markCommitted("한자", range: range(10, 2))]) == true)
    let shorter = session.hanjaTapped(mode: .korean, profile: profile)
    #expect(shorter?.actions.prefix(2).elementsEqual([.insert("한자"), .markCommitted("자", range: range(11, 1))]) == true)
}

@Test("영문 모드에서 한자 tap 은 아무 일도 없다")
func hanjaKeyTapInEnglish() {
    var session = Session(hanja: dictionary)
    #expect(session.hanjaTapped(mode: .english, profile: AppProfile(hanjaKey: .rightOption)) == nil)
}

@Test("Apple 방식을 끄면 방금 친 단어를 보지 않는다 — 조합 중인 글자만, app 에게 묻지도 않는다")
func recentWordOff() {
    var session = hanjaSession(typing: "gkswk")
    var asked = false
    let opened = session.handle(
        optionReturn, mode: .korean, profile: AppProfile(hanjaRecentWord: false),
        textBefore: { _ in asked = true; return nil })
    #expect(!asked)
    #expect(opened.actions.count == 1)
    #expect(session.composing == "자")
}
