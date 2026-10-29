import Testing
@testable import InputSession

private let capsProfile = AppProfile(toggleKeys: [.capsLock])
private func caps(_ capture: ModifierCapture) -> ModifierEvent {
    ModifierEvent(keyCode: 62, modifiers: capture.isDown ? .control : [], time: capture.time,
        activity: capture.activity, isDown: capture.isDown)
}

@Test("release 뒤 다음 key 가 이미 발생했어도 정상 tap 과 다음 key 의 한글 mode 를 보존한다")
func delayedReleaseUsesEventSnapshot() {
    var timeline = ModifierActivityTimeline()
    timeline.modifier(keyCode: 62, time: 10, isDown: true)
    let press = timeline.lastCapture!
    timeline.modifier(keyCode: 62, time: 10.1, isDown: false)
    let released = timeline.lastCapture!
    timeline.input() // 물리 10.3 의 다음 key. IMK 는 10.4 에 앞의 modifier 를 처리한다.
    var keys = ModifierKeys()
    _ = keys.changed(caps(press), profile: capsProfile)
    let release = keys.changed(caps(released), profile: capsProfile)
    #expect(release.action == .toggle)
    var session = Session()
    let mode = release.action == .toggle ? session.toggle(from: .english).mode : .english
    let firstKey = session.handle(KeyEvent(keyCode: 0), mode: mode)
    #expect(firstKey.actions == [.mark("ㅁ")])
}

@Test("누름도 늦게 전달되어도 IMK 가 못 본 단축키는 tap 이 아니다")
func delayedPressStillSeesHiddenChord() {
    var timeline = ModifierActivityTimeline()
    timeline.modifier(keyCode: 54, time: 10, isDown: true)
    let press = timeline.lastCapture!
    timeline.input() // menu 가 가져간 key. IMK 에서는 이 keyDown 을 보지 못한다.
    timeline.modifier(keyCode: 54, time: 10.1, isDown: false)
    let release = timeline.lastCapture!
    var keys = ModifierKeys()
    let profile = AppProfile(toggleKeys: [.rightCommand])
    for capture in [press, release] {
        let result = keys.changed(ModifierEvent(keyCode: 54, modifiers: capture.isDown ? .command : [],
            time: capture.time, activity: capture.activity, isDown: capture.isDown), profile: profile)
        #expect(result.action == nil)
    }
}

@Test("tap 사이 다른 수식키·mouse·key 활동은 취소하고 tap 밖의 활동은 영향이 없다", arguments: [true, false])
func activityBelongsToItsOwnInterval(modifier: Bool) {
    var timeline = ModifierActivityTimeline()
    timeline.input()
    timeline.modifier(keyCode: 62, time: 10, isDown: true)
    let press = timeline.lastCapture!
    if modifier {
        timeline.modifier(keyCode: 56, time: 10.02, isDown: true)
        timeline.modifier(keyCode: 56, time: 10.04, isDown: false)
    } else { timeline.input() }
    timeline.modifier(keyCode: 62, time: 10.1, isDown: false)
    let release = timeline.lastCapture!
    var keys = ModifierKeys()
    _ = keys.changed(caps(press), profile: capsProfile)
    let up = keys.changed(caps(release), profile: capsProfile)
    #expect(up.action == nil)
    timeline.modifier(keyCode: 62, time: 20, isDown: true)
    let nextPress = timeline.lastCapture!
    timeline.modifier(keyCode: 62, time: 20.1, isDown: false)
    let nextRelease = timeline.lastCapture!
    timeline.input()
    _ = keys.changed(caps(nextPress), profile: capsProfile)
    let next = keys.changed(caps(nextRelease), profile: capsProfile)
    #expect(next.action == .toggle)
}

