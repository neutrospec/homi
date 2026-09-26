/// 주인이 설정 창에서 고르는 것 — homi 가 저장하고, key 마다 `AppRules.profile(for:preferences:)` 가 규칙에 섞는다.
/// app 의 결함에 맞춘 우회(다시 보내기, 한자 제한, Ghostty 의 Ctrl-B·Ctrl-A)는 여기가 아니라 `AppRules` 의 표에 있다.
public struct Preferences: Sendable, Equatable, Codable {
    /// 한/영 전환 key — 여럿을 함께 켤 수 있다.
    public enum ToggleKey: String, Sendable, Codable, CaseIterable {
        /// 짧게 = 전환, 길게 = 대문자 고정. homi 가 선택된 동안 오른쪽 Control 로 remap 해서 받는다.
        case capsLock
        /// 짧게 = 전환. 다른 key 와 함께면 평소의 ⌘.
        case rightCommand
        /// 짧게 = 전환. 다른 key 와 함께면 평소의 ⌥ (`⌥a → å` 그대로).
        case rightOption
        /// terminal(Ghostty·iTerm2)에서는 영문 → 한글 전환 때 space 가 샌다 — 주인이 알고 고른다 (docs/lessons.md).
        case shiftSpace
    }

    /// 한자 변환 key — 하나. 수식키 tap 은 한/영 전환에 쓰지 않을 때만 한자 key 가 된다.
    public enum HanjaKey: String, Sendable, Codable, CaseIterable {
        case optionReturn
        case rightOption
        case rightCommand
    }

    public var toggleKeys: Set<ToggleKey>
    public var hanjaKey: HanjaKey
    /// 방금 친 단어도 한자로 바꾸는가 (Apple 방식 — 교체를 제대로 받는 app 에서만). false 면 조합 중인 글자와 선택 영역만.
    public var hanjaRecentWord: Bool
    /// 활성화될 때마다 영문으로 시작하는 app.
    public var englishStartApps: [String]
    /// ESC 로 영문 전환하는 app — 조합 중이면 확정하고, ESC 는 app 으로 간다.
    public var escapeApps: [String]
    /// 한/영 전환 없는 app — homi 가 한/영 전환도 조합도 하지 않고 key 를 그대로 넘긴다. Caps Lock 도 원래대로.
    /// app 자체의 입력기(Emacs)나 원격 컴퓨터의 입력기(Remote Desktop·Windows App)가 한/영을 맡는다.
    public var passThroughApps: [String]

    public init(
        toggleKeys: Set<ToggleKey>, hanjaKey: HanjaKey, hanjaRecentWord: Bool,
        englishStartApps: [String], escapeApps: [String], passThroughApps: [String]
    ) {
        self.toggleKeys = toggleKeys
        self.hanjaKey = hanjaKey
        self.hanjaRecentWord = hanjaRecentWord
        self.englishStartApps = englishStartApps
        self.escapeApps = escapeApps
        self.passThroughApps = passThroughApps
    }

    /// 처음 설치했을 때 — 설정 창이 생기기 전의 동작 그대로 (AGENTS.md 요구사항).
    public static let standard = Preferences(
        toggleKeys: [.capsLock, .rightCommand], hanjaKey: .optionReturn, hanjaRecentWord: true,
        englishStartApps: ["at.obdev.LaunchBar"],
        escapeApps: [
            "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "md.obsidian", "com.googlecode.iterm2",
            "dev.commandline.waveterm", "com.mitchellh.ghostty", "com.jetbrains.intellij", "com.jetbrains.intellij.ce",
        ],
        passThroughApps: ["com.apple.RemoteDesktop", "com.microsoft.rdc.macos", "org.gnu.Emacs"])

    /// 실제로 쓰는 한자 key — 한 key 는 한 가지 일만 한다. 고른 수식키를 한/영 전환에 쓰고 있으면 ⌥↩.
    public var effectiveHanjaKey: HanjaKey {
        switch hanjaKey {
        case .optionReturn: .optionReturn
        case .rightOption: toggleKeys.contains(.rightOption) ? .optionReturn : .rightOption
        case .rightCommand: toggleKeys.contains(.rightCommand) ? .optionReturn : .rightCommand
        }
    }

    /// 저장된 것에 없는 항목은 기본값으로 — homi 가 자라며 항목이 늘어도 옛 설정이 그대로 읽힌다.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let base = Self.standard
        toggleKeys = try container.decodeIfPresent(Set<ToggleKey>.self, forKey: .toggleKeys) ?? base.toggleKeys
        hanjaKey = try container.decodeIfPresent(HanjaKey.self, forKey: .hanjaKey) ?? base.hanjaKey
        hanjaRecentWord = try container.decodeIfPresent(Bool.self, forKey: .hanjaRecentWord) ?? base.hanjaRecentWord
        englishStartApps = try container.decodeIfPresent([String].self, forKey: .englishStartApps) ?? base.englishStartApps
        escapeApps = try container.decodeIfPresent([String].self, forKey: .escapeApps) ?? base.escapeApps
        passThroughApps = try container.decodeIfPresent([String].self, forKey: .passThroughApps) ?? base.passThroughApps
    }
}
