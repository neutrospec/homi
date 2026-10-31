/// client 에 보낸 mark 의 범위. renderer 가 적용·확정했다는 증거가 아니라 homi 의 전송 순서다.
/// Session 은 action 목록을 만들 때 이미 다음 조합으로 진행하므로, client callback 의 범위를 따로 둔다.
public final class CompositionSubmission {
    public private(set) var revision: UInt64 = 0
    private var pendingMarks = 0
    public var hasPendingMark: Bool { pendingMarks > 0 }

    public init() {}

    /// 이미 판단한 action 목록의 남은 mark. insert 중 재활성화도 다음 조합이 예정됐는지 구분한다.
    public func withActions<Result>(_ actions: [Action], _ body: () -> Result) -> Result {
        let previous = pendingMarks
        pendingMarks += actions.reduce(0) { count, action in
            switch action {
            case .mark, .markCommitted: count + 1
            default: count
            }
        }
        defer { pendingMarks = previous }
        return body()
    }

    /// client adapter 는 각 mark 호출 직전에 알린다. 목록의 계획 시점에는 올리지 않는다.
    public func willApply(_ action: Action) {
        switch action {
        case .mark, .markCommitted:
            revision &+= 1
            pendingMarks = max(0, pendingMarks - 1)
        default: break
        }
    }
}
