import AppKit
import InputMethodKit
import HangulCore
import InputSession
import Testing

@testable import homi

/// 문서 위치를 지정하지 않는 proxy 호출을 검사한다. 실제 app 의 조합 종료 여부는 별도 확인한다.
nonisolated final class TextProxy: NSObject, IMKTextInput {
    var insertedRange: NSRange?
    var markedReplacement: NSRange?
    var markedSelection: NSRange?
    var text = ""
    var marked = ""
    var queryCount = 0
    var onInsert: (() -> Void)?
    var onMark: (() -> Void)?
    var onSelectionQuery: (() -> Void)?
    var onMarkedQuery: (() -> Void)?
    var onAttributesQuery: (() -> Void)?
    var onSubstringQuery: (() -> Void)?
    var selectionAnswer = NSRange(location: NSNotFound, length: NSNotFound)
    var markedAnswer = NSRange(location: NSNotFound, length: NSNotFound)
    var attributeAnswer: [Any] = []
    var substringAnswer: String?
    var queries: [String] = []
    var appID: String? = "homi.tests"
    var onBundleQuery: (() -> Void)?
    var onCaretQuery: (() -> Void)?

    func insertText(_ string: Any?, replacementRange: NSRange) {
        insertedRange = replacementRange
        text += string as? String ?? ""
        marked = ""
        let callback = onInsert
        onInsert = nil
        callback?()
    }
    func setMarkedText(_ string: Any?, selectionRange: NSRange, replacementRange: NSRange) {
        markedSelection = selectionRange
        markedReplacement = replacementRange
        marked = string as? String ?? ""
        let callback = onMark
        onMark = nil
        callback?()
    }
    func selectedRange() -> NSRange {
        queryCount += 1
        queries.append("selected")
        let callback = onSelectionQuery
        onSelectionQuery = nil
        callback?()
        return selectionAnswer
    }
    func markedRange() -> NSRange {
        queryCount += 1
        queries.append("marked")
        onMarkedQuery?()
        return markedAnswer
    }
    func attributedSubstring(from range: NSRange) -> NSAttributedString? {
        queryCount += 1
        queries.append("substring")
        onSubstringQuery?()
        return substringAnswer.map { NSAttributedString(string: $0) }
    }
    func length() -> Int { NSNotFound }
    func characterIndex(for point: NSPoint, tracking: IMKLocationToOffsetMappingMode,
                        inMarkedRange: UnsafeMutablePointer<ObjCBool>?) -> Int { NSNotFound }
    func attributes(forCharacterIndex index: Int,
                    lineHeightRectangle: UnsafeMutablePointer<NSRect>?) -> [AnyHashable: Any]? {
        queryCount += 1
        let callback = onCaretQuery
        onCaretQuery = nil
        callback?()
        lineHeightRectangle?.pointee = NSRect(x: 10, y: 20, width: 0, height: 18)
        return nil
    }
    func validAttributesForMarkedText() -> [Any]? {
        queryCount += 1
        queries.append("attributes")
        onAttributesQuery?()
        return attributeAnswer
    }
    func overrideKeyboard(withKeyboardNamed keyboard: String?) {}
    func selectMode(_ mode: String?) {}
    func supportsUnicode() -> Bool { true }
    func bundleIdentifier() -> String? {
        let callback = onBundleQuery
        onBundleQuery = nil
        callback?()
        return appID
    }
    func windowLevel() -> CGWindowLevel { 0 }
    func supportsProperty(_ property: TSMDocumentPropertyTag) -> Bool { false }
    func uniqueClientIdentifierString() -> String? { "homi.tests.client" }
    func string(from range: NSRange, actualRange: NSRangePointer?) -> String? { nil }
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect { .zero }
}

@Test("확정은 문서 위치를 지정하지 않고 기존 호환 range 로 보낸다")
func insertionDoesNotSpecifyDocumentPosition() {
    let proxy = TextProxy()
    Client(proxy: proxy).apply([.insert("한")])
    #expect(proxy.insertedRange == NSRange(location: NSNotFound, length: 0))
}

