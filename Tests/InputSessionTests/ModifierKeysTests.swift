import Testing

@testable import InputSession

// 수식키 tap 의 뜻 — flagsChanged 가 차례로 오면 무엇을 하는가 (IMK 층은 받은 일을 할 뿐이다).

private let rightCommand: UInt16 = 54
private let rightOption: UInt16 = 61
/// Caps Lock 은 homi 가 선택된 동안 오른쪽 Control 로 remap 되어 온다.
private let capsLock: UInt16 = 62
private let leftShift: UInt16 = 56

/// flagsChanged 하나 — `modifiers` 는 바뀐 뒤 눌려 있는 수식키.
private func flags(_ keyCode: UInt16, _ modifiers: Modifiers, at time: Double, activity: [UInt32] = [0]) -> ModifierEvent {
    ModifierEvent(keyCode: keyCode, modifiers: modifiers, time: time, activity: activity)
}

private func profile(
    _ toggleKeys: Set<Preferences.ToggleKey>, hanja: Preferences.HanjaKey = .optionReturn, passThrough: Bool = false
) -> AppProfile {
    AppProfile(passThrough: passThrough, toggleKeys: toggleKeys, hanjaKey: hanja)
}

/// 단독으로 눌렀다 뗀다 — 뗄 때 할 일.
private func tap(
    _ keys: inout ModifierKeys, _ keyCode: UInt16, _ flag: Modifiers, profile: AppProfile, for duration: Double = 0.1
) -> ModifierKeys.Action? {
    _ = keys.changed(flags(keyCode, flag, at: 10), profile: profile)
    return keys.changed(flags(keyCode, [], at: 10 + duration), profile: profile).action
}

@Test("오른쪽 ⌘·⌥ tap — 한/영 전환 key 로 골랐으면 전환")
func modifierTapToggles() {
    var keys = ModifierKeys()
    let both = profile([.rightCommand, .rightOption])
    #expect(tap(&keys, rightCommand, .command, profile: both) == .toggle)
    #expect(tap(&keys, rightOption, .option, profile: both) == .toggle)
}

@Test("오른쪽 ⌥·⌘ tap — 한자 key 로 골랐으면 한자, 어느 역할도 아니면 아무 일도 없다")
func modifierTapHanja() {
    var keys = ModifierKeys()
    #expect(tap(&keys, rightOption, .option, profile: profile([.capsLock], hanja: .rightOption)) == .hanja)
    #expect(tap(&keys, rightCommand, .command, profile: profile([.capsLock], hanja: .rightCommand)) == .hanja)
    #expect(tap(&keys, rightOption, .option, profile: profile([.capsLock])) == nil)
}

@Test("주인의 설정 그대로 — 기본은 Caps Lock·오른쪽 ⌘ 가 전환, 오른쪽 ⌥ 는 아무 일도 없다")
func modifierDefaults() {
    var keys = ModifierKeys()
    let standard = AppRules.profile(for: "com.example.unknown")
    #expect(tap(&keys, rightCommand, .command, profile: standard) == .toggle)
    #expect(tap(&keys, capsLock, .control, profile: standard) == .toggle)
    #expect(tap(&keys, rightOption, .option, profile: standard) == nil)
}

@Test("Caps Lock — 누르기 시작하면 hold timer 를 걸고, 짧게 떼면 전환")
func capsLockTap() {
    var keys = ModifierKeys()
    let caps = profile([.capsLock])
    let down = keys.changed(flags(capsLock, .control, at: 10), profile: caps)
    let up = keys.changed(flags(capsLock, [], at: 10.1), profile: caps)
    #expect(down == ModifierKeys.Result(action: nil, startsHoldTimer: true))
    #expect(up == ModifierKeys.Result(action: .toggle, startsHoldTimer: false))
}

@Test("Caps Lock hold — timer 가 울릴 때 아직 단독으로 누르고 있으면 대문자 고정, 뗄 때는 아무 일도 없다 (macOS 처럼)")
func capsLockHeldWhilePressed() {
    var keys = ModifierKeys()
    let caps = profile([.capsLock])
    _ = keys.changed(flags(capsLock, .control, at: 10), profile: caps)
    let held = keys.capsLockHeld(activity: [0])
    let again = keys.capsLockHeld(activity: [0])
    let up = keys.changed(flags(capsLock, [], at: 11), profile: caps)
    #expect(held == .capsLock)
    #expect(again == nil)
    #expect(up.action == nil)
}

