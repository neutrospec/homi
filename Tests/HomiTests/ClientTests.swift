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

    func insertText(_ string: Any?, replacementRange: NSRange) { insertedRange = replacementRange }
    func setMarkedText(_ string: Any?, selectionRange: NSRange, replacementRange: NSRange) {
        markedSelection = selectionRange
        markedReplacement = replacementRange
    }
    func selectedRange() -> NSRange { NSRange(location: NSNotFound, length: NSNotFound) }
    func markedRange() -> NSRange { selectedRange() }
    func attributedSubstring(from range: NSRange) -> NSAttributedString? { nil }
    func length() -> Int { NSNotFound }
    func characterIndex(for point: NSPoint, tracking: IMKLocationToOffsetMappingMode,
                        inMarkedRange: UnsafeMutablePointer<ObjCBool>?) -> Int { NSNotFound }
    func attributes(forCharacterIndex index: Int,
                    lineHeightRectangle: UnsafeMutablePointer<NSRect>?) -> [AnyHashable: Any]? { nil }
    func validAttributesForMarkedText() -> [Any]? { [] }
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