@Test("marked text 는 문서 위치를 지정하지 않고 UTF-16 끝에 caret 을 둔다")
func markedTextUsesUTF16Caret() {
    let proxy = TextProxy()
    Client(proxy: proxy).apply([.mark("한🙂")])
    #expect(proxy.markedReplacement?.location == NSNotFound)
    #expect(proxy.markedSelection == NSRange(location: 3, length: 0))
}

@Test("검증한 한자 재변환의 교체 범위는 그대로 client 에 보낸다")
func reconversionKeepsReplacementRange() {
    let proxy = TextProxy()
    let range = NSRange(location: 7, length: 2)
    Client(proxy: proxy).apply([.markCommitted("한자", range: range)])
    #expect(proxy.markedReplacement == range)
}

@Test("client trace: insert callback 은 다음 mark 계획과 이전 mark 반환을 구분한다")
func clientBatchIsPlannedBeforeInsert() throws {
    let proxy = TextProxy()
    let trace = ClientTrace(state: .init(composing: true, candidates: false))
    let client = Client(proxy: proxy, trace: trace)
    client.apply([.mark("한")])
    let old = try #require(trace.snapshot.lastMarkCallReturn)
    var observed: ClientTrace.Snapshot?
    proxy.onInsert = { observed = trace.snapshot }
    client.apply([.insert("한"), .mark("ㄱ")])
    let callback = try #require(observed)
    #expect(callback.frame?.kind == .insert)
    #expect(callback.localMarkPlan != old)
    #expect(callback.lastMarkCallReturn == old)
    #expect(trace.snapshot.lastMarkCallReturn == callback.localMarkPlan)
    #expect(proxy.text == "한")
    #expect(proxy.marked == "ㄱ")
    #expect(proxy.queryCount == 0)
}

@Test("client trace: mark 의 callback 은 호출 중과 정상 반환 뒤를 구분한다")
func clientMarkCallbackBeforeReturn() throws {
    let proxy = TextProxy()
    let trace = ClientTrace(state: .init(composing: true, candidates: false))
    let client = Client(proxy: proxy, trace: trace)
    client.apply([.mark("ㅎ")])
    let old = try #require(trace.snapshot.lastMarkCallReturn)
    var observed: ClientTrace.Snapshot?
    proxy.onMark = { observed = trace.snapshot }
    client.apply([.mark("하")])
    let callback = try #require(observed)
    #expect(callback.frame?.kind == .mark)
    #expect(callback.lastMarkCallAttempt == callback.localMarkPlan)
    #expect(callback.lastMarkCallReturn == old)
    #expect(trace.snapshot.lastMarkCallReturn == callback.localMarkPlan)
    #expect(trace.snapshot.frame == nil)
    #expect(proxy.queryCount == 0)
}

@Test("client trace: 문서 질의의 snapshot 은 client 에 추가로 묻지 않는다")
func clientQueryDoesNotQueryAgainForTrace() throws {
    let proxy = TextProxy()
    let trace = ClientTrace()
    let client = Client(proxy: proxy, trace: trace)
    var observed: ClientTrace.Snapshot?
    proxy.onSelectionQuery = { observed = trace.snapshot }
    #expect(client.selectedText() == nil)
    let callback = try #require(observed)
    #expect(callback.frame?.kind == .query)
    #expect(proxy.queryCount == 1)
    #expect(trace.snapshot.frame == nil)
}

private nonisolated final class ClientTestModes: ModeStore {
    var memory = ModeMemory(modes: ["homi.tests": .korean, "fallback": .korean])
    func withMemory<Result: Sendable>(_ operation: (inout ModeMemory) -> Result) -> Result { operation(&memory) }
    func save(_ snapshot: ModeMemory) {}
}

