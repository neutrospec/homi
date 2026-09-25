/// 수식키 하나를 단독으로 눌렀다 뗐는지 — 짧게(tap)인지 길게(hold)인지.
///
/// 전환 key 둘이 이것으로 판정된다:
/// - 오른쪽 ⌘: tap = 한/영 전환
/// - Caps Lock (homi 가 선택된 동안 오른쪽 Control 로 remap): tap = 한/영 전환, hold = 대문자 고정 켜기/끄기 — macOS 의 Caps Lock 과 같다
///
/// ⌘C·⌘Tab 의 C·Tab 은 menu·system 이 먼저 가져가 입력기에 오지 않는다 (docs/macos-input.md, probe run 2).
/// 그래서 입력기가 본 event 가 아니라, system 전체의 key·mouse 누름 횟수(`activity`)가 누를 때와 뗄 때 같은지로 판정한다.
/// 횟수는 app 층이 `CGEventSource.counterForEventType` 으로 잰다 — 권한이 필요 없다. 판정은 event 의 timestamp 만 쓴다 (timer 없음).
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

    private var armed: (time: Double, activity: [UInt32])?
    /// 누르고 있는 동안 이미 hold 로 처리했다 — 뗄 때 다시 처리하지 않는다.
    private var held = false

    public init() {}

    /// 수식키를 (다른 수식키 없이) 눌렀다.
    public mutating func press(at time: Double, activity: [UInt32]) {
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
    public mutating func holdReached(activity: [UInt32]) -> Bool {
        guard let armed, !held, armed.activity == activity else { return false }
        held = true
        return true
    }

    /// 수식키를 뗐다. 누르고 있는 동안 이미 hold 로 처리했다면 `.none`.
    public mutating func release(at time: Double, activity: [UInt32]) -> Result {
        defer {
            armed = nil
            held = false
        }
        guard let armed, !held, armed.activity == activity else { return .none }
        return time - armed.time < Self.holdAfter ? .tap : .hold
    }
}
