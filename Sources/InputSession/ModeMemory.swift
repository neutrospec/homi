/// app 별 한/영 기억 (AGENTS.md "앱별 상태"). 처음 보는 app 은 영문으로 시작한다.
///
/// key 마다 그 입력칸의 app 으로 조회한다 — activate 알림이 늦거나 빠져도 틀리지 않는다 (조사: IMK lifecycle 을 믿지 말 것).
public struct ModeMemory: Sendable, Equatable {
    public private(set) var modes: [String: Mode]

    public init(modes: [String: Mode] = [:]) {
        self.modes = modes
    }

    public func mode(for app: String) -> Mode {
        modes[app] ?? .english
    }

    public mutating func remember(_ mode: Mode, for app: String) {
        modes[app] = mode
    }

    /// app 의 입력칸이 활성화될 때. 늘 영문으로 시작하는 app 은 영문으로 되돌린다.
    public mutating func activate(_ app: String, profile: AppProfile) -> Mode {
        if profile.startsInEnglish { modes[app] = .english }
        return mode(for: app)
    }
}
