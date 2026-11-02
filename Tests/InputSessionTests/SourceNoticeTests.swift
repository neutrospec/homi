import InputSession
import Testing

// 후속 3번 (2026-11-03): source 알림의 판단을 고정한다. unknown 의 false fallback 은 정책이며, 바꾸면 이 test 가 먼저 알린다.

@Test("source 알림: homi 선택이면 remap·표시를 켜고 조합을 끝내지 않는다")
func selectedKeepsComposition() {
    #expect(SourceNotice.effects(of: .selected, trigger: .sourceChanged) == .init(homiSelected: true, endsComposition: false))
}

@Test("source 알림: 다른 source 면 remap·표시를 끄고 마지막 owner 의 조합을 끝낸다")
func otherEndsComposition() {
    #expect(SourceNotice.effects(of: .other, trigger: .sourceChanged) == .init(homiSelected: false, endsComposition: true))
}

@Test("source 알림: 조회 실패는 이유와 무관하게 선택 해제로 다룬다 — 기존 false fallback",
      arguments: [SourceSelection.UnknownReason.sourceCopyNil, .propertyNil, .typeMismatch, .emptyID])
func unknownFallsBackToNotSelected(reason: SourceSelection.UnknownReason) {
    #expect(SourceNotice.effects(of: .unknown(reason), trigger: .sourceChanged) == .init(homiSelected: false, endsComposition: true))
    #expect(SourceNotice.effects(of: .unknown(reason), trigger: .appActivated) == .init(homiSelected: false, endsComposition: false))
}

@Test("app 활성화 알림은 remap·표시만 맞추고 어떤 관측에서도 조합을 끝내지 않는다",
      arguments: [SourceSelection.selected, .other])
func appActivationNeverEnds(selection: SourceSelection) {
    let effects = SourceNotice.effects(of: selection, trigger: .appActivated)
    #expect(!effects.endsComposition)
    #expect(effects.homiSelected == selection.compatibilitySelected)
}
