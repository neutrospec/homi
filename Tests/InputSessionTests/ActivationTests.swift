import Testing

@testable import InputSession

private let startingApp = "homi.tests.english-start"
private let fallbackApp = "homi.tests.fallback"

private final class ActivationModes: ModeStore {
    var memory = ModeMemory(modes: [startingApp: .korean, fallbackApp: .korean])
    var saved: [ModeMemory] = []
    var accessing = false

    func withMemory<Result: Sendable>(_ operation: (inout ModeMemory) -> Result) -> Result {
        #expect(!accessing)
        accessing = true
        defer { accessing = false }
        return operation(&memory)
    }

    func save(_ snapshot: ModeMemory) {
        #expect(!accessing)
        saved.append(snapshot)
    }
}

/// client 와 환경만 대신한다. app 식별·mode 준비·판단·반영 순서는 제품 coordinator 를 그대로 실행한다.
private final class ActivationHost: InputClient {
    let modes: ActivationModes
    lazy var coordinator = InputCoordinator(driver: SessionDriver(hanja: dictionary), modes: modes,
        profile: { [unowned self] in appProfile($0) }, fallbackApp: { [unowned self] in fallback })
    var driver: SessionDriver { coordinator.driver }
    var memory: ModeMemory {
        get { modes.memory }
        set { modes.memory = newValue }
    }
    var clientApp: String?
    var fallback: String
    var knownApp: String? { coordinator.clientApp?.bundleID }
    var inputDepth: Int { coordinator.inputDepth }
    var appProfile: (String) -> AppProfile = { AppProfile(startsInEnglish: $0 == startingApp || $0 == fallbackApp) }
    var text = ""
    var marked = ""
    var onBundleID: (() -> Void)?
    var onMark: (() -> Void)?
    var onInsert: (() -> Void)?
    var selection: () -> String? = { nil }

    init(clientApp: String? = startingApp, fallback: String = fallbackApp, modes: ActivationModes = ActivationModes()) {
        self.clientApp = clientApp
        self.fallback = fallback
        self.modes = modes
    }

    func activate() { _ = coordinator.activate() }

    func bundleIdentifier() -> String? {
        #expect(!modes.accessing)
        let callback = onBundleID
        onBundleID = nil
        callback?()
        return clientApp
    }

    func selectedText() -> String? {
        #expect(!modes.accessing)
        return selection()
    }

    func textBefore(_ count: Int) -> (text: String, end: Int)? { nil }

    func apply(_ actions: [Action]) {
        #expect(!modes.accessing)
        for action in actions {
            switch action {
            case .mark(let value):
                marked = value
                let callback = onMark
                onMark = nil
                callback?()
            case .insert(let value):
                text += value
                marked = ""
                let callback = onInsert
                onInsert = nil
                callback?()
            default: break
            }
        }
    }

    func type(_ letters: String) {
        for letter in letters {
            send(key(letter), passedText: String(letter))
        }
    }

    @discardableResult
    func send(_ event: KeyEvent, passedText: String = "") -> Outcome {
        let outcome = coordinator.keyDown(event, client: self)
        if !outcome.handled { text += passedText }
        return outcome
    }

    func toggle() {
        coordinator.modifiersChanged(client: self, action: { _, _ in .toggle })
    }

    func modifierWithoutAction() {
        coordinator.modifiersChanged(client: self, action: { _, _ in nil })
    }

    func mouseDown() { coordinator.mouseDown(client: self, boundClient: { self }) }

    func deactivate() { driver.deactivate(apply: apply) }
    func commit() { driver.end(.commitToClient, apply: apply) }
}

@Test("activation: mark 중 재활성화는 조합과 한글 mode 를 함께 이어 간다")
func activationKeepsModeDuringReentry() {
    let host = ActivationHost(fallback: startingApp)
    host.activate()
    host.toggle()
    host.onMark = { host.deactivate(); host.activate() }
    host.type("g")
    #expect(host.marked == "ㅎ")
    #expect(host.memory.mode(for: startingApp) == .korean)
    host.type("k")
    #expect(host.text.isEmpty)
    #expect(host.marked == "하")
}

@Test("activation: fallback 의 기억은 보존하고 실제 client 의 시작 규칙을 한 번 적용한다")
func activationUsesActualClientOnce() {
    let host = ActivationHost()
    host.activate()
    #expect(host.memory.mode(for: fallbackApp) == .korean)
    host.type("g")
    #expect(host.memory.mode(for: startingApp) == .english)
    #expect(host.text == "g")
    #expect(host.marked.isEmpty)
    host.toggle()
    host.type("gk")
    #expect(host.marked == "하")
}

