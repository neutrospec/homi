/// 오른쪽 ⌘ 를 단독으로 눌렀다 뗐는지 — 한/영 전환 key 하나.
///
/// ⌘C·⌘Tab 의 C·Tab 은 menu·system 이 먼저 가져가 입력기에 오지 않는다 (docs/macos-input.md, probe run 2).
/// 그래서 입력기가 본 event 가 아니라, system 전체의 key·mouse 누름 횟수(`activity`)가 누를 때와 뗄 때 같은지로 판정한다.
/// 횟수는 app 층이 `CGEventSource.counterForEventType` 으로 잰다 — 권한이 필요 없다.
public struct CommandTap: Sendable {
    /// 이보다 오래 누르고 있다가 뗀 것은 tap 이 아니다 (마음을 바꾼 경우).
    public static let limit = 0.5

    private var armed: (time: Double, activity: [UInt32])?

    public init() {}

    /// 오른쪽 ⌘ 를 (다른 수식키 없이) 눌렀다.
    public mutating func press(at time: Double, activity: [UInt32]) {
        armed = (time, activity)
    }

    /// 사이에 다른 수식키나 key 가 끼었다.
    public mutating func cancel() {
        armed = nil
    }

    /// 오른쪽 ⌘ 를 뗐다. 단독 tap 이면 true.
    public mutating func release(at time: Double, activity: [UInt32]) -> Bool {
        defer { armed = nil }
        guard let armed else { return false }
        return armed.activity == activity && time - armed.time < Self.limit
    }
}
