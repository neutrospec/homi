import Foundation
import HangulCore
@testable import InputSession

import Testing

private let preparedDictionary: HanjaDictionary = {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("homi-prepared-\(UUID().uuidString).txt")
    defer { try? FileManager.default.removeItem(at: url) }
    try! "가:家:집\n한:韓:나라\n한가:閑暇:틈\n".write(to: url, atomically: true, encoding: .utf8)
    return try! HanjaDictionary(contentsOf: url)
}()

private final class PreparedModes: ModeStore {
    var memory = ModeMemory(modes: ["prepared.tests": .korean])
    func withMemory<Result: Sendable>(_ operation: (inout ModeMemory) -> Result) -> Result { operation(&memory) }
    func save(_ snapshot: ModeMemory) {}
}

private final class PreparedHost: InputClient {
    let driver = SessionDriver(hanja: preparedDictionary)
    let modes: PreparedModes
    init(modes: PreparedModes = PreparedModes()) { self.modes = modes }
    lazy var coordinator = InputCoordinator(driver: driver, modes: modes, profile: { [unowned self] _ in self.profile }, fallbackApp: { "prepared.tests" })
    var text = "", marked = ""
    var profile = AppProfile()
    var selected: String? = "한"
    var preceding: (text: String, end: Int)?
    var onBefore: (() -> Void)?
    var beforeQueries = 0
    var actions: [Action] = []
    var onSelected: (() -> Void)?
    var selectedQueries = 0
    func bundleIdentifier() -> String? { "prepared.tests" }
    func selectedText() -> String? {
        selectedQueries += 1
        let callback = onSelected; onSelected = nil; callback?()
        return selected
    }
    func textBefore(_ count: Int) -> (text: String, end: Int)? {
        beforeQueries += 1
        let callback = onBefore; onBefore = nil; callback?()
        return preceding
    }
    func apply(_ actions: [Action]) {
        self.actions += actions
        driver.submission.withActions(actions) {
            for action in actions {
                driver.submission.willApply(action)
                switch action {
                case .mark(let text): marked = text
                case .insert(let value): text += value; marked = ""
                default: break
                }
            }
        }
    }
    @discardableResult func key(_ code: UInt16, _ modifiers: Modifiers = []) -> Outcome {
        coordinator.keyDown(KeyEvent(keyCode: code, modifiers: modifiers), client: self)
    }
}

@Test("한자 선택 질의 중 중첩 key 는 Session 접근 충돌 없이 새 입력을 보존한다")
func preparedSelectionNestedKey() {
    let host = PreparedHost()
    host.onSelected = {
        #expect(!host.driver.isMutatingSession)
        // 이전 구현은 Session 의 inout 안이므로 nested key 를 실행하면 suite process 가 종료된다.
        guard !host.driver.isMutatingSession else { return }
        #expect(host.key(5).handled)
    }
    let result = host.key(KeyCode.returnKey, .option)
    #expect(host.selectedQueries == 1)
    #expect(result.handled)
    #expect(host.marked == "ㅎ")
    #expect(host.driver.composing == "ㅎ")
    #expect(!host.driver.hasCandidates)
}