@Test("activation: activate 알림이 없는 cold 첫 key 에도 실제 시작 규칙을 적용한다")
func activationWithoutNotification() {
    let host = ActivationHost()
    host.type("g")
    #expect(host.text == "g")
    #expect(host.memory.mode(for: startingApp) == .english)
    #expect(host.memory.mode(for: fallbackApp) == .korean)
}

@Test("activation: 첫 modifier event 의 초기화 뒤 한글 tap 은 다음 key 에도 유지된다")
func activationBeforeFirstModifier() {
    let host = ActivationHost()
    host.modifierWithoutAction()
    #expect(host.memory.mode(for: startingApp) == .english)
    host.toggle()
    host.type("gk")
    #expect(host.marked == "하")
    #expect(host.memory.mode(for: startingApp) == .korean)
}

@Test("activation: insert 중 재활성화 뒤 새 음절을 같은 한글 mode 로 이어 간다")
func activationDuringInsert() {
    let host = ActivationHost()
    host.toggle()
    host.type("gks")
    host.onInsert = { host.deactivate(); host.activate() }
    host.type("rk")
    #expect(host.text == "한")
    #expect(host.marked == "가")
    #expect(host.memory.mode(for: startingApp) == .korean)
}

@Test("activation: mutating 한자 질의 중 재활성화도 mode 를 바꾸지 않는다")
func activationDuringSelectionQuery() {
    let host = ActivationHost()
    host.toggle()
    host.selection = {
        host.deactivate()
        host.activate()
        return "한자"
    }
    host.send(optionReturn)
    #expect(host.driver.hasCandidates)
    #expect(host.memory.mode(for: startingApp) == .korean)
}

@Test("activation: 명시적 commit 은 재활성화가 취소하지 않고 다음 시작은 영문이다")
func activationAfterExplicitCommit() {
    let host = ActivationHost()
    host.toggle()
    host.onMark = {
        host.commit()
        host.activate()
        #expect(host.memory.mode(for: startingApp) == .korean)
    }
    host.type("gk")
    #expect(host.text == "ㅎk")
    #expect(host.marked.isEmpty)
    #expect(host.memory.mode(for: startingApp) == .english)
}

@Test("activation: 외부 commit 의 insert flush 는 실제 key event 의 continuation 이 아니다")
func activationDuringExternalFlush() {
    let host = ActivationHost()
    host.toggle()
    host.type("gks")
    host.onInsert = {
        #expect(host.driver.hasExplicitEnd)
        #expect(host.inputDepth == 0)
        host.activate()
        #expect(host.memory.mode(for: startingApp) == .korean)
    }
    host.commit()
    #expect(host.text == "한")
    #expect(!host.driver.hasExplicitEnd)
    host.type("g")
    #expect(host.text == "한g")
    #expect(host.marked.isEmpty)
}

@Test("activation: 실제 새 시작은 영문이며 그 뒤 매 key 를 reset 하지 않는다")
func activationOnRealNewStart() {
    let host = ActivationHost()
    host.toggle()
    host.type("gks")
    host.deactivate()
    host.activate()
    #expect(host.memory.mode(for: startingApp) == .english)
    host.type("g")
    host.toggle()
    host.type("gk")
    #expect(host.text == "한g")
    #expect(host.marked == "하")
}

@Test("activation: 늦은 실제 ID 는 이미 시작한 조합을 다시 영문으로 초기화하지 않는다")
func activationWithLateClientID() {
    let host = ActivationHost(clientApp: nil)
    host.memory.remember(.english, for: startingApp)
    host.activate()
    host.type("g")
    #expect(host.marked == "ㅎ")
    #expect(host.knownApp == nil)
    host.clientApp = startingApp
    host.type("k")
    #expect(host.text.isEmpty)
    #expect(host.marked == "하")
    #expect(host.memory.mode(for: startingApp) == .korean)
    #expect(host.memory.mode(for: fallbackApp) == .korean)
}

