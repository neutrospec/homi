import AppKit
import InputMethodKit
import InputSession
import Testing

@testable import homi

/// 문서 위치를 지정하지 않는 proxy 호출을 검사한다. 실제 app 의 조합 종료 여부는 별도 확인한다.
private nonisolated final class TextProxy: NSObject, IMKTextInput {
    var insertedRange: NSRange?
    var markedReplacement: NSRange?
    var markedSelection: NSRange?
    var text = ""
    var marked = ""
    var queryCount = 0
    var onInsert: (() -> Void)?
    var onMark: (() -> Void)?
    var onSelectionQuery: (() -> Void)?

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
        let callback = onSelectionQuery
        onSelectionQuery = nil
        callback?()
        return NSRange(location: NSNotFound, length: NSNotFound)
    }
    func markedRange() -> NSRange { queryCount += 1; return NSRange(location: NSNotFound, length: NSNotFound) }
    func attributedSubstring(from range: NSRange) -> NSAttributedString? { queryCount += 1; return nil }
    func length() -> Int { NSNotFound }
    func characterIndex(for point: NSPoint, tracking: IMKLocationToOffsetMappingMode,
                        inMarkedRange: UnsafeMutablePointer<ObjCBool>?) -> Int { NSNotFound }
    func attributes(forCharacterIndex index: Int,
                    lineHeightRectangle: UnsafeMutablePointer<NSRect>?) -> [AnyHashable: Any]? { queryCount += 1; return nil }
    func validAttributesForMarkedText() -> [Any]? { queryCount += 1; return [] }
    func overrideKeyboard(withKeyboardNamed keyboard: String?) {}
    func selectMode(_ mode: String?) {}
    func supportsUnicode() -> Bool { true }
    func bundleIdentifier() -> String? { "homi.tests" }
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
