/// app 하나에 대한 규칙.
public struct AppProfile: Sendable, Equatable {
    /// 입력칸이 활성화될 때마다 영문으로 시작한다.
    public var startsInEnglish = false
    /// 이 key 를 치면 조합을 확정하고 영문으로 — key 자체는 app 에 그대로 간다.
    public var englishTriggers: [Trigger] = []
    /// 조합 중에 치면 app 이 그 key 를 잃거나 다르게 쓰는 key (key code).
    /// 조합을 확정한 뒤 그 key 는 먹고 **다시 보낸다** — 두 번째로 도착할 때는 조합이 없다.
    public var resendWhileComposing: Set<UInt16> = []

    public init(startsInEnglish: Bool = false, englishTriggers: [Trigger] = [], resendWhileComposing: Set<UInt16> = []) {
        self.startsInEnglish = startsInEnglish
        self.englishTriggers = englishTriggers
        self.resendWhileComposing = resendWhileComposing
    }
}

/// 영문 전환 trigger key.
public struct Trigger: Sendable, Equatable {
    public var keyCode: UInt16
    /// nil 이면 수식키 무관. 있으면 정확히 그 수식키만 — 다른 수식키가 함께 눌리면 아니다 (Caps Lock 은 무시).
    public var modifiers: Modifiers?

    public init(keyCode: UInt16, modifiers: Modifiers? = nil) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    func matches(_ key: KeyEvent) -> Bool {
        guard key.keyCode == keyCode else { return false }
        guard let modifiers else { return true }
        return key.modifiers.subtracting(.capsLock) == modifiers
    }
}

/// app 별 규칙 표 — 주인의 요구사항(AGENTS.md "앱별 상태")과 재현 증거가 있는 우회만 둔다. 바꾸면 다시 build·설치한다.
public enum AppRules {
    public static func profile(for app: String) -> AppProfile {
        table[app] ?? AppProfile()
    }

    private static let escape: UInt16 = 53
    private static let returnKey: UInt16 = 36
    private static let enter: UInt16 = 76  // keypad
    private static let tab: UInt16 = 48

    private static let esc = Trigger(keyCode: escape)
    private static let ctrlB = Trigger(keyCode: 11, modifiers: .control)
    private static let ctrlA = Trigger(keyCode: 0, modifiers: .control)

    /// native terminal 은 조합 중에 누른 Enter·ESC·Tab 을 음절 확정에만 쓰고 key 를 버린다
    /// (source 확인: Ghostty `SurfaceView_AppKit.keyDown` — markedTextBefore 면 확정 글자만 보내고 화살표만 다시 보낸다).
    private static let terminal = AppProfile(englishTriggers: [esc], resendWhileComposing: [returnKey, enter, escape, tab])

    private static let table: [String: AppProfile] = [
        // 활성화될 때마다 영문 (Hammerspoon 규칙에서 옮김)
        "at.obdev.LaunchBar": AppProfile(startsInEnglish: true),
        "com.apple.RemoteDesktop": AppProfile(startsInEnglish: true),
        "com.microsoft.rdc.macos": AppProfile(startsInEnglish: true),  // Windows App

        // ESC → 영문 (Hammerspoon 규칙에서 옮김). Chromium 계열은 조합 중 ESC 도 page 에 한 번 간다 (조사).
        "com.microsoft.VSCode": AppProfile(englishTriggers: [esc]),
        "com.microsoft.VSCodeInsiders": AppProfile(englishTriggers: [esc]),
        "md.obsidian": AppProfile(englishTriggers: [esc]),
        "dev.commandline.waveterm": AppProfile(englishTriggers: [esc]),

        "com.googlecode.iterm2": terminal,
        // Ghostty 는 tmux prefix 도 (Ctrl-B, Ctrl-A — Ctrl 단독일 때만)
        "com.mitchellh.ghostty": AppProfile(
            englishTriggers: [esc, ctrlB, ctrlA], resendWhileComposing: terminal.resendWhileComposing),

        // 조합 중 Enter 는 marked text 가 있으면 전송 대신 줄바꿈 — TelegramSwift ChatInputTextView.keyDown (source 확인)
        "ru.keepcoder.Telegram": AppProfile(resendWhileComposing: [returnKey, enter]),

        // ESC → 영문 (주인 요청, 2026-09-25 — IdeaVim 등)
        "com.jetbrains.intellij": AppProfile(englishTriggers: [esc]),
        "com.jetbrains.intellij.ce": AppProfile(englishTriggers: [esc]),
    ]
}