@Test("coordinator·Client: 실제 adapter 의 ID 질의 재진입도 늦은 ID 의 조합을 보존한다")
func coordinatorClientIdentityReentry() {
    let modes = ClientTestModes()
    let coordinator = InputCoordinator(modes: modes, profile: { _ in AppProfile(startsInEnglish: true) },
        fallbackApp: { "fallback" })
    let proxy = TextProxy()
    proxy.appID = nil
    let client = Client(proxy: proxy, trace: coordinator.driver.clientTrace, submission: coordinator.driver.submission)
    coordinator.keyDown(KeyEvent(keyCode: 5), client: client) // ㅎ
    proxy.appID = "homi.tests"
    var queried = false
    proxy.onBundleQuery = {
        queried = true
        let snapshot = coordinator.driver.clientTrace.snapshot
        #expect(snapshot.frame?.kind == .query)
        #expect(snapshot.eventID != nil)
        coordinator.driver.deactivate(apply: client.apply)
        _ = coordinator.activate()
    }
    coordinator.keyDown(KeyEvent(keyCode: 40), client: client) // ㅏ
    #expect(queried)
    #expect(proxy.text.isEmpty)
    #expect(proxy.marked == "하")
    #expect(proxy.markedReplacement?.location == NSNotFound)
    #expect(modes.memory.mode(for: "homi.tests") == .korean)
    #expect(proxy.queryCount == 0) // 일반 조합은 문서 위치를 묻지 않는다.
}

@Test("coordinator·Client: insert callback 뒤 다음 mark 를 같은 mode 와 range 규칙으로 반영한다")
func coordinatorClientInsertReentry() {
    let modes = ClientTestModes()
    let coordinator = InputCoordinator(modes: modes, profile: { _ in AppProfile(startsInEnglish: true) },
        fallbackApp: { "fallback" })
    let proxy = TextProxy()
    let client = Client(proxy: proxy, trace: coordinator.driver.clientTrace, submission: coordinator.driver.submission)
    coordinator.modifiersChanged(client: client, action: { _, _ in .toggle })
    for code: UInt16 in [5, 40, 1] { coordinator.keyDown(KeyEvent(keyCode: code), client: client) } // 한
    var reentered = false
    proxy.onInsert = {
        reentered = true
        #expect(coordinator.driver.clientTrace.snapshot.frame?.kind == .insert)
        coordinator.driver.deactivate(apply: client.apply)
        let activation = coordinator.activate()
        #expect(activation.resuming)
    }
    for code: UInt16 in [15, 40] { coordinator.keyDown(KeyEvent(keyCode: code), client: client) } // 가
    #expect(reentered)
    #expect(proxy.text == "한")
    #expect(proxy.marked == "가")
    #expect(proxy.insertedRange == NSRange(location: NSNotFound, length: 0))
    #expect(proxy.markedReplacement?.location == NSNotFound)
    #expect(modes.memory.mode(for: "homi.tests") == .korean)
    #expect(proxy.queryCount == 0)
}

@Test("coordinator·Client: 확정 callback 은 그때까지 보낸 mark 에만 적용한다", arguments: ["insert", "insertActivate", "mark"])
func coordinatorClientConfirmationScope(callback: String) {
    let coordinator = InputCoordinator(modes: ClientTestModes(), profile: { _ in AppProfile(startsInEnglish: true) }, fallbackApp: { "fallback" })
    let proxy = TextProxy()
    let driver = coordinator.driver
    let client = Client(proxy: proxy, trace: driver.clientTrace, submission: driver.submission)
    coordinator.modifiersChanged(client: client, action: { _, _ in .toggle })
    for code: UInt16 in [5, 40, 1] { coordinator.keyDown(KeyEvent(keyCode: code), client: client) }
    let confirmed = {
        driver.end(.alreadyCommittedByClient, apply: client.apply)
        if callback == "insertActivate" {
            let activation = coordinator.activate()
            #expect(activation.resuming)
        }
        if callback == "mark" {
            proxy.text += proxy.marked
            proxy.marked = ""
        }
    }
    if callback != "mark" { proxy.onInsert = confirmed }
    else { proxy.onMark = confirmed }
    coordinator.keyDown(KeyEvent(keyCode: 15), client: client)
    #expect(driver.composing == (callback != "mark" ? "ㄱ" : ""))
    #expect(proxy.marked == driver.composing)
    if callback != "mark" {
        for code: UInt16 in [46, 3] { coordinator.keyDown(KeyEvent(keyCode: code), client: client) }
    }
    driver.end(.commitToClient, apply: client.apply)
    #expect(proxy.text == (callback != "mark" ? "한글" : "한ㄱ"))
    #expect(proxy.marked.isEmpty)
    #expect(proxy.queryCount == 0)
}