@Test("activation: ID 없는 첫 tap 의 새 mode 는 늦은 실제 ID 에서도 보존된다")
func activationWithLateClientAfterToggle() {
    let host = ActivationHost(clientApp: "")
    host.memory.remember(.english, for: fallbackApp)
    host.activate()
    host.toggle()
    host.clientApp = startingApp
    host.type("gk")
    #expect(host.text.isEmpty)
    #expect(host.marked == "하")
    #expect(host.memory.mode(for: startingApp) == .korean)
}

@Test("activation: ID 없는 영문 key 통과는 실제 app 의 한글 기억을 덮지 않는다")
func activationLateClientAfterPassedKey() {
    let actual = "homi.tests.remembered-korean"
    let host = ActivationHost(clientApp: nil)
    host.memory.remember(.english, for: fallbackApp)
    host.memory.remember(.korean, for: actual)
    host.activate()
    host.type("a")
    #expect(host.text == "a")
    #expect(host.marked.isEmpty)
    host.clientApp = actual
    host.type("r")
    #expect(host.memory.mode(for: actual) == .korean)
    #expect(host.memory.mode(for: fallbackApp) == .english)
    #expect(host.text == "a")
    #expect(host.marked == "ㄱ")
}

@Test("activation: ID 없는 Control 단축키 통과는 실제 app 의 한글 기억을 덮지 않는다")
func activationLateClientAfterPassedShortcut() {
    let actual = "homi.tests.remembered-korean"
    let host = ActivationHost(clientApp: nil)
    host.memory.remember(.english, for: fallbackApp)
    host.memory.remember(.korean, for: actual)
    host.activate()
    let outcome = host.send(KeyEvent(keyCode: 0, modifiers: .control))
    #expect(!outcome.handled)
    #expect(outcome.actions.isEmpty)
    #expect(host.driver.composing.isEmpty)
    host.clientApp = actual
    host.type("r")
    #expect(host.memory.mode(for: actual) == .korean)
    #expect(host.memory.mode(for: fallbackApp) == .english)
    #expect(host.text.isEmpty)
    #expect(host.marked == "ㄱ")
}

@Test("activation: ID 없는 단축키 통과 뒤 실제 app 의 영문 시작 규칙을 적용한다")
func activationLateClientAfterPassedShortcutUsesStartRule() {
    let host = ActivationHost(clientApp: nil)
    host.activate()
    let outcome = host.send(KeyEvent(keyCode: 0, modifiers: .control))
    #expect(outcome.actions.isEmpty)
    #expect(host.coordinator.needsStart)
    host.clientApp = startingApp
    host.type("r")
    #expect(host.memory.mode(for: startingApp) == .english)
    #expect(host.memory.mode(for: fallbackApp) == .korean)
    #expect(host.text == "r")
    #expect(host.marked.isEmpty)
}

@Test("activation: 명시적 전환 뒤 다른 fallback 의 통과 key 는 그 선택을 덮지 않는다")
func activationLateClientKeepsToggleAcrossPassedKey() {
    let host = ActivationHost(clientApp: nil)
    host.memory.remember(.english, for: fallbackApp)
    host.activate()
    host.toggle()
    host.fallback = "homi.tests.other-english-fallback"
    host.send(KeyEvent(keyCode: 0, modifiers: .control))
    host.clientApp = startingApp
    host.type("gk")
    #expect(host.memory.mode(for: startingApp) == .korean)
    #expect(host.text.isEmpty)
    #expect(host.marked == "하")
}

@Test("activation: 늦은 ID 의 한자 질의 중 새 시작은 옛 판단 결과가 소비하지 않는다")
func activationLateClientAfterNewStartDuringQuery() {
    let host = ActivationHost(clientApp: nil)
    host.activate()
    host.selection = {
        host.commit()
        host.activate()
        return "한자"
    }
    host.send(optionReturn)
    #expect(host.coordinator.needsStart)
    #expect(!host.driver.hasCandidates)
    #expect(host.text == "한자")
    host.clientApp = startingApp
    host.type("g")
    #expect(host.memory.mode(for: startingApp) == .english)
    #expect(host.text == "한자g")
    #expect(host.marked.isEmpty)
}

@Test("activation: 늦은 ID 의 한자 질의 중 같은 입력 재활성화는 mode 를 이어 간다")
func activationLateClientDuringContinuingQuery() {
    let host = ActivationHost(clientApp: nil)
    host.activate()
    host.selection = {
        host.deactivate()
        host.activate()
        return "한자"
    }
    host.send(optionReturn)
    #expect(!host.coordinator.needsStart)
    #expect(host.driver.hasCandidates)
    host.clientApp = startingApp
    host.modifierWithoutAction()
    #expect(host.memory.mode(for: startingApp) == .korean)
    #expect(host.driver.hasCandidates)
    #expect(host.text.isEmpty)
}

