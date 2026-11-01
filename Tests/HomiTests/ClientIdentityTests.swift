import AppKit
import InputMethodKit
import InputSession
import Testing

@testable import homi

private nonisolated final class IdentityModes: ModeStore {
    var memory: ModeMemory
    var saved: [ModeMemory] = []
    init(actual: Mode, fallback: Mode) { memory = ModeMemory(modes: ["actual.app": actual, "fallback.app": fallback]) }
    func withMemory<Result: Sendable>(_ operation: (inout ModeMemory) -> Result) -> Result { operation(&memory) }
    func save(_ snapshot: ModeMemory) { saved.append(snapshot) }
}

private nonisolated final class IdentityProxy: NSObject, IMKTextInput {
    var idQueries = 0
    var onFirstQuery: (() -> Void)?
    var firstAnswer: String?
    var subsequentAnswer: String? = "actual.app"
    var text = "", marked = ""
    func bundleIdentifier() -> String? {
        idQueries += 1
        if idQueries == 1 { onFirstQuery?(); return firstAnswer }
        return subsequentAnswer
    }
    func insertText(_ value: Any?, replacementRange: NSRange) { text += value as? String ?? ""; marked = "" }
    func setMarkedText(_ value: Any?, selectionRange: NSRange, replacementRange: NSRange) { marked = value as? String ?? "" }
    func selectedRange() -> NSRange { NSRange(location: NSNotFound, length: NSNotFound) }
    func markedRange() -> NSRange { NSRange(location: NSNotFound, length: NSNotFound) }
    func attributedSubstring(from range: NSRange) -> NSAttributedString? { nil }
    func length() -> Int { NSNotFound }
    func characterIndex(for point: NSPoint, tracking: IMKLocationToOffsetMappingMode, inMarkedRange: UnsafeMutablePointer<ObjCBool>?) -> Int { NSNotFound }
    func attributes(forCharacterIndex index: Int, lineHeightRectangle: UnsafeMutablePointer<NSRect>?) -> [AnyHashable: Any]? { nil }
    func validAttributesForMarkedText() -> [Any]? { [] }
    func overrideKeyboard(withKeyboardNamed keyboard: String?) {}
    func selectMode(_ mode: String?) {}
    func supportsUnicode() -> Bool { true }
    func windowLevel() -> CGWindowLevel { 0 }
    func supportsProperty(_ property: TSMDocumentPropertyTag) -> Bool { false }
    func uniqueClientIdentifierString() -> String? { nil }
    func string(from range: NSRange, actualRange: NSRangePointer?) -> String? { nil }
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect { .zero }
}

private nonisolated final class IdentityHost {
    let driver = SessionDriver()
    let modes: IdentityModes
    let proxy = IdentityProxy()
    let startsInEnglish: Bool
    var fallbackCalls = 0
    lazy var client = Client(proxy: proxy, trace: driver.clientTrace, submission: driver.submission)
    lazy var coordinator = InputCoordinator(driver: driver, modes: modes,
        profile: { [startsInEnglish] id in AppProfile(startsInEnglish: startsInEnglish && id == "actual.app") },
        fallbackApp: { [unowned self] in self.fallbackCalls += 1; return "fallback.app" })
    init(actual: Mode, fallback: Mode, startsInEnglish: Bool = false) {
        modes = IdentityModes(actual: actual, fallback: fallback)
        self.startsInEnglish = startsInEnglish
    }
    func key(_ code: UInt16) -> Outcome { coordinator.keyDown(KeyEvent(keyCode: code), client: client) }
}

@Test("ID 출처: 동일 proxy 가 중첩 질의에서 확인한 ID 를 nil·빈 답에도 이어 쓴다",
    arguments: [false, true] as [Bool], [nil, ""] as [String?])
func clientIdentitySameProxy(reverse: Bool, empty: String?) {
    let host = IdentityHost(actual: reverse ? .english : .korean, fallback: reverse ? .korean : .english)
    host.proxy.firstAnswer = empty
    var nested: Outcome?
    host.proxy.onFirstQuery = { nested = host.key(5) }
    let outer = host.key(15)
    #expect(host.proxy.idQueries == 2 && host.fallbackCalls == 0)
    #expect(host.coordinator.clientApp?.bundleID == "actual.app")
    #expect(nested?.handled == !reverse && outer.handled == !reverse)
    #expect(outer.mode == (reverse ? .english : .korean))
    #expect(host.proxy.text == (reverse ? "" : "ㅎ"))
    #expect(host.driver.composing == (reverse ? "" : "ㄱ"))
    #expect(host.proxy.marked == host.driver.composing)
}

