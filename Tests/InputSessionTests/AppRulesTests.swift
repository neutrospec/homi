import Testing

@testable import InputSession

let escape = KeyEvent(keyCode: 53)
let returnKey = KeyEvent(keyCode: 36)

func ctrl(_ letter: Character, _ extra: Modifiers = []) -> KeyEvent {
    key(letter, extra.union(.control))
}

// MARK: - 규칙 표 (AGENTS.md "앱별 상태" 와 같아야 한다)

@Test("활성화될 때마다 영문으로 시작하는 app", arguments: [
    "at.obdev.LaunchBar", "com.apple.RemoteDesktop", "com.microsoft.rdc.macos",
])
func startsInEnglish(app: String) {
    #expect(AppRules.profile(for: app).startsInEnglish)
}

@Test("ESC 가 영문 trigger 인 app — 수식키 무관", arguments: [
    "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "md.obsidian", "com.googlecode.iterm2",
    "dev.commandline.waveterm", "com.mitchellh.ghostty", "com.jetbrains.intellij",
])
func escapeTriggers(app: String) {
    let triggers = AppRules.profile(for: app).englishTriggers
    #expect(triggers.contains { $0.matches(escape) })
    #expect(triggers.contains { $0.matches(KeyEvent(keyCode: 53, modifiers: .shift)) })
}

@Test("Ghostty 의 Ctrl-B·Ctrl-A 는 Ctrl 단독일 때만")
func ghosttyTmuxTriggers() {
    let triggers = AppRules.profile(for: "com.mitchellh.ghostty").englishTriggers
    #expect(triggers.contains { $0.matches(ctrl("b")) })
    #expect(triggers.contains { $0.matches(ctrl("a")) })
    #expect(triggers.contains { $0.matches(ctrl("b", .capsLock)) })
    #expect(!triggers.contains { $0.matches(ctrl("b", .shift)) })
    #expect(!triggers.contains { $0.matches(key("b")) })
    #expect(!triggers.contains { $0.matches(ctrl("c")) })
}

@Test("규칙이 없는 app 은 기본")
func unknownApp() {
    #expect(AppRules.profile(for: "com.example.unknown") == AppProfile())
}

// MARK: - 규칙에 따른 동작

@Test("trigger 는 확정하고 영문으로, key 는 app 으로")
func triggerSwitchesToEnglish() {
    var session = Session()
    let profile = AppRules.profile(for: "com.microsoft.VSCode")
    _ = press("gks", &session)
    let outcome = session.handle(escape, mode: .korean, profile: profile)
    #expect(outcome == Outcome(handled: false, actions: [.insert("한")], mode: .english))
}

@Test("trigger 는 영문 모드에서도 key 를 그대로 넘긴다")
func triggerInEnglish() {
    var session = Session()
    let outcome = session.handle(escape, mode: .english, profile: AppRules.profile(for: "md.obsidian"))
    #expect(outcome == Outcome(handled: false, actions: [], mode: .english))
}

@Test("terminal 에서 조합 중 ESC — 확정하고 영문으로, ESC 는 먹고 다시 보낸다")
func terminalEscapeWhileComposing() {
    var session = Session()
    let profile = AppRules.profile(for: "com.mitchellh.ghostty")
    _ = press("gks", &session)
    let first = session.handle(escape, mode: .korean, profile: profile)
    #expect(first == Outcome(handled: true, actions: [.insert("한")], mode: .english, resend: true))
    // 다시 보낸 ESC 가 도착할 때는 조합이 없다 — 그대로 넘어간다.
    let second = session.handle(escape, mode: first.mode, profile: profile)
    #expect(second == Outcome(handled: false, actions: [], mode: .english))
}

@Test("Telegram 에서 조합 중 Enter — 확정하고 먹고 다시 보낸다 (두 번째 Enter 가 전송)")
func telegramEnterWhileComposing() {
    var session = Session()
    let profile = AppRules.profile(for: "ru.keepcoder.Telegram")
    _ = press("gks", &session)
    let first = session.handle(returnKey, mode: .korean, profile: profile)
    #expect(first == Outcome(handled: true, actions: [.insert("한")], mode: .korean, resend: true))
    let second = session.handle(returnKey, mode: .korean, profile: profile)
    #expect(second == Outcome(handled: false, actions: [], mode: .korean))
}

@Test("조합 중이 아니면 다시 보내지 않는다")
func noResendWithoutComposing() {
    var session = Session()
    let outcome = session.handle(returnKey, mode: .korean, profile: AppRules.profile(for: "ru.keepcoder.Telegram"))
    #expect(outcome == Outcome(handled: false, actions: [], mode: .korean))
}

@Test("규칙이 없는 app 의 조합 중 Enter 는 확정하고 넘긴다")
func plainEnter() {
    var session = Session()
    _ = press("gks", &session)
    let outcome = session.handle(returnKey, mode: .korean, profile: AppProfile())
    #expect(outcome == Outcome(handled: false, actions: [.insert("한")], mode: .korean))
}

@Test("IntelliJ 도 ESC → 영문 (주인 요청)", arguments: ["com.jetbrains.intellij", "com.jetbrains.intellij.ce"])
func intellijEscape(app: String) {
    #expect(AppRules.profile(for: app).englishTriggers.contains { $0.matches(escape) })
}

// MARK: - app 별 기억

@Test("처음 보는 app 은 영문, 그 뒤로는 app 마다 따로 기억한다")
func memoryPerApp() {
    var memory = ModeMemory()
    #expect(memory.mode(for: "com.example.a") == .english)
    memory.remember(.korean, for: "com.example.a")
    #expect(memory.mode(for: "com.example.a") == .korean)
    #expect(memory.mode(for: "com.example.b") == .english)
}

@Test("활성화 — 늘 영문으로 시작하는 app 만 영문으로 되돌린다")
func activation() {
    var memory = ModeMemory(modes: ["at.obdev.LaunchBar": .korean, "com.example.a": .korean])
    let launchBar = memory.activate("at.obdev.LaunchBar", profile: AppRules.profile(for: "at.obdev.LaunchBar"))
    let other = memory.activate("com.example.a", profile: AppRules.profile(for: "com.example.a"))
    #expect(launchBar == .english)
    #expect(other == .korean)
}
