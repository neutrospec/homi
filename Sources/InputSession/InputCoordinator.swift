/// 입력 판단에 필요한 client 경계. 실제 IMK client 와 test client 가 같은 순서로 호출된다.
public protocol InputClient {
    func bundleIdentifier() -> String?
    func selectedText() -> String?
    func textBefore(_ count: Int) -> (text: String, end: Int)?
    func apply(_ actions: [Action])
}

/// 모든 controller 가 공유하는 app 별 mode. client 를 부르는 동안에는 memory 접근을 잡고 있지 않는다.
public protocol ModeStore {
    func withMemory<Result: Sendable>(_ operation: (inout ModeMemory) -> Result) -> Result
    func save(_ snapshot: ModeMemory)
}

/// app 식별 → mode 준비 → Session 판단 → mode 보존 → client 반영의 동기 경계.
/// AppKit event 해석·modifier 관찰·화면 표시는 adapter 가 맡는다. lifecycle 의 종료 정책은 SessionDriver 에 둔다.
public final class InputCoordinator {
    public let driver: SessionDriver
    /// 실제 client 에서 얻은 ID 만 cache 한다. fallback 은 다음 event 에 다시 확인한다.
    public private(set) var clientApp: ClientAppID?
    /// 종료 flush 와 실제 입력 event 를 구분한다. driver 의 depth 로 대신하면 새 시작을 continuation 으로 오인한다.
    public private(set) var inputDepth = 0
    public var needsStart: Bool { activation.needsStart }

    public enum Notice {
        case becameActive
        case received(app: String)
        case appResolved(app: String, mode: Mode, passThrough: Bool)
        case modePrepared(app: String, mode: Mode, passThrough: Bool)
        case modeChanged(app: String, mode: Mode, passThrough: Bool)
    }

    public struct Activation {
        public let app: InputApp
        public let mode: Mode
        public let passThrough: Bool
        public let layout: String
        public let resuming: Bool
    }

    private var activation = ModeActivation()
    private let modes: any ModeStore
    private let profile: (String) -> AppProfile
    private let fallbackApp: () -> String
    private let notice: (Notice) -> Void

    /// 생성 중에는 client·환경·callback 을 부르지 않는다. adapter 의 lazy 초기화 중 재진입을 피한다.
    public init(driver: SessionDriver = SessionDriver(), modes: any ModeStore,
        profile: @escaping (String) -> AppProfile, fallbackApp: @escaping () -> String,
        notice: @escaping (Notice) -> Void = { _ in }) {
        self.driver = driver
        self.modes = modes
        self.profile = profile
        self.fallbackApp = fallbackApp
        self.notice = notice
    }

    /// activate 에서는 client 에 묻지 않는다. ID 가 없거나 event 중이면 시작 intent 를 실제 입력까지 보존한다.
    public func activate() -> Activation {
        let resuming = inputDepth > 0 && !driver.hasExplicitEnd
        activation.activate(resumingInput: resuming)
        driver.activate()
        notice(.becameActive)
        if !driver.isHandlingEvent, inputDepth == 0, let clientApp { prepareMode(for: .client(clientApp)) }
        let app = clientApp.map(InputApp.client) ?? .fallback(fallbackApp())
        let profile = profile(app.bundleID)
        let mode = mode(for: app)
        let layoutMode: Mode = activation.needsStart && profile.startsInEnglish ? .english : mode
        return Activation(app: app, mode: mode, passThrough: profile.passThrough,
            layout: profile.keyboardLayout(in: layoutMode), resuming: resuming)
    }

    /// before·after 도 입력 경계 안에서 실행한다. after 의 caret 질의 도중 들어오는 종료도 client 반영 뒤 처리한다.
    @discardableResult
    public func keyDown(_ key: KeyEvent, client: any InputClient, before: () -> Void = {},
        canResend: () -> Bool = { false }, after: (Outcome, Bool) -> Void = { _, _ in }) -> Outcome {
        withInput(client: client) { app in
            prepareMode(for: app)
            before()
            let mode = mode(for: app)
            let input = activation.beginInput(app: app)
            var outcome = driver.perform({
                $0.handle(key, mode: mode, profile: profile(app.bundleID), selectedText: client.selectedText,
                    textBefore: client.textBefore)
            }, apply: { _ in })
            preserveInputMode(input, outcome: outcome, from: mode)
            if outcome.resend && !canResend() {
                // 다시 보낼 수 없으면 원래 key 를 넘긴다. 먹은 채 잃지 않는다.
                outcome.handled = false
                outcome.resend = false
            }
            switchMode(to: outcome.mode, from: mode, app: app)
            client.apply(outcome.actions)
            after(outcome, outcome.mode != mode)
            return outcome
        }
    }

