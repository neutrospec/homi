/// 실제 입력 시작의 mode 초기화. mode 자체는 ModeMemory 하나에 있으며 여기에는 시작 여부·app 식별 상태만 둔다.
/// client 에 묻거나 호출하지 않으므로 재진입할 수 있는 작업 밖에서 짧게 사용한다.
public struct ModeActivation: Sendable {
    public private(set) var needsStart = true
    /// ID 를 모른 채 조합하거나 mode 를 바꿨을 때만, 그 선택을 늦은 ID 보정에서 이어 간다.
    private var fallbackInputApp: String?
    private var generation: UInt64 = 0

    /// client 질의 중 들어온 새 activation 을 이전 입력의 결과가 소비하지 않도록 시작을 식별한다.
    public struct FallbackInput: Sendable {
        fileprivate let generation: UInt64
        fileprivate let app: String
    }

    public init() {}

    public mutating func activate(resumingInput: Bool) {
        guard !resumingInput else { return }
        needsStart = true
        fallbackInputApp = nil
        generation &+= 1
    }

    /// client 의 실제 ID(또는 그 cache)에서만 시작 규칙을 적용한다. fallback 의 기억은 reset 하지 않는다.
    public mutating func prepare(app: InputApp, profile: AppProfile, memory: inout ModeMemory) -> Mode {
        if case .client(let id) = app {
            if needsStart {
                needsStart = false
                generation &+= 1
                return memory.activate(id.bundleID, profile: profile)
            }
            if let fallbackInputApp {
                // 같은 입력 시작에서 ID 만 늦게 알아냈다. 지금 선택된 mode 를 실제 app 의 기억으로 옮긴다.
                // 새 activation 의 startsInEnglish 는 다음 실제 시작 때 적용한다.
                memory.remember(memory.mode(for: fallbackInputApp), for: id.bundleID)
                self.fallbackInputApp = nil
                generation &+= 1
            }
        }
        return memory.mode(for: app.bundleID)
    }

    /// Session 판단·client 질의 전에 시작을 잡는다. 통과하는 key 자체로는 시작 규칙을 소비하지 않는다.
    public func beginInput(app: InputApp) -> FallbackInput? {
        guard case .fallback(let id) = app else { return nil }
        return FallbackInput(generation: generation, app: id)
    }

    /// 판단 결과를 client 에 반영하기 전에 호출한다. composing 은 한자 후보의 조합도 포함한다.
    public mutating func inputHandled(_ input: FallbackInput?, modeChanged: Bool, composing: Bool) {
        guard let input, input.generation == generation, modeChanged || composing else { return }
        needsStart = false
        fallbackInputApp = input.app
    }
}
