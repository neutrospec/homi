import AppKit
import IOKit.hidsystem
import InputSession
import Testing
@testable import homi

/// memory 안에서만 만드는 event. system 이나 app 에 post 하지 않는다.
private func modifier(_ key: UInt16, flags: UInt64, timestamp: UInt64 = 10_000_000_000) -> NSEvent {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true)!
    event.type = .flagsChanged
    event.flags = CGEventFlags(rawValue: flags)
    event.timestamp = timestamp
    return NSEvent(cgEvent: event)!
}

@Test("좌우 modifier 가 함께일 때 오른쪽 release 를 press 로 해석하지 않는다", arguments: [UInt16(54), 61, 62])
func releaseWithOppositeModifier(key: UInt16) {
    let bits: (CGEventFlags, Int32, Int32)
    switch key {
    case 54: bits = (.maskCommand, NX_DEVICERCMDKEYMASK, NX_DEVICELCMDKEYMASK)
    case 61: bits = (.maskAlternate, NX_DEVICERALTKEYMASK, NX_DEVICELALTKEYMASK)
    default: bits = (.maskControl, NX_DEVICERCTLKEYMASK, NX_DEVICELCTLKEYMASK)
    }
    let down = ModifierEvent(modifier(key, flags: bits.0.rawValue | UInt64(bits.1) | UInt64(bits.2)), activity: .counter([0]))
    let up = ModifierEvent(modifier(key, flags: bits.0.rawValue | UInt64(bits.2)), activity: .counter([0]))
    #expect(down.isDown && down.oppositeSideDown)
    #expect(!up.isDown && up.oppositeSideDown)
    var keys = ModifierKeys()
    let profile = AppProfile(toggleKeys: [.capsLock, .rightCommand, .rightOption])
    let pressed = keys.changed(down, profile: profile)
    let released = keys.changed(up, profile: profile)
    let hold = keys.capsLockHeld(at: 10.5, pressedAt: 10, activity: .counter([0]))
    #expect(pressed.action == nil && !pressed.startsHoldTimer)
    #expect(released.action == nil && !released.startsHoldTimer)
    #expect(hold == nil)
}

@Test("서로 다른 timestamp 의 NSEvent 두 쌍도 관찰한 한 gesture 에 묶어 한 번만 전환한다")
func retimedNSEventsUseCapturedGesture() {
    let store = ModifierActivityStore()
    store.publish(.init(keyCode: 62, time: 10, isDown: true, epoch: 0, serial: 1, gesture: 1), index: 0)
    store.publish(.init(keyCode: 62, time: 10.1, isDown: false, epoch: 0, serial: 1, gesture: 1), index: 1)
    let captured = store.pending(keyCode: 62, after: nil).capture
    var binding = ModifierEventBinding()
    var keys = ModifierKeys()
    let profile = AppProfile(toggleKeys: [.capsLock])
    var actions: [ModifierKeys.Action] = []
    let inputs = [(true, 10_004_000_000), (true, 10_009_000_000), (false, 10_130_000_000), (false, 10_140_000_000)]
    for (isDown, time) in inputs {
        let ns = modifier(62, flags: isDown ? CGEventFlags.maskControl.rawValue | UInt64(NX_DEVICERCTLKEYMASK) : 0,
            timestamp: UInt64(time))
        let raw = ModifierEvent(ns, activity: .counter([isDown ? 0 : 1]))
        let translated = binding.translate(raw, claim: { captured }, release: { store.release(for: $0) })
        if let action = keys.changed(translated, profile: profile).action { actions.append(action) }
    }
    #expect(actions == [.toggle])
}
