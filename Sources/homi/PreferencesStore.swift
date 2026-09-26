import Foundation
import InputSession
import Synchronization

/// 주인의 설정 — 설정 창이 바꾸고, key 처리는 memory 에서 읽는다 (key 처리 중에 file 을 읽지 않는다).
nonisolated let preferences = Mutex(PreferencesStore.load())

/// 설정은 UserDefaults 에 JSON 하나로 남는다. 읽을 수 없으면 기본값(`Preferences.standard`).
nonisolated enum PreferencesStore {
    private static let key = "preferences"

    static func load() -> Preferences {
        guard let data = UserDefaults.standard.data(forKey: key),
            let value = try? JSONDecoder().decode(Preferences.self, from: data)
        else { return .standard }
        return value
    }

    /// 바꾸고 저장하고 알린다 — Caps Lock remap 이 설정을 따라가야 한다 (`SourceWatcher`).
    static func update(_ value: Preferences) {
        preferences.withLock { $0 = value }
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
        NotificationCenter.default.post(name: .homiPreferencesChanged, object: nil)
    }
}

extension Notification.Name {
    /// 설정이 바뀌었다.
    nonisolated static let homiPreferencesChanged = Notification.Name("homiPreferencesChanged")
}
