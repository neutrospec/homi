/// 수식키 하나를 단독으로 눌렀다 뗐는지 — 짧게(tap)인지 길게(hold)인지.
/// 오른쪽 ⌘·⌥ 와 Caps Lock 이 이것으로 판정되고, 그 tap·hold 가 무엇을 뜻하는지는 `ModifierKeys` 가 주인의 설정대로 정한다.
///
/// ⌘C·⌘Tab 의 C·Tab 은 menu·system 이 먼저 가져가 입력기에 오지 않는다 (docs/macos-input.md, probe run 2).
/// 그래서 app 이 key 를 가져가기 전, 각 event 에 대응해 기억한 활동 번호를 비교한다.
/// `ModifierActivityTimeline` 을 연결할 수 없는 환경에서는 기존 counter 판정을 유지하며 시간차의 한계가 남는다.
public struct ModifierTap: Sendable {
    public enum Result: Sendable, Equatable {
        /// 사이에 다른 key·mouse 가 끼었거나 누른 적이 없다 — 아무것도 아니다.
        case none
        /// `holdAfter` 보다 짧게 단독으로 눌렀다 뗐다.
        case tap
        /// `holdAfter` 이상 단독으로 누르고 있다가 뗐다.
        case hold
    }

    /// 이 시간 이상 누르고 있으면 tap 이 아니라 hold 다.
    public static let holdAfter = 0.5

    private var armed: (time: Double, activity: ModifierActivity)?
    /// 누르고 있는 동안 이미 hold 로 처리했다 — 뗄 때 다시 처리하지 않는다.
    private var held = false

    public init() {}

    public var pressTime: Double? { held ? nil : armed?.time }

    /// 수식키를 (다른 수식키 없이) 눌렀다.
    public mutating func press(at time: Double, activity: ModifierActivity) {
        guard activity != .missing else { cancel(); return }
        // 같은 관찰 press 를 IMK 가 다시 전달해도 hold 처리와 최초 시각을 되돌리지 않는다.
        if let armed, armed.time == time, armed.activity == activity { return }
        armed = (time, activity)
        held = false
    }

    /// 사이에 다른 수식키가 끼었다.
    public mutating func cancel() {
        armed = nil
        held = false
    }

    /// 누른 지 `holdAfter` 가 지났다 (app 층의 timer). 아직 단독으로 누르고 있으면 hold 이고 true — 한 번만.
    /// macOS 의 Caps Lock 처럼 떼기 전에 대문자 고정이 켜지게 하려고 쓴다.
    public mutating func holdReached(at time: Double, pressedAt: Double?, activity: ModifierActivity) -> Bool {
        // 둘 다 같은 physical press 에서 복사한 값이다. IMK timestamp 와 근사 비교하지 않는다.
        guard let armed, !held, let pressedAt, pressedAt == armed.time,
            time - armed.time >= Self.holdAfter, activity.unchanged(since: armed.activity) else { return false }
        held = true
        return true
    }

    /// 수식키를 뗐다. 누르고 있는 동안 이미 hold 로 처리했다면 `.none`.
    public mutating func release(at time: Double, activity: ModifierActivity) -> Result {
        defer {
            armed = nil
            held = false
        }
        guard let armed, !held, time >= armed.time, activity.unchanged(since: armed.activity) else { return .none }
        return time - armed.time < Self.holdAfter ? .tap : .hold
    }
}