@Test("한자 준비: 중단 없는 질의와 결과는 기존 Session 과 같다", arguments: ["selection", "nil", "noCandidate", "composing", "recent", "passThrough", "recentNilSelected", "recentMismatchNil"])
func preparedMatchesSession(scenario: String) {
    let host = PreparedHost()
    var original = Session(hanja: preparedDictionary)
    if scenario == "passThrough" { host.profile = AppProfile(passThrough: true) }
    if scenario == "nil" { host.selected = nil }
    if scenario == "noCandidate" { host.selected = "홙" }
    let emptyRecent = scenario == "recentNilSelected" || scenario == "recentMismatchNil"
    let keys: [UInt16] = scenario == "composing" ? [5, 40, 1] : scenario == "recent" ? [5, 40, 1, 15, 40] : emptyRecent ? [5, 40, 1, 15, KeyCode.delete] : []
    for code in keys {
        _ = original.handle(KeyEvent(keyCode: code), mode: .korean, profile: host.profile)
        _ = host.key(code)
    }
    if scenario == "recent" { host.preceding = ("한", 1) }
    if scenario == "recentMismatchNil" { host.preceding = ("가", 1); host.selected = nil }
    if emptyRecent { #expect(host.driver.composing.isEmpty) }
    host.actions = []
    var selectedCount = 0, beforeCount = 0
    let expected = original.handle(KeyEvent(keyCode: KeyCode.returnKey, modifiers: .option), mode: .korean,
        profile: host.profile, selectedText: { selectedCount += 1; return host.selected },
        textBefore: { _ in beforeCount += 1; return host.preceding })
    let actual = host.key(KeyCode.returnKey, .option)
    #expect(actual == expected)
    #expect(host.actions == expected.actions)
    #expect(host.selectedQueries == selectedCount)
    #expect(host.beforeQueries == beforeCount)
    if emptyRecent { #expect(host.beforeQueries == 1 && host.selectedQueries == 1) }
    #expect(host.driver.composing == original.composing)
    #expect(host.driver.hasCandidates == original.hasCandidates)
    #expect(host.modes.memory.mode(for: "prepared.tests") == expected.mode)
}

@Test("한자 준비: modifier tap 질의도 중첩 key 뒤 이전 후보를 열지 않는다")
func preparedModifierNestedKey() {
    let host = PreparedHost()
    host.onSelected = {
        #expect(!host.driver.isMutatingSession)
        guard !host.driver.isMutatingSession else { return }
        #expect(host.key(5).handled)
    }
    host.coordinator.modifiersChanged(client: host, action: { _, _ in .hanja })
    #expect(host.selectedQueries == 1)
    #expect(host.marked == "ㅎ")
    #expect(host.driver.composing == "ㅎ")
    #expect(!host.driver.hasCandidates)
}

@Test("한자 준비: 질의 중 mode 전환은 이전 proposal 이 되돌리지 않는다")
func preparedNestedToggle() {
    let host = PreparedHost()
    host.onSelected = {
        #expect(!host.driver.isMutatingSession)
        guard !host.driver.isMutatingSession else { return }
        host.coordinator.modifiersChanged(client: host, action: { _, _ in .toggle })
    }
    var afterModeChanged: Bool?
    let result = host.coordinator.keyDown(KeyEvent(keyCode: KeyCode.returnKey, modifiers: .option), client: host,
        after: { _, changed in afterModeChanged = changed })
    #expect(result.handled && result.mode == .english && !result.resend && result.actions.isEmpty)
    #expect(afterModeChanged == false)
    #expect(host.modes.memory.mode(for: "prepared.tests") == .english)
    #expect(!host.driver.hasCandidates)
}

@Test("한자 준비: 종료와 그 뒤 새 key 는 지연 종료의 기존 의미로 한 번만 보존한다", arguments: ["commit", "deactivateActivate", "source", "confirmed"])
func preparedLifecycleAndKey(ending: String) {
    let host = PreparedHost()
    host.onSelected = {
        #expect(!host.driver.isMutatingSession)
        guard !host.driver.isMutatingSession else { return }
        switch ending {
        case "commit": host.driver.end(.commitToClient, apply: host.apply)
        case "deactivateActivate": host.driver.deactivate(apply: host.apply); _ = host.coordinator.activate()
        case "source": host.driver.sourceChanged(selected: false, apply: host.apply)
        default: host.driver.end(.alreadyCommittedByClient, apply: host.apply)
        }
        #expect(host.key(5).handled)
    }
    let result = host.key(KeyCode.returnKey, .option)
    #expect(result.handled)
    #expect(host.text + host.marked == "ㅎ")
    #expect(host.marked == host.driver.composing)
    #expect(!host.driver.hasCandidates)
    host.driver.end(.commitToClient, apply: host.apply)
    host.driver.end(.commitToClient, apply: host.apply)
    #expect(host.text == "ㅎ" && host.marked.isEmpty)
}

@Test("한자 준비: modifier tap 의 일반 결과와 질의 횟수는 기존 Session 과 같다", arguments: ["selection", "nil", "noCandidate", "composing", "recent", "passThrough", "recentNilSelected", "recentMismatchNil"])
func preparedModifierMatchesSession(scenario: String) {
    let host = PreparedHost()
    var original = Session(hanja: preparedDictionary)
    if scenario == "passThrough" { host.profile = AppProfile(passThrough: true) }
    if scenario == "nil" { host.selected = nil }
    if scenario == "noCandidate" { host.selected = "홙" }
    let emptyRecent = scenario == "recentNilSelected" || scenario == "recentMismatchNil"
    let keys: [UInt16] = scenario == "composing" ? [5, 40, 1] : scenario == "recent" ? [5, 40, 1, 15, 40] : emptyRecent ? [5, 40, 1, 15, KeyCode.delete] : []
    for code in keys {
        _ = original.handle(KeyEvent(keyCode: code), mode: .korean, profile: host.profile)
        _ = host.key(code)
    }
    if scenario == "recent" { host.preceding = ("한", 1) }
    if scenario == "recentMismatchNil" { host.preceding = ("가", 1); host.selected = nil }
    if emptyRecent { #expect(host.driver.composing.isEmpty) }
    host.actions = []
    var selectedCount = 0, beforeCount = 0
    let expected = original.hanjaTapped(mode: .korean, profile: host.profile,
        selectedText: { selectedCount += 1; return host.selected },
        textBefore: { _ in beforeCount += 1; return host.preceding })
    host.coordinator.modifiersChanged(client: host, action: { _, _ in .hanja })
    #expect(host.actions == (expected?.actions ?? []))
    #expect(host.selectedQueries == selectedCount && host.beforeQueries == beforeCount)
    if emptyRecent { #expect(host.beforeQueries == 1 && host.selectedQueries == 1) }
    #expect(host.driver.composing == original.composing)
    #expect(host.driver.hasCandidates == original.hasCandidates)
    #expect(host.modes.memory.mode(for: "prepared.tests") == .korean)
}

@Test("한자 준비: 문서 앞 질의 중 nested key 는 이전 변환을 취소한다")
func preparedPrecedingNestedKey() {
    let host = PreparedHost()
    for code: UInt16 in [5, 40, 1, 15, 40] { _ = host.key(code) } // 한 + 가
    host.preceding = ("한", 1)
    host.onBefore = {
        #expect(!host.driver.isMutatingSession)
        guard !host.driver.isMutatingSession else { return }
        #expect(host.key(1).handled) // 가 → 간
    }
    let outcome = host.key(KeyCode.returnKey, .option)
    #expect(outcome.handled)
    #expect(host.beforeQueries == 1 && host.selectedQueries == 0)
    #expect(host.text == "한" && host.marked == "간")
    #expect(host.driver.composing == "간" && !host.driver.hasCandidates)
}

@Test("한자 준비: 질의 중 pass-through key 도 이전 변환을 취소한다")
func preparedNestedPassThrough() {
    let host = PreparedHost()
    var nested: Outcome?
    host.onSelected = {
        #expect(!host.driver.isMutatingSession)
        guard !host.driver.isMutatingSession else { return }
        nested = host.key(0, .option)
    }
    let outcome = host.key(KeyCode.returnKey, .option)
    #expect(nested?.handled == false)
    #expect(outcome.handled && outcome.actions.isEmpty)
    #expect(!host.driver.hasCandidates && host.marked.isEmpty)
}

@Test("한자 준비: 질의 중 새 한자 요청이 연 후보를 이전 요청이 덮지 않는다")
func preparedNestedHanja() {
    let host = PreparedHost()
    host.onSelected = {
        #expect(!host.driver.isMutatingSession)
        guard !host.driver.isMutatingSession else { return }
        #expect(host.key(KeyCode.returnKey, .option).handled)
    }
    let outcome = host.key(KeyCode.returnKey, .option)
    #expect(outcome.handled && outcome.actions.isEmpty)
    #expect(host.selectedQueries == 2)
    #expect(host.driver.hasCandidates && host.marked == "한")
    #expect(host.actions.filter { if case .showCandidates = $0 { true } else { false } }.count == 1)
}

@Test("한자 준비: client 질의에서 받은 검사 함수는 nested 전이 직후 false 다")
func preparedCurrentPredicate() {
    let host = PreparedHost()
    var before = false, after = true
    let result = host.driver.performPrepared({ session, selected, preceding, _ in
        session.handle(KeyEvent(keyCode: KeyCode.returnKey, modifiers: .option), mode: .korean,
            selectedText: selected, textBefore: preceding)
    }, selectedText: { current in
        before = current()
        _ = host.key(5)
        after = current()
        return "한"
    }, textBefore: { _, _ in nil })
    if case .interrupted = result {} else { Issue.record("중첩 입력 뒤 이전 proposal 을 버려야 한다") }
    #expect(before && !after)
    #expect(host.driver.composing == "ㅎ" && host.marked == "ㅎ")
}

@Test("한자 준비: 중첩 입력 없는 lifecycle 은 종전과 같이 제안을 반영하고 종료한다", arguments: ["commit", "deactivateActivate", "source"])
func preparedLifecycleOnly(ending: String) {
    let host = PreparedHost()
    host.onSelected = {
        #expect(!host.driver.isMutatingSession)
        switch ending {
        case "commit": host.driver.end(.commitToClient, apply: host.apply)
        case "deactivateActivate": host.driver.deactivate(apply: host.apply); _ = host.coordinator.activate()
        default: host.driver.sourceChanged(selected: false, apply: host.apply)
        }
    }
    let result = host.key(KeyCode.returnKey, .option)
    #expect(result.handled)
    if ending == "deactivateActivate" {
        #expect(host.driver.hasCandidates && host.marked == "한")
    } else {
        #expect(!host.driver.hasCandidates && host.text == "한" && host.marked.isEmpty)
    }
}

@Test("한자 준비: 다른 controller 가 공유 mode 를 바꾸면 이전 변환을 취소한다", arguments: [false, true])
func preparedOtherControllerToggle(modifier: Bool) {
    let modes = PreparedModes()
    let first = PreparedHost(modes: modes)
    let second = PreparedHost(modes: modes)
    first.onSelected = {
        #expect(!first.driver.isMutatingSession)
        second.coordinator.modifiersChanged(client: second, action: { _, _ in .toggle })
        #expect(modes.memory.mode(for: "prepared.tests") == .english)
    }
    if modifier {
        first.coordinator.modifiersChanged(client: first, action: { _, _ in .hanja })
    } else {
        let outcome = first.key(KeyCode.returnKey, .option)
        #expect(outcome.handled && outcome.mode == .english && outcome.actions.isEmpty)
    }
    #expect(first.selectedQueries == 1)
    #expect(!first.driver.hasCandidates && first.marked.isEmpty)
    #expect(modes.memory.mode(for: "prepared.tests") == .english)
}
