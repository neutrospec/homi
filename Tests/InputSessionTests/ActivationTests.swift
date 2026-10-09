import Testing

@testable import InputSession

private let startingApp = "homi.tests.english-start"
private let fallbackApp = "homi.tests.fallback"

/// controller 의 app 판별·mode 기억과 실제 SessionDriver 를 함께 검사한다. 입력은 이 test 에서 만든 것뿐이다.
private final class ActivationHost {
    let driver = SessionDriver(hanja: dictionary)
    var memory: ModeMemory
    var clientApp: String?
    var fallback: String
    var knownApp: String?
    var activation = ModeActivation()
    var inputDepth = 0
    var text = ""
    var marked = ""
    var onMark: (() -> Void)?
    var onInsert: (() -> Void)?

    init(clientApp: String? = startingApp, fallback: String = fallbackApp) {
        self.clientApp = clientApp
        self.fallback = fallback
        memory = ModeMemory(modes: [startingApp: .korean, fallbackApp: .korean])
    }

    func profile(_ app: String) -> AppProfile {
        AppProfile(startsInEnglish: app == startingApp || app == fallbackApp)
    }

    func activate() {
        activation.activate(resumingInput: inputDepth > 0 && !driver.hasExplicitEnd)
        driver.activate()
        if inputDepth == 0, !driver.isHandlingEvent, let knownApp {
            _ = activation.prepare(app: knownApp, trusted: true, profile: profile(knownApp), memory: &memory)
        }
    }

    func resolve() -> String {
        if let knownApp { return knownApp }
        if let clientApp, !clientApp.isEmpty { knownApp = clientApp; return clientApp }
        return fallback
    }

    func apply(_ actions: [Action]) {
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
            withInputEvent {
                let app = resolve()
                let mode = activation.prepare(app: app, trusted: knownApp != nil, profile: profile(app), memory: &memory)
                activation.inputStarted(app: app, trusted: knownApp != nil)
                driver.perform({ $0.handle(key(letter), mode: mode, profile: profile(app)) }, apply: {
                    memory.remember($0.mode, for: app)
                    apply($0.actions)
                    if !$0.handled { text.append(letter) }
                })
            }
        }
    }

    func toggle() {
        withInputEvent {
            let app = resolve()
            let mode = activation.prepare(app: app, trusted: knownApp != nil, profile: profile(app), memory: &memory)
            activation.inputStarted(app: app, trusted: knownApp != nil)
            driver.perform({ $0.toggle(from: mode, profile: profile(app)) }, apply: {
                memory.remember($0.mode, for: app)
                apply($0.actions)
            })
        }
    }

    func modifierWithoutAction() {
        withInputEvent {
            let app = resolve()
            _ = activation.prepare(app: app, trusted: knownApp != nil, profile: profile(app), memory: &memory)
        }
    }

    func withInputEvent(_ body: () -> Void) {
        inputDepth += 1
        defer { inputDepth -= 1 }
        driver.withEvent(body)
    }

    func deactivate() { driver.deactivate(apply: apply) }
    func commit(insert: Bool = true) { driver.commit(insert: insert, apply: apply) }
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
    host.withInputEvent {
        host.driver.perform({
            $0.handle(optionReturn, mode: host.memory.mode(for: startingApp), selectedText: {
                host.deactivate()
                host.activate()
                return "한자"
            })
        }, apply: { host.apply($0.actions) })
    }
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
    #expect(host.activation.needsStart)
    host.clientApp = startingApp
    host.type("g")
    #expect(host.text == "g")
    #expect(host.marked.isEmpty)
}

@Test("activation: mouse 종료는 새 입력의 시작 초기화와 별개다")
func activationWithMouseBeforeFirstKey() {
    let host = ActivationHost()
    host.activate()
    host.withInputEvent { host.commit() }
    #expect(host.activation.needsStart)
    host.type("g")
    #expect(host.text == "g")
    #expect(host.marked.isEmpty)
}