    /// modifier 판정은 mode 준비 뒤에 한다. tap·hold 관찰은 adapter 에, 그 결과의 Session 처리는 여기 둔다.
    public func modifiersChanged(client: any InputClient, action: (String, AppProfile) -> ModifierKeys.Action?,
        showMode: (Mode) -> Void = { _ in }, capsLock: () -> Void = {}) {
        withInput(client: client) { app in
            prepareMode(for: app)
            let profile = profile(app.bundleID)
            guard let action = action(app.bundleID, profile) else { return }
            switch action {
            case .toggle:
                let mode = mode(for: app)
                let input = activation.beginInput(app: app)
                driver.perform({ $0.toggle(from: mode, profile: profile) }, apply: { outcome in
                    preserveInputMode(input, outcome: outcome, from: mode)
                    switchMode(to: outcome.mode, from: mode, app: app)
                    client.apply(outcome.actions)
                    showMode(outcome.mode)
                })
            case .hanja:
                let mode = mode(for: app)
                let input = activation.beginInput(app: app)
                driver.perform({
                    $0.hanjaTapped(mode: mode, profile: profile, selectedText: client.selectedText,
                        textBefore: client.textBefore)
                }, apply: { outcome in
                    if let outcome {
                        preserveInputMode(input, outcome: outcome, from: mode)
                        client.apply(outcome.actions)
                    }
                })
            case .capsLock:
                capsLock()
            }
        }
    }

    /// mouse 는 새 mode 를 초기화하지 않는다. 확정 대상은 event 의 sender 가 아니라 controller 에 묶인 client 다.
    public func mouseDown(client: any InputClient, before: () -> Void = {}, boundClient: () -> (any InputClient)?) {
        withInput(client: client) { _ in
            before()
            let target = boundClient()
            driver.end(.commitToClient) { target?.apply($0) }
        }
    }

    public func ignoredEvent(client: any InputClient) {
        withInput(client: client) { _ in }
    }

    private func withInput<Result>(client: any InputClient, _ body: (InputApp) -> Result) -> Result {
        inputDepth += 1
        defer { inputDepth -= 1 }
        return driver.withEvent {
            notice(.becameActive)
            // bundleIdentifier 질의도 재진입한다 — 반드시 SessionDriver 경계 안에 둔다.
            let app = resolveApp(client)
            notice(.received(app: app.bundleID))
            return body(app)
        }
    }

    private func resolveApp(_ client: any InputClient) -> InputApp {
        if let clientApp { return .client(clientApp) }
        guard let id = ClientAppID(client.bundleIdentifier()) else { return .fallback(fallbackApp()) }
        clientApp = id
        let app = InputApp.client(id)
        notice(.appResolved(app: id.bundleID, mode: mode(for: app), passThrough: profile(id.bundleID).passThrough))
        return app
    }

    private func mode(for app: InputApp) -> Mode { modes.withMemory { $0.mode(for: app.bundleID) } }

    private func prepareMode(for app: InputApp) {
        let profile = profile(app.bundleID)
        let initializing: Bool
        if case .client = app { initializing = activation.needsStart }
        else { initializing = false }
        let (mode, changed) = modes.withMemory { memory in
            let before = memory
            let mode = activation.prepare(app: app, profile: profile, memory: &memory)
            return (mode, memory != before ? memory : nil)
        }
        if let changed { modes.save(changed) }
        if initializing || changed != nil {
            notice(.modePrepared(app: app.bundleID, mode: mode, passThrough: profile.passThrough))
        }
    }

    private func switchMode(to mode: Mode, from old: Mode, app: InputApp) {
        guard mode != old else { return }
        let updated = modes.withMemory { memory in
            memory.remember(mode, for: app.bundleID)
            return memory
        }
        modes.save(updated)
        notice(.modeChanged(app: app.bundleID, mode: mode, passThrough: profile(app.bundleID).passThrough))
    }

    private func preserveInputMode(_ input: ModeActivation.FallbackInput?, outcome: Outcome, from mode: Mode) {
        // Session 의 mutating 접근이 끝난 뒤에만 읽는다. 진단 cache 를 판단에 쓰지 않는다.
        activation.inputHandled(input, modeChanged: outcome.mode != mode,
            composing: !driver.composing.isEmpty || driver.hasCandidates)
    }
}
