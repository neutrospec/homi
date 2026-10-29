/// 수식키 event 와 같은 흐름에서 얻은 활동 번호. 일반 key 의 내용은 담지 않는다.
public enum ModifierActivity: Sendable, Equatable {
    case events(epoch: UInt64, serial: UInt64)
    /// 관찰 권한이 없는 환경의 기존 동작. event 당시 snapshot 이 아니므로 시간차의 한계가 남는다.
    case counter([UInt32])
    /// 관찰 공백·buffer 초과·일치하는 event 없음. 두 번 missing 이어도 단독 tap 의 증거가 아니다.
    case missing

    func unchanged(since earlier: Self) -> Bool {
        self != .missing && self == earlier
    }
}

/// 같은 물리 누름·뗌은 gesture 번호로 연결한다. IMK 가 timestamp 를 다시 만들어도 이 짝은 바뀌지 않는다.
public struct ModifierCapture: Sendable, Equatable {
    public var keyCode: UInt16
    public var time: Double
    public var isDown: Bool
    public var gesture: UInt64
    public var activity: ModifierActivity

    public init(keyCode: UInt16, time: Double, isDown: Bool, gesture: UInt64, activity: ModifierActivity) {
        self.keyCode = keyCode
        self.time = time
        self.isDown = isDown
        self.gesture = gesture
        self.activity = activity
    }
}

/// app 이 key 를 가져가기 전의 event 순서를 센다. 일반 입력은 횟수만, 전환 수식키는 누름·뗌의 짝을 만든다.
/// snapshot 의 보관·IMK 연결은 app 층의 고정 크기 store 가 맡는다. timestamp 로 IMK event 를 찾지 않는다.
public struct ModifierActivityTimeline: Sendable {
    private var epoch: UInt64 = 0
    private var serial: UInt64 = 0
    public private(set) var capsPressTime: Double?
    private var presses: [UInt16: UInt64] = [:]
    public private(set) var lastCapture: ModifierCapture?

    public init() {}

    public mutating func input() { serial &+= 1 }

    @discardableResult
    public mutating func modifier(keyCode: UInt16, time: Double, isDown: Bool) -> ModifierActivity {
        let before = serial
        serial &+= 1
        lastCapture = nil
        guard [54, 61, 62].contains(keyCode) else { return .missing }
        // press 자신의 event 는 포함하고, release 자신의 event 는 제외한다.
        // 그 사이 다른 key·mouse·수식키가 하나라도 있으면 번호가 달라진다.
        let activity = ModifierActivity.events(epoch: epoch, serial: isDown ? serial : before)
        let gesture: UInt64
        if isDown {
            gesture = presses[keyCode] ?? serial
            presses[keyCode] = gesture
        } else {
            gesture = presses.removeValue(forKey: keyCode) ?? 0
        }
        lastCapture = ModifierCapture(keyCode: keyCode, time: time, isDown: isDown, gesture: gesture, activity: activity)
        if keyCode == 62 { capsPressTime = isDown ? time : nil }
        return activity
    }

    public var currentActivity: ModifierActivity { .events(epoch: epoch, serial: serial) }

    public mutating func invalidate() {
        epoch &+= 1
        capsPressTime = nil
        presses.removeAll(keepingCapacity: true)
        lastCapture = nil
    }

}
