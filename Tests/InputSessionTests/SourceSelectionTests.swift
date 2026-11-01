import Testing
@testable import InputSession

@Test("source 판정: 정확한 parent·mode 만 homi 로 보고 유사 prefix 는 다른 source 다",
    arguments: ["com.unocult.inputmethod.homily", "com.unocult.inputmethod.homi.evil", "com.unocult.inputmethod.homi.korean.extra"])
func sourceSelectionRejectsSimilarID(id: String) {
    #expect(SourceSelection.fromID(id) == .other)
}

@Test("source 판정: parent·mode 와 다른 source 및 빈 ID 를 구별한다")
func sourceSelectionExactAndUnknown() {
    #expect(SourceSelection.fromID(SourceSelection.parentID) == .selected)
    #expect(SourceSelection.fromID(SourceSelection.modeID) == .selected)
    #expect(SourceSelection.fromID("com.apple.keylayout.ABC") == .other)
    #expect(SourceSelection.fromID("") == .unknown(.emptyID))
    #expect(!SourceSelection.unknown(.propertyNil).compatibilitySelected)
    #expect(!SourceSelection.other.compatibilitySelected)
    #expect(SourceSelection.selected.compatibilitySelected)
}
