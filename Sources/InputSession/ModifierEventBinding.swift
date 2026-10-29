/// IMK 의 duplicate press 를 같은 물리 gesture 에 묶는다. 시각을 근사해 서로 다른 event 를 맞추지 않는다.
/// 관찰기가 유일한 미처리 press 를 제공할 때만 capture 를 쓰며, 그 밖에는 전달받은 기존 counter 판정을 유지한다.
public struct ModifierEventBinding: Sendable {
    private var keyCode: UInt16?
    private var down = false
    private var capture: ModifierCapture?
    private var cancelled = false

    public init() {}

    public var usesCapturedCaps: Bool { down && !cancelled && keyCode == 62 && capture != nil }

    public mutating func cancel() {
        // IMK 의 duplicate press 가 keyDown·focus 취소 뒤 도착할 수 있다.
        // release 를 보기 전까지 같은 gesture 를 다시 arm 하지 않는다.
        cancelled = down
        capture = nil
    }

    /// 입력칸을 떠나면 release 자체가 이 controller 에 오지 않을 수 있다.
    public mutating func end() { self = Self() }

    public mutating func translate(
        _ event: ModifierEvent,
        claim: () -> ModifierCapture?,
        release: (ModifierCapture) -> ModifierCapture?
    ) -> ModifierEvent {
        guard [54, 61, 62].contains(event.keyCode) else { cancel(); return event }
        if event.isDown {
            if keyCode != event.keyCode || !down {
                keyCode = event.keyCode
                down = true
                cancelled = false
                capture = claim()
            }
            if cancelled { return withoutEvidence(event) }
            return capture.map { applying($0, to: event) } ?? event
        }
        guard keyCode == event.keyCode, down else { return event }
        down = false
        if cancelled {
            cancelled = false
            return withoutEvidence(event)
        }
        guard let captured = capture else { return event }
        capture = nil
        guard let released = release(captured), !released.isDown, released.keyCode == captured.keyCode,
            released.gesture == captured.gesture,
            released.time >= captured.time else {
            return withoutEvidence(event)
        }
        return applying(released, to: event)
    }

    private func applying(_ capture: ModifierCapture, to event: ModifierEvent) -> ModifierEvent {
        var event = event
        event.time = capture.time
        event.activity = capture.activity
        return event
    }

    private func withoutEvidence(_ event: ModifierEvent) -> ModifierEvent {
        var event = event
        event.activity = .missing
        return event
    }
}
