import Foundation
import HangulCore
@testable import InputSession

import Testing

// Mail 의 recipient 자동완성 — homi 의 insert(앞 음절) → mark(현재 음절) 사이에 문서가 앞 음절만 가진 순간이 있고,
// Mail 은 mark 없는 그 text change 때 prefix 를 얼려 completion 에 쓴다 (docs/apps/mail.md 의 얼린 prefix).
// Mail 에서는 앞 음절과 현재 음절을 함께 넣은 뒤 현재 음절만 그 자리에 다시 mark 해, 중간 순간이 보이는 글자 전체가 되게 한다.

private let mail = AppProfile(insertsWithComposing: true)

// MARK: - Session

@Test("음절 경계에서 앞 음절과 현재 음절을 함께 넣고 현재 음절만 그 자리에 다시 mark 한다 — 경계에서만 묻는다")
func joinedInsertAtBoundary() {
    var session = Session()
    var asked = 0
    var actions: [Action] = []
    for letter in "chlgy" {  // 최효
        actions += session.handle(key(letter), mode: .korean, profile: mail, markedStart: { asked += 1; return 5 }).actions
    }
    #expect(actions == [.mark("ㅊ"), .mark("초"), .mark("최"), .mark("쵷"),
        .insert("최효"), .markCommitted("효", range: NSRange(location: 6, length: 1))])
    #expect(asked == 1)
    #expect(session.composing == "효")
    let next = session.handle(key("s"), mode: .korean, profile: mail, markedStart: { asked += 1; return 5 })
    #expect(next.actions == [.mark("횬")])  // 다시 mark 한 음절은 평소처럼 이어서 조합한다
    #expect(asked == 1)
}

@Test("위치를 모르거나 규칙이 없으면 평소대로 — 규칙이 없으면 묻지도 않는다", arguments: ["unknown", "noRule"])
func joinedInsertFallback(scenario: String) {
    var session = Session()
    var asked = 0
    let profile = scenario == "noRule" ? AppProfile() : mail
    var actions: [Action] = []
    for letter in "rksk" {  // 가나
        actions += session.handle(key(letter), mode: .korean, profile: profile, markedStart: { asked += 1; return nil }).actions
    }
    #expect(actions.suffix(2) == [.insert("가"), .mark("나")])
    #expect(asked == (scenario == "noRule" ? 0 : 1))
}

@Test("함께 넣은 뒤에도 방금 친 단어의 기억은 같다 — ⌥↩ 가 같은 단어를 본다")
func joinedInsertKeepsRecentWord() {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("homi-joined-\(UUID().uuidString).txt")
    defer { try? FileManager.default.removeItem(at: url) }
    try! "한자:漢字:한나라의 글자\n".write(to: url, atomically: true, encoding: .utf8)
    var session = Session(hanja: try! HanjaDictionary(contentsOf: url))
    for letter in "gkswk" {  // 한자 — 한 확정, 자 조합 중
        _ = session.handle(key(letter), mode: .korean, profile: mail, markedStart: { 0 })
    }
    var preceding: [Int] = []
    let outcome = session.handle(KeyEvent(keyCode: KeyCode.returnKey, modifiers: .option), mode: .korean, profile: mail,
        textBefore: { count in preceding.append(count); return ("한", 1) })
    #expect(preceding == [1])
    #expect(outcome.handled && session.hasCandidates)
    #expect(outcome.actions.prefix(2) == [.insert("자"), .markCommitted("한자", range: NSRange(location: 0, length: 2))])
}

// MARK: - coordinator 와 Mail 문서 모델

private final class Modes: ModeStore {
    var memory = ModeMemory(modes: ["mail.tests": .korean])
    func withMemory<Result: Sendable>(_ operation: (inout ModeMemory) -> Result) -> Result { operation(&memory) }
    func save(_ snapshot: ModeMemory) {}
}

