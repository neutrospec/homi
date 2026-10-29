import Foundation
import Testing
@testable import InputSession

@Test("Windows App·Emacs 의 Caps Lock 전달은 기본값에서 꺼짐 — 다른 app 의 경로도 그대로")
func capsLockRouteDefaults() {
    let settings = Preferences.standard
    #expect(!settings.windowsAppCapsLock)
    #expect(!settings.emacsCapsLock)
    #expect(CapsLockRoute.resolve(homiSelected: true, app: AppRules.windowsAppID, preferences: settings) == .system)
    #expect(CapsLockRoute.resolve(homiSelected: true, app: AppRules.emacsAppID, preferences: settings) == .system)
    #expect(CapsLockRoute.resolve(homiSelected: true, app: "com.apple.TextEdit", preferences: settings) == .homi)
}

@Test("Windows 목적지는 Windows App 에만 적용하며, ABC 와 Caps Lock 을 고르지 않은 설정에서는 원래 key", arguments: Preferences.WindowsCapsLockKey.allCases)
func capsLockRouteWindowsScope(key: Preferences.WindowsCapsLockKey) {
    var settings = Preferences.standard
    settings.windowsAppCapsLock = true
    settings.windowsAppCapsLockKey = key
    #expect(CapsLockRoute.resolve(homiSelected: true, app: AppRules.windowsAppID, preferences: settings) == .windows(key))
    #expect(CapsLockRoute.resolve(homiSelected: true, app: "com.apple.TextEdit", preferences: settings) == .homi)
    #expect(CapsLockRoute.resolve(homiSelected: true, app: AppRules.emacsAppID, preferences: settings) == .system)
    #expect(CapsLockRoute.resolve(homiSelected: false, app: AppRules.windowsAppID, preferences: settings) == .system)
    settings.toggleKeys.remove(.capsLock)
    #expect(CapsLockRoute.resolve(homiSelected: true, app: AppRules.windowsAppID, preferences: settings) == .system)
    settings.toggleKeys.insert(.capsLock)
    settings.windowsAppCapsLock = false
    #expect(CapsLockRoute.resolve(homiSelected: true, app: AppRules.windowsAppID, preferences: settings) == .system)
}

@Test("Windows 목적지 어느 쪽도 local mode 를 전환하거나 조합하지 않는다", arguments: Preferences.WindowsCapsLockKey.allCases)
func windowsCapsDoesNotOwnModeOrComposition(key: Preferences.WindowsCapsLockKey) {
    var settings = Preferences.standard
    settings.windowsAppCapsLock = true
    settings.windowsAppCapsLockKey = key
    settings.passThroughApps = []
    let profile = AppRules.profile(for: AppRules.windowsAppID, preferences: settings)
    #expect(profile.passThrough)
    var session = Session()
    let typed = session.handle(KeyEvent(keyCode: 5), mode: .korean, profile: profile)
    #expect(typed == Outcome(handled: false, actions: [], mode: .korean))
    var modifiers = ModifierKeys()
    let press = modifiers.changed(ModifierEvent(keyCode: 54, modifiers: .command, time: 1, activity: .counter([]), isDown: true), profile: profile)
    let release = modifiers.changed(ModifierEvent(keyCode: 54, modifiers: [], time: 1.1, activity: .counter([]), isDown: false), profile: profile)
    #expect(press.action == nil)
    #expect(release.action == nil)
    #expect(!AppRules.profile(for: "com.apple.TextEdit", preferences: settings).passThrough)
}

