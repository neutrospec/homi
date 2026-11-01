/// 현재 source 의 관측. unknown 은 선택 해제나 client 확정의 증거가 아니다.
public enum SourceSelection: Sendable, Equatable {
    public enum UnknownReason: String, Sendable {
        case sourceCopyNil, propertyNil, typeMismatch, emptyID
    }
    case selected
    case other
    case unknown(UnknownReason)

    public static let parentID = "com.unocult.inputmethod.homi"
    public static let modeID = "com.unocult.inputmethod.homi.korean"

    public static func fromID(_ id: String) -> SourceSelection {
        guard !id.isEmpty else { return .unknown(.emptyID) }
        return id == parentID || id == modeID ? .selected : .other
    }

    /// property nil·빈 ID 의 기존 false 를 유지한다. copy nil·타입 오류는 새 방어적 fallback 이다.
    /// 이 값은 안전한 종료 판정의 증거가 아니다.
    public var compatibilitySelected: Bool {
        if case .selected = self { return true }
        return false
    }

    public var diagnostic: String {
        switch self {
        case .selected: "yes"
        case .other: "no"
        case .unknown(let reason): "unknown(\(reason.rawValue))"
        }
    }
}