@Test("ID 출처: 다른 proxy 가 확인한 ID 는 바깥 nil 질의의 fallback 대신 쓰지 않는다")
func clientIdentityDifferentProxy() {
    let host = IdentityHost(actual: .english, fallback: .korean)
    let other = IdentityProxy()
    other.firstAnswer = "actual.app"
    let otherClient = Client(proxy: other, trace: host.driver.clientTrace, submission: host.driver.submission)
    host.proxy.onFirstQuery = { _ = host.coordinator.keyDown(KeyEvent(keyCode: 5), client: otherClient) }
    let outer = host.key(15)
    #expect(host.fallbackCalls == 1 && host.proxy.idQueries == 1 && other.idQueries == 1)
    #expect(outer.handled && outer.mode == .korean && host.proxy.marked == "ㄱ")
}

@Test("ID 출처: 실제 영문 시작 뒤 중첩 전환한 한글을 바깥 질의가 되돌리지 않는다")
func clientIdentityStartingRule() {
    let host = IdentityHost(actual: .korean, fallback: .english, startsInEnglish: true)
    host.proxy.onFirstQuery = {
        host.coordinator.modifiersChanged(client: host.client, action: { _, _ in .toggle })
    }
    let outer = host.key(5)
    #expect(host.proxy.idQueries == 2 && host.fallbackCalls == 0)
    #expect(outer.handled && outer.mode == .korean && host.proxy.marked == "ㅎ")
    #expect(host.modes.memory.mode(for: "actual.app") == .korean)
    #expect(host.modes.saved.count == 2) // 시작 영문, 사용자의 한글 전환
}

/// 출처를 제공하지 않는 기존 InputClient 도 fallback 동작을 유지한다.
private nonisolated final class IdentityNoSourceClient: InputClient {
    var answer: String?
    var onQuery: (() -> Void)?
    var text = "", marked = ""
    func bundleIdentifier() -> String? {
        let value = answer
        let callback = onQuery; onQuery = nil; callback?()
        return value
    }
    func selectedText() -> String? { nil }
    func textBefore(_ count: Int) -> (text: String, end: Int)? { nil }
    func apply(_ actions: [Action]) {
        for action in actions {
            switch action {
            case .insert(let value): text += value; marked = ""
            case .mark(let value): marked = value
            default: break
            }
        }
    }
}

@Test("ID 출처: 출처를 제공하지 않는 client 는 중첩 ID 뒤에도 기존 fallback 을 쓴다")
func clientIdentityDefaultNil() {
    let driver = SessionDriver()
    let modes = IdentityModes(actual: .english, fallback: .korean)
    let coordinator = InputCoordinator(driver: driver, modes: modes, profile: { _ in AppProfile() }, fallbackApp: { "fallback.app" })
    let client = IdentityNoSourceClient()
    client.onQuery = {
        client.answer = "actual.app"
        _ = coordinator.keyDown(KeyEvent(keyCode: 5), client: client)
    }
    let outer = coordinator.keyDown(KeyEvent(keyCode: 15), client: client)
    #expect(outer.handled && outer.mode == .korean && client.marked == "ㄱ")
    #expect(coordinator.clientApp?.bundleID == "actual.app")
}

private nonisolated final class IdentityDynamicClient: InputClient {
    var appIDSource: AnyObject?
    var answer: String?
    var onQuery: (() -> Void)?
    var marked = ""
    init(source: AnyObject?, answer: String?) { appIDSource = source; self.answer = answer }
    func bundleIdentifier() -> String? {
        let value = answer
        let callback = onQuery; onQuery = nil; callback?()
        return value
    }
    func selectedText() -> String? { nil }
    func textBefore(_ count: Int) -> (text: String, end: Int)? { nil }
    func apply(_ actions: [Action]) {
        for action in actions { if case .mark(let value) = action { marked = value } }
    }
}