@Test("짧은 tap 의 release 가 IMK 에 늦어도 먼저 도는 timer 가 대문자 고정으로 바꾸지 않는다")
func releasedPhysicalKeyCannotBecomeHold() {
    var timeline = ModifierActivityTimeline()
    timeline.modifier(keyCode: 62, time: 10, isDown: true)
    var keys = ModifierKeys()
    _ = keys.changed(caps(timeline.lastCapture!), profile: capsProfile)
    timeline.modifier(keyCode: 62, time: 10.1, isDown: false)
    let timer = keys.capsLockHeld(at: 10.5, pressedAt: timeline.capsPressTime, activity: timeline.currentActivity)
    let release = keys.changed(caps(timeline.lastCapture!), profile: capsProfile)
    #expect(timer == nil)
    #expect(release.action == .toggle)
}

@Test("실제 hold 는 0.5초 뒤 한 번만, 다른 누름의 timer 는 적용하지 않는다")
func holdRequiresSamePhysicalPress() {
    var timeline = ModifierActivityTimeline()
    timeline.modifier(keyCode: 62, time: 10, isDown: true)
    var keys = ModifierKeys()
    _ = keys.changed(caps(timeline.lastCapture!), profile: capsProfile)
    let early = keys.capsLockHeld(at: 10.49, pressedAt: 10, activity: timeline.currentActivity)
    let another = keys.capsLockHeld(at: 10.5, pressedAt: 10.2, activity: timeline.currentActivity)
    let held = keys.capsLockHeld(at: 10.5, pressedAt: 10, activity: timeline.currentActivity)
    let again = keys.capsLockHeld(at: 10.6, pressedAt: 10, activity: timeline.currentActivity)
    timeline.modifier(keyCode: 62, time: 10.7, isDown: false)
    let release = keys.changed(caps(timeline.lastCapture!), profile: capsProfile)
    #expect(early == nil && another == nil)
    #expect(held == .capsLock && again == nil && release.action == nil)
}

@Test("관찰 공백과 missing 은 단독 tap 의 증거가 아니다")
func missingEvidenceCannotToggle() {
    var timeline = ModifierActivityTimeline()
    timeline.modifier(keyCode: 62, time: 10, isDown: true)
    var keys = ModifierKeys()
    _ = keys.changed(caps(timeline.lastCapture!), profile: capsProfile)
    timeline.invalidate()
    timeline.modifier(keyCode: 62, time: 10.1, isDown: false)
    let afterGap = keys.changed(caps(timeline.lastCapture!), profile: capsProfile)
    #expect(afterGap.action == nil)
    _ = keys.changed(ModifierEvent(keyCode: 62, modifiers: .control, time: 20, activity: .missing, isDown: true), profile: capsProfile)
    let missing = keys.changed(ModifierEvent(keyCode: 62, modifiers: [], time: 20.1, activity: .missing, isDown: false), profile: capsProfile)
    #expect(missing.action == nil)
}

@Test("같은 시각의 서로 다른 수식키도 각자의 press·release 와 연결한다")
func gestureIdentityIsIndependentOfTimestamp() {
    var timeline = ModifierActivityTimeline()
    timeline.modifier(keyCode: 62, time: 10, isDown: true)
    let capsPress = timeline.lastCapture!
    timeline.modifier(keyCode: 54, time: 10, isDown: true)
    let commandPress = timeline.lastCapture!
    timeline.modifier(keyCode: 62, time: 10.1, isDown: false)
    let capsRelease = timeline.lastCapture!
    timeline.modifier(keyCode: 54, time: 10.1, isDown: false)
    let commandRelease = timeline.lastCapture!
    #expect(capsPress.gesture == capsRelease.gesture)
    #expect(commandPress.gesture == commandRelease.gesture)
    #expect(capsPress.gesture != commandPress.gesture)
}

@Test("focus·source 종료 뒤에는 같은 event snapshot 이 있어도 전환하지 않는다")
func lifecycleCancellationStillWins() {
    var timeline = ModifierActivityTimeline()
    timeline.modifier(keyCode: 62, time: 10, isDown: true)
    let press = timeline.lastCapture!
    timeline.modifier(keyCode: 62, time: 10.1, isDown: false)
    let release = timeline.lastCapture!
    var keys = ModifierKeys()
    _ = keys.changed(caps(press), profile: capsProfile)
    keys.cancel()
    let result = keys.changed(caps(release), profile: capsProfile)
    #expect(result.action == nil)
}
