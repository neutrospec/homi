/// source 알림 하나의 판단 — TIS 관측을 remap·표시·종료의 효과로 바꾼다. 효과를 내는 일은 adapter(`SourceWatcher`)가 한다.
/// unknown 은 선택 해제로 다룬다 (기존 false fallback). 바꾸려면 이 한 곳과 docs/stability-review.md 의 판단을 함께 고친다.
public enum SourceNotice {
    public enum Trigger: Sendable, Equatable {
        /// TIS 선택 변경·설정 변경·wake. 선택이 아니면 마지막 owner 의 조합을 끝낸다 — deactivate 가 빠지는 전환을 메운다.
        case sourceChanged
        /// app 활성화·시작. remap·표시만 맞추고 조합은 끝내지 않는다 — 입력칸 이동은 deactivate·commit 이 맡는다.
        case appActivated
    }

    public struct Effects: Sendable, Equatable {
        /// Caps Lock remap·menu bar 표시·modifier 관찰에 쓰는 값. 실제 source 해제의 증거가 아니다.
        public let homiSelected: Bool
        /// 마지막 owner controller 의 조합을 확정할지.
        public let endsComposition: Bool

        public init(homiSelected: Bool, endsComposition: Bool) {
            self.homiSelected = homiSelected
            self.endsComposition = endsComposition
        }
    }

    public static func effects(of selection: SourceSelection, trigger: Trigger) -> Effects {
        let selected = selection.compatibilitySelected
        return Effects(homiSelected: selected, endsComposition: trigger == .sourceChanged && !selected)
    }
}