@Test("ID 출처: 질의 중 확인한 client 의 출처가 바뀌면 동일 출처로 여기지 않는다")
func clientIdentityChangesDuringQuery() {
    let first = NSObject(), second = NSObject()
    let driver = SessionDriver()
    let modes = IdentityModes(actual: .english, fallback: .korean)
    let coordinator = InputCoordinator(driver: driver, modes: modes, profile: { _ in AppProfile() }, fallbackApp: { "fallback.app" })
    let outer = IdentityDynamicClient(source: first, answer: nil)
    let nested = IdentityDynamicClient(source: first, answer: "actual.app")
    outer.onQuery = {
        nested.onQuery = { nested.appIDSource = second }
        _ = coordinator.keyDown(KeyEvent(keyCode: 5), client: nested)
    }
    let outcome = coordinator.keyDown(KeyEvent(keyCode: 15), client: outer)
    #expect(coordinator.clientApp?.bundleID == "actual.app")
    #expect(outcome.handled && outcome.mode == .korean && outer.marked == "ㄱ")
}

@Test("ID 출처: coordinator 의 ID cache 는 출처 객체의 수명을 늘리지 않는다")
func clientIdentitySourceIsWeak() {
    let driver = SessionDriver()
    let modes = IdentityModes(actual: .english, fallback: .english)
    let coordinator = InputCoordinator(driver: driver, modes: modes, profile: { _ in AppProfile() }, fallbackApp: { "fallback.app" })
    var source: NSObject? = NSObject()
    weak let weakSource = source
    var client: IdentityDynamicClient? = IdentityDynamicClient(source: source, answer: "actual.app")
    _ = coordinator.keyDown(KeyEvent(keyCode: 0), client: client!)
    #expect(coordinator.clientApp?.bundleID == "actual.app")
    client = nil
    source = nil
    #expect(weakSource == nil)
}

@Test("ID 출처: 바깥 질의 중 proxy 출처가 바뀌면 중첩 ID 를 쓰지 않는다")
func clientIdentityOuterSourceChanges() {
    let first = NSObject(), second = NSObject()
    let driver = SessionDriver()
    let modes = IdentityModes(actual: .english, fallback: .korean)
    let coordinator = InputCoordinator(driver: driver, modes: modes, profile: { _ in AppProfile() }, fallbackApp: { "fallback.app" })
    let outer = IdentityDynamicClient(source: first, answer: nil)
    let nested = IdentityDynamicClient(source: first, answer: "actual.app")
    outer.onQuery = {
        _ = coordinator.keyDown(KeyEvent(keyCode: 5), client: nested)
        outer.appIDSource = second
    }
    let outcome = coordinator.keyDown(KeyEvent(keyCode: 15), client: outer)
    #expect(outcome.handled && outcome.mode == .korean && outer.marked == "ㄱ")
}

@Test("ID 출처: 중첩 없는 nil 은 fallback, 유효 ID 와 기존 cache 는 종전처럼 동작한다")
func clientIdentityOrdinaryPaths() {
    let missing = IdentityHost(actual: .english, fallback: .korean)
    #expect(missing.key(5).handled)
    #expect(missing.fallbackCalls == 1 && missing.proxy.idQueries == 1)
    #expect(missing.coordinator.clientApp == nil && missing.proxy.marked == "ㅎ")

    let known = IdentityHost(actual: .english, fallback: .korean)
    known.proxy.firstAnswer = "actual.app"
    #expect(!known.key(5).handled)
    #expect(!known.key(15).handled)
    #expect(known.proxy.idQueries == 1 && known.fallbackCalls == 0)
    #expect(known.coordinator.clientApp?.bundleID == "actual.app")
}

@Test("ID 출처: 바깥 질의가 유효 ID 를 돌려주면 기존처럼 그 응답을 쓴다")
func clientIdentityValidOuterAnswer() {
    let host = IdentityHost(actual: .korean, fallback: .korean)
    host.proxy.firstAnswer = "outer.app"
    host.proxy.onFirstQuery = { _ = host.key(5) }
    let outer = host.key(15)
    #expect(host.proxy.idQueries == 2 && host.fallbackCalls == 0)
    #expect(host.coordinator.clientApp?.bundleID == "outer.app")
    #expect(!outer.handled && outer.mode == .english)
}