/// NSTextView 처럼 selection·marked text 를 가진 recipient 칸. 위치 없는 insert·mark 는 marked text 를, 없으면 selection 을 대신한다.
/// Mail 의 가설을 넣었다 — mark 없는 text change 때 caret 까지를 prefix 로 저장하고, completion 은 대기 시작 때 얼린 그 prefix 로
/// 결과의 첫 후보를 채우거나(꼬리를 선택), 결과가 없으면 prefix 로 되돌린다. 실제 Mail 구현의 확정이 아니다.
private final class Recipient: InputClient {
    let driver = SessionDriver()
    let modes = Modes()
    var profile: AppProfile
    lazy var coordinator = InputCoordinator(driver: driver, modes: modes, profile: { [unowned self] _ in self.profile },
        fallbackApp: { "mail.tests" })
    var text = ""
    var selection = NSRange(location: 0, length: 0)
    var marked: NSRange?
    var savedPrefix = NSRange(location: 0, length: 0)
    /// `validAttributesForMarkedText` 에 교체 범위와 받아쓰기 대안을 알리는 text engine — 아니면 위치를 답하지 않는다.
    var textEngine = true
    var markedQueries = 0
    var explicitMarks = 0
    var onMarkedQuery: (() -> Void)?
    /// Mail 의 관측 (docs/apps/mail.md 2026-11-01 14:13) — 위치를 준 mark 뒤 `markedRange` 를 그때의 caret 으로 답하고,
    /// 제자리 mark 동안 그 값을 유지한다. 화면의 반영은 맞다. insert 가 지우고, 새 mark 는 그 자리로 다시 잡는다.
    var reportsMailMarkedRange = false
    private var reportedStart: Int?

    init(profile: AppProfile) { self.profile = profile }

    func bundleIdentifier() -> String? { "mail.tests" }
    func selectedText() -> String? { nil }
    func textBefore(_ count: Int) -> (text: String, end: Int)? { nil }
    func markedStart(while isCurrent: () -> Bool) -> Int? {
        markedQueries += 1
        let callback = onMarkedQuery
        onMarkedQuery = nil
        callback?()
        guard isCurrent(), textEngine, let marked else { return nil }
        return reportsMailMarkedRange ? reportedStart : marked.location
    }
    func apply(_ actions: [Action]) {
        driver.submission.withActions(actions) {
            for action in actions {
                driver.submission.willApply(action)
                switch action {
                case .mark(let value):
                    if marked == nil { reportedStart = selection.location }
                    replace(marked ?? selection, with: value, marking: true)
                    if marked == nil { reportedStart = nil }
                case .markCommitted(let value, let range):
                    explicitMarks += 1
                    reportedStart = selection.location
                    replace(range, with: value, marking: true)
                case .insert(let value):
                    reportedStart = nil
                    replace(marked ?? selection, with: value, marking: false)
                default: break
                }
            }
        }
    }
    private func replace(_ requested: NSRange, with value: String, marking: Bool) {
        // 문서 밖의 범위는 끝으로 자른다 — Mail 은 `{3,1}` 을 길이 3 문서의 끝에 붙였다 (docs/apps/mail.md 2026-11-01 14:13).
        let length = (text as NSString).length
        let location = min(requested.location, length)
        let target = NSRange(location: location, length: min(requested.length, length - location))
        text = (text as NSString).replacingCharacters(in: target, with: value)
        let inserted = (value as NSString).length
        marked = marking && inserted > 0 ? NSRange(location: target.location, length: inserted) : nil
        selection = NSRange(location: target.location + inserted, length: 0)
        if marked == nil { savedPrefix = NSRange(location: 0, length: selection.location) }
    }
    var markedText: String { marked.map { (text as NSString).substring(with: $0) } ?? "" }

    /// 대기 — Mail 이 조합을 끝내고(event 밖의 commitComposition) 얼린 prefix 로 completion 한다.
    func pause(results: [String: [String]]) {
        let frozen = savedPrefix
        let prefix = (text as NSString).substring(with: frozen)
        driver.end(.commitToClient, apply: apply)
        let caret = selection.location
        let replaced = NSRange(location: frozen.location, length: caret - frozen.location)
        if let candidate = results[prefix]?.first {
            text = (text as NSString).replacingCharacters(in: replaced, with: candidate)
            selection = NSRange(location: NSMaxRange(frozen), length: (candidate as NSString).length - frozen.length)
        } else {
            text = (text as NSString).replacingCharacters(in: replaced, with: prefix)
            selection = NSRange(location: NSMaxRange(frozen), length: 0)
        }
        marked = nil
    }
    @discardableResult func press(_ letter: Character) -> Outcome { coordinator.keyDown(key(letter), client: self) }
    func type(_ letters: String) { for letter in letters { press(letter) } }
}