@Test("선택 질의 중 새 입력이 오면 이후 질의와 응답을 버린다", arguments: ["selected", "substring"])
func selectedQueryCancellation(stage: String) {
    let proxy = TextProxy()
    proxy.selectionAnswer = NSRange(location: 4, length: 2)
    proxy.substringAnswer = "한자"
    var current = true
    if stage == "selected" { proxy.onSelectionQuery = { current = false } }
    else { proxy.onSubstringQuery = { current = false } }
    let result = Client(proxy: proxy).selectedText(while: { current })
    #expect(result == nil)
    #expect(proxy.queries == (stage == "selected" ? ["selected"] : ["selected", "substring"]))
}

@Test("이전 글자 질의 중 새 입력이 오면 이후 질의와 응답을 버린다", arguments: ["attributes", "marked", "selected", "substring"])
func precedingQueryCancellation(stage: String) {
    let proxy = TextProxy()
    proxy.attributeAnswer = ["NSTextInputReplacementRangeAttributeName", "NSTextAlternatives"]
    proxy.selectionAnswer = NSRange(location: 5, length: 0)
    proxy.substringAnswer = "한자"
    var current = true
    let cancel = { current = false }
    switch stage {
    case "attributes": proxy.onAttributesQuery = cancel
    case "marked": proxy.onMarkedQuery = cancel
    case "selected": proxy.onSelectionQuery = cancel
    default: proxy.onSubstringQuery = cancel
    }
    let result = Client(proxy: proxy).textBefore(2, while: { current })
    let expected = ["attributes", "marked", "selected", "substring"]
    #expect(result == nil)
    #expect(proxy.queries == Array(expected.prefix(expected.firstIndex(of: stage)! + 1)))
}

@Test("문서 질의 정상 경로는 기존 질의 순서와 답을 보존한다")
func cancellableQueriesNormal() {
    let proxy = TextProxy()
    proxy.attributeAnswer = ["NSTextInputReplacementRangeAttributeName", "NSTextAlternatives"]
    proxy.selectionAnswer = NSRange(location: 5, length: 0)
    proxy.substringAnswer = "한자"
    let client = Client(proxy: proxy)
    let before = client.textBefore(2, while: { true })
    #expect(before?.text == "한자")
    #expect(before?.end == 5)
    #expect(proxy.queries == ["attributes", "marked", "selected", "substring"])
    proxy.queries = []
    proxy.selectionAnswer = NSRange(location: 3, length: 2)
    #expect(client.selectedText(while: { true }) == "한자")
    #expect(proxy.queries == ["selected", "substring"])
}

@Test("이미 취소된 문서 질의는 client 를 호출하지 않는다")
func cancelledQueryDoesNotCallClient() {
    let proxy = TextProxy()
    let client = Client(proxy: proxy)
    #expect(client.selectedText(while: { false }) == nil)
    #expect(client.textBefore(2, while: { false }) == nil)
    #expect(proxy.queryCount == 0)
}

