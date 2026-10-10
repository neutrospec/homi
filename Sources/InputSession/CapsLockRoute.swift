/// Caps Lock 의 목적지 — HID 적용은 app 층이 하고, 여기서는 설정과 현재 app 만으로 정한다.
public enum CapsLockRoute: Sendable, Equatable {
    case system
    case homi
    case windows(Preferences.WindowsCapsLockKey)

    public static func resolve(homiSelected: Bool, app: String, preferences: Preferences) -> Self {
        guard homiSelected, preferences.toggleKeys.contains(.capsLock) else { return .system }
        if app == AppRules.windowsAppID, preferences.windowsAppCapsLock { return .windows(preferences.windowsAppCapsLockKey) }
        return preferences.passThroughApps.contains(app) ? .system : .homi
    }
}
