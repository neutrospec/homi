/// 실제 입력 시작의 mode 초기화. mode 자체는 ModeMemory 하나에 있으며 여기에는 시작 여부·app 식별 상태만 둔다.
/// client 에 묻거나 호출하지 않으므로 재진입할 수 있는 작업 밖에서 짧게 사용한다.
public struct ModeActivation: Sendable {
    public private(set) var needsStart = true
    /// ID 를 모른 채 이미 입력을 시작했다면, 늦은 ID 보정은 새 시작이 아니다.
    private var fallbackInputApp: String?

    public init() {}

    public mutating func activate(resumingInput: Bool) {
        guard !resumingInput else { return }
        needsStart = true
        fallbackInputApp = nil
    }

    /// trusted 는 client 의 실제 ID(또는 그 cache)다. fallback app 의 시작 규칙으로 기억을 reset 하지 않는다.
    public mutating func prepare(app: String, trusted: Bool, profile: AppProfile, memory: inout ModeMemory) -> Mode {
        if trusted {
            if needsStart {
                needsStart = false
                return memory.activate(app, profile: profile)
            }
            if let fallbackInputApp {
                // 같은 입력 시작에서 ID 만 늦게 알아냈다. 지금 선택된 mode 를 실제 app 의 기억으로 옮긴다.
                // 새 activation 의 startsInEnglish 는 다음 실제 시작 때 적용한다.
                memory.remember(memory.mode(for: fallbackInputApp), for: app)
                self.fallbackInputApp = nil
            }
        }
        return memory.mode(for: app)
    }

    /// keyDown 또는 뜻이 있는 modifier action 전에 호출한다. client 호출 중 새 시작 intent 가 들어와도 뒤에서 지우지 않는다.
    public mutating func inputStarted(app: String, trusted: Bool) {
        guard !trusted, needsStart || fallbackInputApp != nil else { return }
        needsStart = false
        fallbackInputApp = app
    }
}