@Test("옛 설정에서 Windows 옵션은 저절로 켜지지 않고, 저장한 목적지는 복원된다", arguments: Preferences.WindowsCapsLockKey.allCases)
func windowsCapsPreferencePersistence(key: Preferences.WindowsCapsLockKey) throws {
    let old = try JSONDecoder().decode(Preferences.self, from: Data(#"{"toggleKeys":["capsLock"]}"#.utf8))
    #expect(!old.windowsAppCapsLock)
    #expect(old.windowsAppCapsLockKey == .hangul)
    let trial = try JSONDecoder().decode(Preferences.self, from: Data(#"{"toggleKeys":["capsLock"],"windowsAppCapsLock":true}"#.utf8))
    #expect(trial.windowsAppCapsLock)
    #expect(trial.windowsAppCapsLockKey == .hangul)
    #expect(trial.toggleKeys == [.capsLock])
    var settings = Preferences.standard
    settings.windowsAppCapsLock = true
    settings.windowsAppCapsLockKey = key
    let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(settings))
    #expect(restored == settings)
}

@Test("알 수 없는 Windows 목적지를 읽어도 주인의 다른 설정은 잃지 않는다")
func unknownWindowsCapsKeyPreservesOtherPreferences() throws {
    let value = try JSONDecoder().decode(Preferences.self, from: Data(#"{"toggleKeys":["capsLock"],"windowsAppCapsLock":true,"windowsAppCapsLockKey":"future","passThroughApps":["example"]}"#.utf8))
    #expect(value.windowsAppCapsLockKey == .hangul)
    #expect(value.windowsAppCapsLock)
    #expect(value.toggleKeys == [.capsLock])
    #expect(value.passThroughApps == ["example"])
}

@Test("Emacs 의 Caps Lock 은 옵션을 켰을 때만 전달하고 ABC·Caps Lock 해제에서는 원래 key 다")
func emacsCapsLockScope() {
    var settings = Preferences.standard
    settings.emacsCapsLock = true
    settings.windowsAppCapsLock = true
    settings.windowsAppCapsLockKey = .rightAlt
    #expect(CapsLockRoute.resolve(homiSelected: true, app: AppRules.emacsAppID, preferences: settings) == .emacs)
    #expect(CapsLockRoute.resolve(homiSelected: false, app: AppRules.emacsAppID, preferences: settings) == .system)
    #expect(CapsLockRoute.resolve(homiSelected: true, app: "com.apple.TextEdit", preferences: settings) == .homi)
    #expect(CapsLockRoute.resolve(homiSelected: true, app: AppRules.windowsAppID, preferences: settings) == .windows(.rightAlt))
    settings.toggleKeys = [.shiftSpace]
    #expect(CapsLockRoute.resolve(homiSelected: true, app: AppRules.emacsAppID, preferences: settings) == .system)
    settings.toggleKeys.insert(.capsLock)
    settings.emacsCapsLock = false
    #expect(CapsLockRoute.resolve(homiSelected: true, app: AppRules.emacsAppID, preferences: settings) == .system)
    #expect(CapsLockRoute.resolve(homiSelected: true, app: AppRules.windowsAppID, preferences: settings) == .windows(.rightAlt))
    settings.passThroughApps.removeAll { $0 == AppRules.emacsAppID }
    #expect(CapsLockRoute.resolve(homiSelected: true, app: AppRules.emacsAppID, preferences: settings) == .homi)
    #expect(!AppRules.profile(for: AppRules.emacsAppID, preferences: settings).passThrough)
    settings.emacsCapsLock = true
    #expect(CapsLockRoute.resolve(homiSelected: true, app: AppRules.emacsAppID, preferences: settings) == .emacs)
    settings.passThroughApps.append("example.other")
    #expect(CapsLockRoute.resolve(homiSelected: true, app: "example.other", preferences: settings) == .system)
}

@Test("Emacs 전달을 켜면 목록에서 빼도 F18·Shift+Space·한글 key 를 넘기고 local mode·조합은 건드리지 않는다")
func emacsKeepsItsOwnInputMethod() {
    var settings = Preferences.standard
    settings.emacsCapsLock = true
    settings.passThroughApps = []
    settings.toggleKeys.insert(.shiftSpace)
    let profile = AppRules.profile(for: AppRules.emacsAppID, preferences: settings)
    #expect(profile.passThrough)
    #expect(!AppRules.profile(for: "com.apple.TextEdit", preferences: settings).passThrough)
    for mode in [Mode.english, Mode.korean] {
        var session = Session()
        for key in [KeyEvent(keyCode: 79), KeyEvent(keyCode: 49, modifiers: .shift), KeyEvent(keyCode: 0)] {
            let outcome = session.handle(key, mode: mode, profile: profile)
            #expect(outcome == Outcome(handled: false, actions: [], mode: mode))
        }
    }
}

@Test("옛 설정에서 Emacs 전달은 켜지지 않고, 저장한 선택과 Windows 목적지는 함께 복원된다", arguments: [false, true])
func emacsCapsPreferencePersistence(enabled: Bool) throws {
    var settings = try JSONDecoder().decode(Preferences.self, from: Data(#"{"toggleKeys":["capsLock"],"windowsAppCapsLock":true,"windowsAppCapsLockKey":"rightAlt"}"#.utf8))
    #expect(!settings.emacsCapsLock)
    #expect(settings.windowsAppCapsLock)
    #expect(settings.windowsAppCapsLockKey == .rightAlt)
    settings.emacsCapsLock = enabled
    let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(settings))
    #expect(restored == settings)
    #expect(CapsLockRoute.resolve(homiSelected: true, app: AppRules.emacsAppID, preferences: restored) == (enabled ? .emacs : .system))
    #expect(CapsLockRoute.resolve(homiSelected: true, app: AppRules.windowsAppID, preferences: restored) == .windows(.rightAlt))
}
