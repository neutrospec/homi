/// Caps Lock 의 목적지 — HID 적용은 app 층이 하고, 여기서는 설정과 현재 app 만으로 정한다.
public enum CapsLockRoute: Sendable, Equatable {
    case system
    case homi
    case windows(Preferences.WindowsCapsLockKey)
    /// Emacs 자체 입력기 전환용 F18. 조합·모드는 Emacs 가 소유한다.
    case emacs

    public static func resolve(homiSelected: Bool, app: String, preferences: Preferences) -> Self {
        guard homiSelected, preferences.toggleKeys.contains(.capsLock) else { return .system }
        if app == AppRules.windowsAppID, preferences.windowsAppCapsLock { return .windows(preferences.windowsAppCapsLockKey) }
        if app == AppRules.emacsAppID, preferences.emacsCapsLock { return .emacs }
        if preferences.passThroughApps.contains(app) { return .system }
        return .homi
    }
}