@Test("재현: 규칙이 없으면 얼린 prefix 가 한 음절 짧아 주인이 본 세 누락이 그대로 나온다")
func recipientWithoutRuleLosesSyllables() {
    let first = Recipient(profile: AppProfile())
    first.type("rksk")  // 가나
    first.pause(results: ["가": ["가족"]])
    #expect(first.text == "가족" && first.selection == NSRange(location: 1, length: 1))
    first.type("ek")
    #expect(first.text == "가다")

    let second = Recipient(profile: AppProfile())
    second.type("chlgy")  // 최효
    second.pause(results: ["최": ["최효주"]])
    #expect(second.text == "최효주" && second.selection == NSRange(location: 1, length: 2))

    let third = Recipient(profile: AppProfile())
    third.type("chlgywn")  // 최효주
    third.pause(results: [:])
    #expect(third.text == "최효")
    #expect(first.explicitMarks + second.explicitMarks + third.explicitMarks == 0)
}

@Test("Mail 규칙: 얼린 prefix 가 보이는 글자 전체라 completion 이 음절을 지우지 않는다")
func recipientWithRuleKeepsSyllables() {
    let first = Recipient(profile: mail)
    first.type("rksk")  // 가나
    first.pause(results: ["가": ["가족"]])  // `가나` 로 검색하니 `가` 의 결과는 쓰이지 않는다
    #expect(first.text == "가나")
    first.type("ek")
    #expect(first.text == "가나다" && first.markedText == "다")

    let filled = Recipient(profile: mail)
    filled.type("rksk")
    filled.pause(results: ["가나": ["가나라"]])
    #expect(filled.text == "가나라" && filled.selection == NSRange(location: 2, length: 1))
    filled.type("ek")
    #expect(filled.text == "가나다")

    let second = Recipient(profile: mail)
    second.type("chlgy")  // 최효 — Apple 입력기처럼 `최효` 로 검색해 결과가 없다
    second.pause(results: ["최": ["최효주"]])
    #expect(second.text == "최효")

    let third = Recipient(profile: mail)
    third.type("chlgywn")  // 최효주
    third.pause(results: [:])
    #expect(third.text == "최효주")
    #expect(third.explicitMarks == 2 && third.markedQueries == 1)  // 둘째 경계는 기억한 위치를 쓴다
}

@Test("Mail 규칙: 받침·도깨비불·Backspace 의 매 단계가 규칙 없는 app 과 같다")
func recipientEditingMatchesPlain() {
    let plain = Recipient(profile: AppProfile())
    let rule = Recipient(profile: mail)
    let keys: [KeyEvent] = "rkskek".map { key($0) } + [backspace, backspace, key("s"), key("k"), backspace, backspace, backspace]
    for (index, event) in keys.enumerated() {
        let expected = plain.coordinator.keyDown(event, client: plain)
        let outcome = rule.coordinator.keyDown(event, client: rule)
        #expect(outcome.handled == expected.handled, "key \(index)")
        #expect(rule.text == plain.text && rule.marked == plain.marked && rule.selection == plain.selection, "key \(index): \(rule.text) vs \(plain.text)")
        #expect(rule.driver.composing == plain.driver.composing, "key \(index)")
    }
    #expect(rule.explicitMarks > 0)
}

@Test("Mail 규칙: text engine 이 아니면 위치를 묻기만 하고 평소대로 넣는다")
func recipientNotTextEngineFallsBack() {
    let host = Recipient(profile: mail)
    host.textEngine = false
    host.type("rksk")
    #expect(host.text == "가나" && host.markedText == "나")
    #expect(host.markedQueries == 1 && host.explicitMarks == 0)
}

@Test("Mail 규칙: 위치 질의 중 중첩 key 는 Session 충돌 없이 처리되고 바깥 key 도 평소대로 넣는다")
func recipientNestedKeyDuringQuery() {
    let host = Recipient(profile: mail)
    host.type("rks")  // 간
    host.onMarkedQuery = {
        #expect(!host.driver.isMutatingSession)
        guard !host.driver.isMutatingSession else { return }
        #expect(host.press("e").handled)  // ㄷ — 중첩
    }
    let outcome = host.press("k")  // ㅏ — 바깥
    #expect(outcome.handled)
    // 중첩한 ㄷ 이 먼저 처리되고 바깥 ㅏ 는 중단 뒤 위치 없이 이어진다 — 두 key 가 남고 문서와 조합이 일치한다.
    // 순서가 바뀌는 것은 일반 key 재진입의 남은 반례와 같은 종류다 (docs/stability-review.md).
    #expect(host.text == "간다" && host.markedText == "다")
    #expect(host.driver.composing == "다")
}

@Test("Mail 규칙: 위치 질의 중 client 의 확정 요청이 오면 명시적 위치를 쓰지 않고 경계 끝에 확정한다")
func recipientCommitDuringQuery() {
    let host = Recipient(profile: mail)
    host.type("rks")  // 간
    host.onMarkedQuery = { host.driver.end(.commitToClient, apply: host.apply) }
    let outcome = host.press("k")  // ㅏ
    #expect(outcome.handled)
    #expect(host.text == "가나" && host.marked == nil)
    #expect(host.driver.composing.isEmpty)
    #expect(host.explicitMarks == 0)
}