@Test("activation: ID 보정은 처음 fallback 보다 마지막 입력의 mode 를 이어 간다")
func activationAfterFallbackAppChanges() {
    let host = ActivationHost(clientApp: nil)
    host.activate()
    host.toggle()  // fallback A: 한글 → 영문
    let laterFallback = "homi.tests.later-fallback"
    host.memory.remember(.english, for: laterFallback)
    host.fallback = laterFallback
    host.toggle()  // fallback B: 영문 → 한글
    host.clientApp = startingApp
    host.type("gk")
    #expect(host.text.isEmpty)
    #expect(host.marked == "하")
    #expect(host.memory.mode(for: startingApp) == .korean)
}

@Test("activation: ID 없는 무변화 flagsChanged 는 늦은 시작 규칙을 소비하지 않는다")
func activationWithUnknownModifierOnly() {
    let host = ActivationHost(clientApp: nil)
    host.activate()
    host.modifierWithoutAction()
    #expect(host.coordinator.needsStart)
    host.clientApp = startingApp
    host.type("g")
    #expect(host.text == "g")
    #expect(host.marked.isEmpty)
}

@Test("activation: mouse 종료는 새 입력의 시작 초기화와 별개다")
func activationWithMouseBeforeFirstKey() {
    let host = ActivationHost()
    host.activate()
    host.mouseDown()
    #expect(host.coordinator.needsStart)
    host.type("g")
    #expect(host.text == "g")
    #expect(host.marked.isEmpty)
}

@Test("coordinator: bundle ID 질의의 재활성화도 같은 입력 경계에서 조합을 이어 간다")
func coordinatorReentryDuringClientIdentity() {
    let host = ActivationHost(clientApp: nil)
    host.type("g")
    host.clientApp = startingApp
    host.onBundleID = {
        #expect(host.inputDepth == 1)
        #expect(host.driver.isHandlingEvent)
        host.deactivate()
        #expect(host.text.isEmpty)
        #expect(host.driver.composing == "ㅎ")
        host.activate()
    }
    host.type("k")
    #expect(host.marked == "하")
    #expect(host.text.isEmpty)
    #expect(host.memory.mode(for: startingApp) == .korean)
}

@Test("coordinator: key·modifier 전환의 mode 저장은 client 확정보다 먼저다", arguments: [false, true])
func coordinatorSavesModeBeforeCommit(modifier: Bool) {
    let host = ActivationHost()
    host.appProfile = { _ in AppProfile(toggleKeys: [.shiftSpace]) }
    host.type("gks")
    var committed = false
    host.onInsert = {
        committed = true
        #expect(host.memory.mode(for: startingApp) == .english)
        #expect(host.modes.saved.last?.mode(for: startingApp) == .english)
        host.deactivate()
        host.activate()
    }
    if modifier { host.toggle() }
    else { host.send(KeyEvent(keyCode: 49, modifiers: .shift)) }
    #expect(committed)
    #expect(host.text == "한")
    #expect(host.marked.isEmpty)
    host.type("a")
    #expect(host.text == "한a")
}

@Test("coordinator: caret 등 후속 질의의 commit 도 같은 event 의 마지막에 반영한다")
func coordinatorKeepsAfterCallbackInsideBoundary() {
    let host = ActivationHost(clientApp: nil)
    var afterCalled = false
    host.coordinator.keyDown(key("g"), client: host, after: { _, _ in
        afterCalled = true
        host.commit()
        #expect(host.inputDepth == 1)
        #expect(host.text.isEmpty)
        #expect(host.marked == "ㅎ")
    })
    #expect(afterCalled)
    #expect(host.text == "ㅎ")
    #expect(host.marked.isEmpty)
    #expect(host.inputDepth == 0)
}

@Test("coordinator: mouse 확정은 event sender 대신 bound client 로 한 번 보낸다")
func coordinatorMouseUsesBoundClient() {
    let host = ActivationHost(clientApp: nil)
    let other = ActivationHost(clientApp: "homi.tests.other")
    host.type("gks")
    host.coordinator.mouseDown(client: other, boundClient: {
        #expect(host.inputDepth == 1)
        #expect(host.driver.isHandlingEvent)
        return host
    })
    #expect(host.text == "한")
    #expect(host.marked.isEmpty)
    #expect(other.text.isEmpty)
    #expect(other.marked.isEmpty)
    host.commit()
    #expect(host.text == "한")
}

