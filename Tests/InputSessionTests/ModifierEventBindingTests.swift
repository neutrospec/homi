import Testing
@testable import InputSession

private let profile = AppProfile(toggleKeys: [.capsLock])
private func event(_ time: Double, down: Bool, counter: UInt32 = 0) -> ModifierEvent {
    .init(keyCode: 62, modifiers: down ? .control : [], time: time, activity: .counter([counter]), isDown: down)
}
private func capture(_ time: Double, down: Bool, serial: UInt64 = 1) -> ModifierCapture {
    .init(keyCode: 62, time: time, isDown: down, gesture: 1, activity: .events(epoch: 0, serial: serial))
}

@Test("IMK 가 시각을 바꾸고 press·release 를 두 번 보내도 물리 tap 은 한 번만 전환한다")
func rebuiltAndDuplicateIMKEvents() {
    var binding = ModifierEventBinding()
    var keys = ModifierKeys()
    var claims = 0
    var actions: [ModifierKeys.Action] = []
    for input in [event(10.004, down: true), event(10.009, down: true),
                  event(10.13, down: false, counter: 1), event(10.14, down: false, counter: 1)] {
        let translated = binding.translate(input, claim: {
            claims += 1
            return capture(10, down: true)
        }, release: { _ in capture(10.1, down: false) })
        if let action = keys.changed(translated, profile: profile).action { actions.append(action) }
    }
    #expect(claims == 1)
    #expect(actions == [.toggle])
}

@Test("관찰한 chord 는 IMK 가 그 key 를 못 봐도 전환하지 않는다")
func capturedChordIsNotTap() {
    var binding = ModifierEventBinding()
    var keys = ModifierKeys()
    let down = binding.translate(event(10.2, down: true), claim: { capture(10, down: true) }, release: { _ in nil })
    _ = keys.changed(down, profile: profile)
    let up = binding.translate(event(10.3, down: false), claim: { nil }, release: { _ in capture(10.1, down: false, serial: 2) })
    let result = keys.changed(up, profile: profile)
    #expect(result.action == nil)
}

@Test("press 대응이 불명확하면 해당 gesture 전체에 기존 counter 를 쓴다")
func ambiguousPressKeepsLegacyPair() {
    var binding = ModifierEventBinding()
    var keys = ModifierKeys()
    let down = binding.translate(event(10, down: true), claim: { nil }, release: { _ in nil })
    _ = keys.changed(down, profile: profile)
    let up = binding.translate(event(10.1, down: false), claim: { nil }, release: { _ in capture(10.1, down: false) })
    let result = keys.changed(up, profile: profile)
    #expect(down.activity == .counter([0]) && up.activity == .counter([0]))
    #expect(result.action == .toggle)
}

@Test("capture 의 release 가 없거나 다른 gesture 이면 연결을 만들어내지 않는다", arguments: [false, true])
func missingOrWrongReleaseCannotToggle(wrong: Bool) {
    var binding = ModifierEventBinding()
    var keys = ModifierKeys()
    let down = binding.translate(event(10, down: true), claim: { capture(10, down: true) }, release: { _ in nil })
    _ = keys.changed(down, profile: profile)
    let up = binding.translate(event(10.1, down: false), claim: { nil }, release: { _ in
        guard wrong else { return nil }
        var other = capture(10.1, down: false)
        other.gesture = 2
        return other
    })
    let result = keys.changed(up, profile: profile)
    #expect(up.activity == .missing && result.action == nil)
}

@Test("keyDown 으로 취소한 gesture 는 duplicate press 가 뒤늦게 와도 다시 켜지지 않는다")
func cancelledGestureDoesNotRearmOnDuplicate() {
    var binding = ModifierEventBinding()
    var keys = ModifierKeys()
    let down = binding.translate(event(10.004, down: true), claim: { capture(10, down: true) }, release: { _ in nil })
    _ = keys.changed(down, profile: profile)
    binding.cancel()
    keys.cancel()
    let duplicate = binding.translate(event(10.009, down: true), claim: { nil }, release: { _ in nil })
    _ = keys.changed(duplicate, profile: profile)
    let up = binding.translate(event(10.13, down: false), claim: { nil }, release: { _ in capture(10.1, down: false) })
    let result = keys.changed(up, profile: profile)
    #expect(result.action == nil)
    // 정상 release 를 본 다음의 새 gesture 는 다시 판정한다.
    let nextDown = binding.translate(event(11, down: true), claim: { nil }, release: { _ in nil })
    _ = keys.changed(nextDown, profile: profile)
    let nextUp = binding.translate(event(11.1, down: false), claim: { nil }, release: { _ in nil })
    let next = keys.changed(nextUp, profile: profile)
    #expect(next.action == .toggle)
}

@Test("종료된 입력칸에 old release 가 오지 않아도 복귀 후 첫 새 tap 은 동작한다")
func newSessionDoesNotWaitForMissingRelease() {
    var binding = ModifierEventBinding()
    var keys = ModifierKeys()
    let down = binding.translate(event(10.004, down: true), claim: { capture(10, down: true) }, release: { _ in nil })
    _ = keys.changed(down, profile: profile)
    binding.end()
    keys.cancel()
    // 다른 app 에서 뗐다. 이 controller 에는 다음 press 부터 다시 온다.
    let nextDown = binding.translate(event(20, down: true), claim: { nil }, release: { _ in nil })
    _ = keys.changed(nextDown, profile: profile)
    let nextUp = binding.translate(event(20.1, down: false), claim: { nil }, release: { _ in nil })
    let result = keys.changed(nextUp, profile: profile)
    #expect(result.action == .toggle)
}

@Test("hold 를 처리한 뒤 duplicate press 가 와도 대문자 고정을 다시 뒤집지 않는다")
func duplicatePressAfterHoldIsIdempotent() {
    var binding = ModifierEventBinding()
    var keys = ModifierKeys()
    let down = binding.translate(event(10.004, down: true), claim: { capture(10, down: true) }, release: { _ in nil })
    _ = keys.changed(down, profile: profile)
    let held = keys.capsLockHeld(at: 10.5, pressedAt: 10, activity: .events(epoch: 0, serial: 1))
    let duplicate = binding.translate(event(10.6, down: true), claim: { nil }, release: { _ in nil })
    let duplicateResult = keys.changed(duplicate, profile: profile)
    let heldAgain = keys.capsLockHeld(at: 10.7, pressedAt: 10, activity: .events(epoch: 0, serial: 1))
    let up = binding.translate(event(11, down: false), claim: { nil }, release: { _ in capture(10.9, down: false) })
    let result = keys.changed(up, profile: profile)
    #expect(held == .capsLock && heldAgain == nil)
    #expect(!duplicateResult.startsHoldTimer && result.action == nil)
}