// MARK: - Mail 의 markedRange 응답

@Test("다시 mark 한 위치는 homi 가 기억한다 — 같은 조합의 다음 경계는 묻지 않는다")
func joinedInsertRemembersStart() {
    var session = Session()
    var answers = [0, 2]  // 둘째 답은 Mail 처럼 한 음절 뒤 — 쓰이면 안 된다
    var actions: [Action] = []
    for letter in "chlgywn" {  // 최효주
        actions += session.handle(key(letter), mode: .korean, profile: mail, markedStart: { answers.removeFirst() }).actions
    }
    #expect(answers == [2])
    #expect(actions.suffix(2) == [.insert("효주"), .markCommitted("주", range: NSRange(location: 2, length: 1))])
}

@Test("제자리에서 고치는 Backspace 뒤에도 기억한 위치를 쓴다")
func joinedInsertRemembersThroughBackspace() {
    var session = Session()
    var asked = 0
    for event in "chlgy".map({ key($0) }) + [backspace, key("y"), key("w"), key("n")] {  // 최효 → 최ㅎ → 최효 → 최효주
        _ = session.handle(event, mode: .korean, profile: mail, markedStart: { asked += 1; return 0 })
    }
    #expect(asked == 1)
    #expect(session.composing == "주")
}

@Test("기억한 위치는 같은 mark 가 끝나면 버린다 — 다음 조합의 첫 경계는 다시 묻는다",
    arguments: ["commit", "emptied", "space", "plainBoundary", "toggle"])
func joinedInsertForgetsStart(scenario: String) {
    var session = Session()
    var asked = 0
    let answer: () -> Int? = { asked += 1; return scenario == "plainBoundary" && asked == 1 ? nil : 0 }
    for letter in "rksk" { _ = session.handle(key(letter), mode: .korean, profile: mail, markedStart: answer) }  // 가나
    switch scenario {
    case "commit": _ = session.commit()
    case "emptied": _ = session.handle(backspace, mode: .korean, profile: mail); _ = session.handle(backspace, mode: .korean, profile: mail)
    case "space": _ = session.handle(space, mode: .korean, profile: mail)
    case "toggle": _ = session.toggle(from: .korean, profile: mail)
    default: break  // 첫 경계에서 위치를 몰라 평소대로 넣었다
    }
    for letter in "ekek" { _ = session.handle(key(letter), mode: .korean, profile: mail, markedStart: answer) }  // 다다
    #expect(asked == 2)
}

@Test("Mail 의 markedRange 응답을 흉내 내도 둘째 경계부터 음절이 겹치지 않는다 — 주인 관측의 재현")
func recipientMailMarkedRangeKeepsSyllables() {
    // 결과가 없는 대기에는 Mail 이 아무것도 보내지 않았다 (trace 14:13 — 대기 중 commitComposition 없음). 그래서 event 없이 이어 친다.
    let paused = Recipient(profile: mail)
    paused.reportsMailMarkedRange = true
    paused.type("rksk")  // 가나
    paused.type("ek")  // 다
    #expect(paused.text == "가나다" && paused.markedText == "다")

    let straight = Recipient(profile: mail)
    straight.reportsMailMarkedRange = true
    straight.type("chlgywn")  // 최효주
    #expect(straight.text == "최효주" && straight.markedText == "주")
    #expect(straight.markedQueries == 1 && straight.explicitMarks == 2)
}

@Test("Mail 규칙: 종료 요청이 기다리는 중의 음절 경계는 기억한 위치도 쓰지 않고 평소대로 넣는다")
func recipientPendingEndDisablesJoin() {
    let host = Recipient(profile: mail)
    host.type("chlgyw")  // 최횾 — 첫 경계에서 위치를 기억했다
    #expect(host.explicitMarks == 1 && host.markedText == "횾")
    let outcome = host.driver.withEvent { () -> Outcome in
        host.driver.end(.commitToClient, apply: host.apply)  // 같은 event 안에서 기다리는 종료 — client 가 문서를 바꿨을 수 있다
        return host.press("n")  // ㅜ — 음절 경계
    }
    #expect(outcome.handled)
    #expect(host.explicitMarks == 1)
    #expect(host.text == "최효주" && host.marked == nil)
    #expect(host.driver.composing.isEmpty)
}