@Test("coordinator: modifier 한자 질의의 재활성화와 늦은 ID 를 함께 처리한다")
func coordinatorModifierHanjaReentry() {
    let host = ActivationHost(clientApp: nil)
    host.selection = {
        #expect(host.driver.isMutatingSession)
        host.deactivate()
        host.activate()
        return "한자"
    }
    host.coordinator.modifiersChanged(client: host, action: { _, _ in .hanja })
    #expect(host.driver.hasCandidates)
    #expect(!host.coordinator.needsStart)
    host.clientApp = startingApp
    host.modifierWithoutAction()
    #expect(host.memory.mode(for: startingApp) == .korean)
    #expect(host.driver.hasCandidates)
    #expect(host.text.isEmpty)
}

@Test("coordinator: resend 권한 유무에 따라 먹거나 넘기며 조합은 먼저 한 번 확정한다", arguments: [false, true])
func coordinatorResendAfterCommit(allowed: Bool) {
    let host = ActivationHost()
    host.appProfile = { _ in AppProfile(resendWhileComposing: [36]) }
    host.type("gks")
    var permissionChecks = 0
    var delivered: Outcome?
    let outcome = host.coordinator.keyDown(KeyEvent(keyCode: 36), client: host, canResend: {
        permissionChecks += 1
        #expect(host.text.isEmpty)
        return allowed
    }, after: { outcome, _ in
        #expect(host.text == "한")
        #expect(host.marked.isEmpty)
        delivered = outcome
    })
    #expect(permissionChecks == 1)
    #expect(outcome.handled == allowed)
    #expect(outcome.resend == allowed)
    #expect(delivered == outcome)
    host.commit()
    #expect(host.text == "한")
}

@Test("coordinator: controller 둘은 app mode 를 공유하되 조합은 따로 소유한다")
func coordinatorSharesOnlyModes() {
    let modes = ActivationModes()
    let first = ActivationHost(clientApp: "homi.tests.shared", modes: modes)
    let second = ActivationHost(clientApp: "homi.tests.shared", modes: modes)
    first.toggle() // 처음 보는 app: 영문 → 한글
    first.type("g")
    second.type("r")
    #expect(first.marked == "ㅎ")
    #expect(second.marked == "ㄱ")
    first.toggle()
    second.type("a")
    #expect(first.text == "ㅎ")
    #expect(second.text == "ㄱa")
    #expect(second.marked.isEmpty)
}

@Test("coordinator: 생성은 환경을 부르지 않고 activation 은 client 를 질의하지 않는다")
func coordinatorConstructionAndActivationDoNotQueryClient() {
    let modes = ActivationModes()
    var environmentCalls = 0
    let coordinator = InputCoordinator(modes: modes, profile: { _ in
        environmentCalls += 1
        return AppProfile(startsInEnglish: true)
    }, fallbackApp: {
        environmentCalls += 1
        return fallbackApp
    }, notice: { _ in environmentCalls += 1 })
    #expect(environmentCalls == 0)
    let activation = coordinator.activate()
    #expect(environmentCalls > 0)
    #expect(activation.app == .fallback(fallbackApp))
    #expect(activation.layout == "com.apple.keylayout.ABC")
    #expect(!activation.resuming)
    #expect(coordinator.clientApp == nil)
    #expect(coordinator.needsStart)
    #expect(modes.memory.mode(for: fallbackApp) == .korean)
    #expect(modes.saved.isEmpty)
}

@Test("app 식별: 같은 ID 문자열이어도 fallback 은 실제 client 의 시작 근거가 아니다", arguments: [nil, ""] as [String?])
func fallbackWithSameIDDoesNotBecomeClientIdentity(unansweredID: String?) {
    let host = ActivationHost(clientApp: unansweredID, fallback: startingApp)
    host.activate()
    host.modifierWithoutAction()
    #expect(host.knownApp == nil)
    #expect(host.coordinator.needsStart)
    #expect(host.memory.mode(for: startingApp) == .korean)
    host.clientApp = startingApp
    host.type("g")
    #expect(host.knownApp == startingApp)
    #expect(host.memory.mode(for: startingApp) == .english)
    #expect(host.text == "g")
    #expect(host.marked.isEmpty)
}