@Test("조합 범위 앞의 질의는 선택을 묻지 않으며 기존 호출도 같은 답을 준다")
func precedingMarkedQueryNormal() {
    let proxy = TextProxy()
    proxy.attributeAnswer = ["NSTextInputReplacementRangeAttributeName", "NSTextAlternatives"]
    proxy.markedAnswer = NSRange(location: 5, length: 1)
    proxy.substringAnswer = "한자"
    let client = Client(proxy: proxy)
    let result = client.textBefore(2)
    #expect(result?.text == "한자")
    #expect(result?.end == 5)
    #expect(proxy.queries == ["attributes", "marked", "substring"])
}

private let clientBridgeDictionary = try! HanjaDictionary(contentsOf: URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appending(path: "Sources/homi/Bundle/Resources/hanja.txt"))

/// 실제 coordinator 와 adapter 의 질의에 재진입을 주입한다. 실제 OS 에서 일어났다는 뜻은 아니다.
private final class HanjaClientBridge {
    let driver = SessionDriver(hanja: clientBridgeDictionary)
    let proxy = TextProxy()
    let coordinator: InputCoordinator
    let client: Client

    init() {
        coordinator = InputCoordinator(driver: driver, modes: ClientTestModes(), profile: { _ in AppProfile() },
                                       fallbackApp: { "homi.tests" })
        client = Client(proxy: proxy, trace: driver.clientTrace, submission: driver.submission)
    }

    @discardableResult func key(_ code: UInt16, modifiers: Modifiers = []) -> Outcome {
        coordinator.keyDown(KeyEvent(keyCode: code, modifiers: modifiers), client: client)
    }
}

@Test("coordinator·Client: 선택 범위 질의 중 새 key 는 옛 선택과 후보를 버린다", arguments: [false, true])
func coordinatorClientSelectedQueryInterrupted(modifier: Bool) {
    let host = HanjaClientBridge()
    host.proxy.selectionAnswer = NSRange(location: 2, length: 2)
    host.proxy.substringAnswer = "한자"
    var called = false
    host.proxy.onSelectionQuery = {
        called = true
        #expect(!host.driver.isMutatingSession)
        host.key(5) // ㅎ
    }
    if modifier {
        host.coordinator.modifiersChanged(client: host.client, action: { _, _ in .hanja })
    } else {
        let outcome = host.key(KeyCode.returnKey, modifiers: .option)
        #expect(outcome.handled)
    }
    #expect(called)
    #expect(host.proxy.queries == ["selected"])
    #expect(host.driver.composing == "ㅎ")
    #expect(host.proxy.marked == "ㅎ")
    #expect(!host.driver.hasCandidates)
}

@Test("coordinator·Client: 이전 글자 질의 중 새 key 는 옛 질의를 중단한다", arguments: ["attributes", "marked"])
func coordinatorClientPrecedingQueryInterrupted(stage: String) {
    let host = HanjaClientBridge()
    for code: UInt16 in [5, 40, 1, 15, 40] { host.key(code) } // 한가
    #expect(host.proxy.text == "한" && host.proxy.marked == "가")
    host.proxy.attributeAnswer = ["NSTextInputReplacementRangeAttributeName", "NSTextAlternatives"]
    host.proxy.markedAnswer = NSRange(location: 1, length: 1)
    host.proxy.substringAnswer = "한"
    var called = false
    let nested = {
        called = true
        #expect(!host.driver.isMutatingSession)
        host.key(1) // 간
    }
    if stage == "attributes" { host.proxy.onAttributesQuery = nested }
    else { host.proxy.onMarkedQuery = nested }
    let outcome = host.key(KeyCode.returnKey, modifiers: .option)
    #expect(outcome.handled)
    #expect(called)
    #expect(host.proxy.queries == (stage == "attributes" ? ["attributes"] : ["attributes", "marked"]))
    #expect(host.proxy.text == "한" && host.proxy.marked == "간")
    #expect(host.driver.composing == "간")
    #expect(!host.driver.hasCandidates)
}
