/// 이 입력칸에서 homi 가 따를 규칙 — 주인의 설정(`Preferences`)과 app 의 결함에 맞춘 우회를 합친 것 (`AppRules.profile`).
public struct AppProfile: Sendable, Equatable {
    /// 입력칸이 활성화될 때마다 영문으로 시작한다.
    public var startsInEnglish = false
    /// 이 key 를 치면 조합을 확정하고 영문으로 — key 자체는 app 에 그대로 간다.
    public var englishTriggers: [Trigger] = []
    /// 조합 중에 치면 app 이 그 key 를 잃거나 다르게 쓰는 key (key code).
    /// 조합을 확정한 뒤 그 key 는 먹고 **다시 보낸다** — 두 번째로 도착할 때는 조합이 없다.
    public var resendWhileComposing: Set<UInt16> = []
    /// ⌥↩ 가 이미 입력된 글자(방금 친 단어·선택 영역)를 한자로 바꾸는가. false 면 조합 중인 글자만.
    /// terminal: 선택 영역은 입력이 아니라 화면의 출력이고(Ghostty 는 그것을 `selectedRange` 로 알려 준다), 보낸 글자는 고칠 수 없다.
    /// Office: 위치를 준 교체에 깨진다 (docs/research/app-compat-and-hangul.md).
    public var convertsEnteredText = true
    /// 한/영 전환 없는 app — homi 가 한/영 전환도 조합도 하지 않고 key 를 그대로 넘긴다 (주인 설정).
    public var passThrough = false
    /// 한/영 전환 key (주인 설정) — 수식키 tap 은 `ModifierKeys` 가, Shift+Space 는 `Session` 이 본다.
    public var toggleKeys: Set<Preferences.ToggleKey> = Preferences.standard.toggleKeys
    /// 한자 변환 key (주인 설정 — 한/영 전환과 겹치지 않게 정리된 것).
    public var hanjaKey: Preferences.HanjaKey = .optionReturn
    /// 방금 친 단어도 한자로 (Apple 방식, 주인 설정).
    public var hanjaRecentWord = true
    /// app 이 입력기의 글자를 받지 않고 key 를 homi 아래의 keyboard layout 으로 직접 글자로 바꾼다 — 한/영을 layout 으로 알린다
    /// (`keyboardLayout(in:)`). 원격 화면(Remote Desktop)이 그렇다.
    public var keyboardLayoutFollowsMode = false

    public init(
        startsInEnglish: Bool = false, englishTriggers: [Trigger] = [], resendWhileComposing: Set<UInt16> = [],
        convertsEnteredText: Bool = true, passThrough: Bool = false,
        toggleKeys: Set<Preferences.ToggleKey> = Preferences.standard.toggleKeys,
        hanjaKey: Preferences.HanjaKey = .optionReturn, hanjaRecentWord: Bool = true, keyboardLayoutFollowsMode: Bool = false
    ) {
        self.startsInEnglish = startsInEnglish
        self.englishTriggers = englishTriggers
        self.resendWhileComposing = resendWhileComposing
        self.convertsEnteredText = convertsEnteredText
        self.passThrough = passThrough
        self.toggleKeys = toggleKeys
        self.hanjaKey = hanjaKey
        self.hanjaRecentWord = hanjaRecentWord
        self.keyboardLayoutFollowsMode = keyboardLayoutFollowsMode
    }

    /// homi 아래에 둘 keyboard layout — homi 가 넘긴 key 는 이것으로 글자가 된다. 늘 ABC 다 (한글 모드의 ` 도 ` 가 된다).
    /// 예외: `keyboardLayoutFollowsMode` 인 app 의 한글 모드는 두벌식 layout — key 마다 자모를 내고, 그 자모가 원격에서 한글이 된다.
    public func keyboardLayout(in mode: Mode) -> String {
        keyboardLayoutFollowsMode && !passThrough && mode == .korean
            ? "com.apple.keylayout.2SetHangul" : "com.apple.keylayout.ABC"
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

/// app 별 규칙 — 주인의 설정(`Preferences`)에 app 의 결함에 맞춘 우회를 더한다.
/// 우회는 주인이 고르는 것이 아니라 app 의 동작에 딸린 것이라 source 의 표(`quirks`)에 둔다 — 재현 증거가 있는 것만, 바꾸면 다시 build·설치한다.
/// 각 app 의 사실과 까닭, 확인한 version 은 원장 `docs/apps/<app>.md` 에 있다 — 바꾸기 전에 읽고, 바꾼 뒤에 갱신한다.
public enum AppRules {
    public static func profile(for app: String, preferences: Preferences = .standard) -> AppProfile {
        var profile = quirks[app] ?? AppProfile()
        profile.startsInEnglish = preferences.englishStartApps.contains(app)
        if preferences.escapeApps.contains(app) { profile.englishTriggers.insert(esc, at: 0) }
        profile.passThrough = preferences.passThroughApps.contains(app)
        profile.toggleKeys = preferences.toggleKeys
        profile.hanjaKey = preferences.effectiveHanjaKey
        profile.hanjaRecentWord = preferences.hanjaRecentWord
        return profile
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
    /// 이미 보낸 글자는 고칠 수 없으니 한자는 조합 중인 글자만.
    private static let terminal = AppProfile(
        resendWhileComposing: [returnKey, enter, escape, tab], convertsEnteredText: false)

    private static let quirks: [String: AppProfile] = [
        "com.googlecode.iterm2": terminal,
        // tmux prefix(Ctrl-B, Ctrl-A — Ctrl 단독일 때만)도 영문으로 — Hammerspoon 에서 옮긴 주인의 규칙, 설정 창에는 두지 않았다
        "com.mitchellh.ghostty": AppProfile(
            englishTriggers: [ctrlB, ctrlA], resendWhileComposing: terminal.resendWhileComposing,
            convertsEnteredText: false),
        "dev.commandline.waveterm": AppProfile(convertsEnteredText: false),  // terminal (xterm.js)
        "com.apple.Terminal": AppProfile(convertsEnteredText: false),

        // ⌥↩ 는 조합 중인 글자만 (`convertsEnteredText` 의 설명)
        "com.microsoft.Word": AppProfile(convertsEnteredText: false),
        "com.microsoft.Excel": AppProfile(convertsEnteredText: false),
        "com.microsoft.Powerpoint": AppProfile(convertsEnteredText: false),

        // 조합 중 Enter 는 marked text 가 있으면 전송 대신 줄바꿈 — TelegramSwift ChatInputTextView.keyDown (source 확인)
        "ru.keepcoder.Telegram": AppProfile(resendWhileComposing: [returnKey, enter]),

        // 원격 화면은 입력기의 글자를 받지 않고, key 를 이 Mac 의 keyboard layout 으로 글자로 바꿔 보낸다 —
        // 한/영은 원격의 입력 소스가 아니라 이 layout 이 정한다 (docs/apps/remote-desktop.md, 2026-09-26 주인 + log)
        "com.apple.RemoteDesktop": AppProfile(keyboardLayoutFollowsMode: true),
    ]
}
