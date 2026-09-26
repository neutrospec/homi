/// 수식키 event 하나(flagsChanged) — AppKit 의 NSEvent 에서 판단에 쓰는 것만 옮긴 값.
public struct ModifierEvent: Sendable, Equatable {
    /// 바뀐 수식키의 자리 (macOS virtual key code).
    public var keyCode: UInt16
    /// 바뀐 뒤 눌려 있는 수식키.
    public var modifiers: Modifiers
    /// event 의 시각 (초).
    public var time: Double
    /// system 전체의 key·mouse 누름 횟수 — 사이에 다른 key 가 눌렸는지 본다 (`ModifierTap`).
    public var activity: [UInt32]

    public init(keyCode: UInt16, modifiers: Modifiers, time: Double, activity: [UInt32]) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.time = time
        self.activity = activity
    }
}

/// 수식키로 하는 일 — 오른쪽 ⌘·⌥ 와 Caps Lock 의 tap·hold 를 판정하고, 주인이 고른 역할(한/영 전환·한자)로 바꾼다.
///
/// IMK 층은 flagsChanged 를 옮겨 넘기고 돌려받은 일을 한다. hold timer 는 IMK 층에 있다 — `startsHoldTimer` 면
/// `ModifierTap.holdAfter` 뒤에 `capsLockHeld` 를 부른다 (macOS 처럼 떼기 전에 대문자 고정을 켜려고).
/// 전환이 전환 key 의 event 처리 안에서 끝나므로 "전환 → 다음 key" 순서는 그대로 구조로 보장된다 (결정 1·3).
public struct ModifierKeys: Sendable {
    /// 수식키가 뜻하는 일.
    public enum Action: Sendable, Equatable {
        /// 한/영 전환
        case toggle
        /// 한자 변환 (한자 key 로 고른 수식키의 tap)
        case hanja
        /// 대문자 고정 켜기·끄기 (Caps Lock 을 길게)
        case capsLock
    }

    public struct Result: Sendable, Equatable {
        public var action: Action?
        /// Caps Lock 을 누르기 시작했다 — IMK 층이 hold timer 를 건다. 아니면 걸린 timer 를 푼다.
        public var startsHoldTimer: Bool

        public init(action: Action? = nil, startsHoldTimer: Bool = false) {
            self.action = action
            self.startsHoldTimer = startsHoldTimer
        }
    }

    static let rightCommand: UInt16 = 54
    static let rightOption: UInt16 = 61
    /// Caps Lock 은 homi 가 선택된 동안 오른쪽 Control 로 remap 되어 온다 (`CapsLockRemap`) — 전환 key 로 골랐을 때만.
    static let capsLock: UInt16 = 62

    private var command = ModifierTap()
    private var option = ModifierTap()
    private var capsLock = ModifierTap()

    public init() {}

    /// 수식키가 바뀌었다 (flagsChanged). `profile` 에 주인이 고른 전환 key·한자 key 가 있다.
    public mutating func changed(_ event: ModifierEvent, profile: AppProfile) -> Result {
        guard !profile.passThrough else {
            // 한/영 전환 없는 app — 수식키도 그대로 둔다. Caps Lock 은 이 app 이 앞에 있는 동안 remap 이 풀려 원래대로 온다.
            cancel()
            return Result()
        }
        switch event.keyCode {
        case Self.rightCommand:
            option.cancel()
            capsLock.cancel()
            let result = Self.track(&command, event, flag: .command, others: [.shift, .control, .option, .function])
            return Result(action: result == .tap ? Self.meaning(.rightCommand, .rightCommand, profile) : nil)
        case Self.rightOption:
            command.cancel()
            capsLock.cancel()
            let result = Self.track(&option, event, flag: .option, others: [.shift, .control, .command, .function])
            return Result(action: result == .tap ? Self.meaning(.rightOption, .rightOption, profile) : nil)
        case Self.capsLock where profile.toggleKeys.contains(.capsLock):
            // 짧게 = 전환, 길게 = 대문자 고정 (macOS 와 같게). 길게는 보통 누르고 있는 동안 timer 가 처리한다 — 뗄 때의 hold 는 그러지 못했을 때.
            command.cancel()
            option.cancel()
            let result = Self.track(&capsLock, event, flag: .control, others: [.shift, .command, .option, .function])
            let action: Action? =
                switch result {
                case .tap: .toggle
                case .hold: .capsLock
                case .none: nil
                }
            return Result(action: action, startsHoldTimer: event.modifiers.contains(.control))
        default:
            // 다른 수식키가 끼었다. (대문자 고정을 뒤집을 때 오는 echo 도 여기로 — 이미 판정이 끝난 뒤다.)
            cancel()
            return Result()
        }
    }

    /// Caps Lock 을 누른 지 `ModifierTap.holdAfter` 가 지났다 (IMK 층의 timer). 아직 단독으로 누르고 있으면 대문자 고정 — 한 번만.
    public mutating func capsLockHeld(activity: [UInt32]) -> Action? {
        capsLock.holdReached(activity: activity) ? .capsLock : nil
    }

    /// key 를 치거나 입력칸을 떠났다 — 누르고 있던 수식키는 tap 이 아니다.
    public mutating func cancel() {
        command.cancel()
        option.cancel()
        capsLock.cancel()
    }

    /// 오른쪽 ⌘·⌥ 의 tap — 한/영 전환으로 골랐으면 전환, 한자 key 로 골랐으면 한자, 둘 다 아니면 아무 일도 없다.
    private static func meaning(
        _ toggleKey: Preferences.ToggleKey, _ hanjaKey: Preferences.HanjaKey, _ profile: AppProfile
    ) -> Action? {
        if profile.toggleKeys.contains(toggleKey) { return .toggle }
        if profile.hanjaKey == hanjaKey { return .hanja }
        return nil
    }

    /// 수식키 하나의 누름·뗌을 판정기에 넘긴다. 누를 때 다른 수식키가 함께면 tap 이 아니다.
    private static func track(_ tap: inout ModifierTap, _ event: ModifierEvent, flag: Modifiers, others: Modifiers)
        -> ModifierTap.Result
    {
        guard !event.modifiers.contains(flag) else {
            if event.modifiers.isDisjoint(with: others) {
                tap.press(at: event.time, activity: event.activity)
            } else {
                tap.cancel()
            }
            return .none
        }
        return tap.release(at: event.time, activity: event.activity)
    }
}