@Test("Caps Lock 을 오래 누르다 뗐는데 timer 가 처리하지 못했으면 뗄 때 대문자 고정")
func capsLockHoldOnRelease() {
    var keys = ModifierKeys()
    #expect(tap(&keys, capsLock, .control, profile: profile([.capsLock]), for: ModifierTap.holdAfter) == .capsLock)
}

@Test("Caps Lock 이 전환 key 가 아니면 오른쪽 Control 은 다른 수식키일 뿐이다 — timer 도 없다")
func capsLockNotToggleKey() {
    var keys = ModifierKeys()
    let command = profile([.rightCommand])
    let down = keys.changed(flags(capsLock, .control, at: 10), profile: command)
    let up = keys.changed(flags(capsLock, [], at: 10.1), profile: command)
    #expect(down == ModifierKeys.Result())
    #expect(up == ModifierKeys.Result())
}

@Test("사이에 다른 수식키가 끼거나 함께 눌렀으면 tap 이 아니다")
func otherModifierCancels() {
    var keys = ModifierKeys()
    let command = profile([.rightCommand])
    _ = keys.changed(flags(rightCommand, .command, at: 10), profile: command)
    _ = keys.changed(flags(leftShift, [.command, .shift], at: 10.02), profile: command)
    _ = keys.changed(flags(leftShift, .command, at: 10.04), profile: command)
    let afterShift = keys.changed(flags(rightCommand, [], at: 10.1), profile: command)
    _ = keys.changed(flags(rightCommand, [.shift, .command], at: 20), profile: command)
    let withShift = keys.changed(flags(rightCommand, .shift, at: 20.1), profile: command)
    #expect(afterShift.action == nil)
    #expect(withShift.action == nil)
}

@Test("한 수식키를 누르면 다른 수식키의 tap 은 취소된다")
func modifiersCancelEachOther() {
    var keys = ModifierKeys()
    let all = profile([.rightCommand, .rightOption, .capsLock])
    _ = keys.changed(flags(capsLock, .control, at: 10), profile: all)
    _ = keys.changed(flags(rightCommand, [.control, .command], at: 10.02), profile: all)
    let commandUp = keys.changed(flags(rightCommand, .control, at: 10.04), profile: all)
    let capsUp = keys.changed(flags(capsLock, [], at: 10.1), profile: all)
    #expect(commandUp.action == nil)  // 누를 때 Control(Caps Lock)이 함께였다
    #expect(capsUp.action == nil)  // 오른쪽 ⌘ 가 끼었다
}

@Test("⌘C·⌘Tab 처럼 사이에 key·mouse 가 눌렸으면 tap 이 아니다 (입력기가 그 key 를 못 봤어도)")
func keyInBetween() {
    var keys = ModifierKeys()
    let command = profile([.rightCommand])
    _ = keys.changed(flags(rightCommand, .command, at: 10, activity: [1]), profile: command)
    let up = keys.changed(flags(rightCommand, [], at: 10.1, activity: [2]), profile: command)
    #expect(up.action == nil)
}

@Test("key 를 치면 누르고 있던 수식키는 tap 이 아니다")
func keyDownCancels() {
    var keys = ModifierKeys()
    let command = profile([.rightCommand])
    _ = keys.changed(flags(rightCommand, .command, at: 10), profile: command)
    keys.cancel()
    #expect(keys.changed(flags(rightCommand, [], at: 10.1), profile: command).action == nil)
}

@Test("한/영 전환 없는 app — 수식키는 아무 일도 하지 않는다, Caps Lock 의 timer 도 없다")
func passThroughModifiers() {
    var keys = ModifierKeys()
    let passed = profile([.rightCommand, .capsLock], passThrough: true)
    #expect(tap(&keys, rightCommand, .command, profile: passed) == nil)
    #expect(keys.changed(flags(capsLock, .control, at: 20), profile: passed) == ModifierKeys.Result())
}
