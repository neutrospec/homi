import InputSession
import Testing

@testable import homi

private nonisolated final class BoundaryModes: ModeStore {
    var memory = ModeMemory(modes: ["homi.tests": .korean])
    func withMemory<Result: Sendable>(_ operation: (inout ModeMemory) -> Result) -> Result { operation(&memory) }
    var saved: [ModeMemory] = []
    var onSave: ((ModeMemory) -> Void)?
    func save(_ snapshot: ModeMemory) { saved.append(snapshot); onSave?(snapshot) }
}

private nonisolated final class BoundaryHost {
    let modes = BoundaryModes()
    let proxy = TextProxy()
    let driver = SessionDriver()
    let remote: Bool
    let startsInEnglish: Bool
    lazy var coordinator = InputCoordinator(driver: driver, modes: modes,
        profile: { [remote, startsInEnglish] _ in AppProfile(startsInEnglish: startsInEnglish, keyboardLayoutFollowsMode: remote) }, fallbackApp: { "homi.tests" },
        notice: { [weak self] notice in
            if case .becameActive = notice { self?.becameActive += 1 }
        })
    lazy var client = Client(proxy: proxy, trace: driver.clientTrace, submission: driver.submission)
    var becameActive = 0
    var factoryCalls = 0
    var activations: [InputCoordinator.Activation] = []
    init(remote: Bool = false, startsInEnglish: Bool = false) {
        self.remote = remote
        self.startsInEnglish = startsInEnglish
    }

    func activate(_ target: TextProxy? = nil, valid: Bool = true) {
        InputActivation.run(coordinator: coordinator, client: {
            self.factoryCalls += 1
            guard valid else { return nil }
            return Client(proxy: target ?? self.proxy, trace: self.driver.clientTrace, submission: self.driver.submission)
        }, didActivate: { self.activations.append($0) })
    }
    @discardableResult func key(_ code: UInt16) -> Outcome {
        coordinator.keyDown(KeyEvent(keyCode: code), client: client)
    }
    func end(_ kind: CompositionEnd = .commitToClient) { driver.end(kind, apply: client.apply) }
}

@Test("activation 경계: 일반·원격 layout 과 client 부재도 기존 순서로 처리한다", arguments: [false, true])
func activationBoundaryNormal(remote: Bool) {
    let host = BoundaryHost(remote: remote)
    host.activate()
    #expect(host.proxy.keyboardOverrides == [remote ? "com.apple.keylayout.2SetHangul" : "com.apple.keylayout.ABC"])
    #expect(host.becameActive == 1 && host.factoryCalls == 1 && host.activations.count == 1)
    #expect(host.proxy.queryCount == 0 && host.proxy.queries.isEmpty)
    host.activate(valid: false)
    #expect(host.proxy.keyboardOverrides.count == 1)
    #expect(host.becameActive == 2 && host.factoryCalls == 2 && host.activations.count == 2)
    host.activate()
    #expect(host.proxy.keyboardOverrides.count == 2) // 별도 activation 은 layout 을 다시 지정한다.
}

@Test("activation 경계: 같은 proxy 의 새 activation 은 layout 초기화 뒤에도 다시 지정한다")
func activationBoundaryNewActivation() {
    let host = BoundaryHost()
    var effective: String?
    host.proxy.onOverrideKeyboard = { effective = $0 }
    host.activate()
    effective = nil // client 가 새 activation 에서 layout 을 초기화한 가정
    host.activate()
    #expect(effective == "com.apple.keylayout.ABC")
    #expect(host.proxy.keyboardOverrides.count == 2)
}

@Test("activation 경계: mark 중 재활성화는 client factory 를 호출하지 않는다")
func activationBoundaryResuming() {
    let host = BoundaryHost()
    host.proxy.onMark = {
        host.driver.deactivate(apply: host.client.apply)
        host.activate()
    }
    #expect(host.key(5).handled)
    #expect(host.activations.count == 1 && host.activations[0].resuming)
    #expect(host.factoryCalls == 0 && host.proxy.keyboardOverrides.isEmpty)
    #expect(host.proxy.marked == "ㅎ" && host.driver.composing == "ㅎ")
    host.end()
    #expect(host.proxy.text == "ㅎ" && host.proxy.marked.isEmpty)
}

@Test("activation 경계: mark 중 명시적 종료 뒤 activation 은 종료를 지우지 않는다", arguments: ["commit", "source", "confirmed"])
func activationBoundaryExplicitEnd(ending: String) {
    let host = BoundaryHost()
    host.proxy.onMark = {
        switch ending {
        case "commit": host.end()
        case "source": host.driver.sourceChanged(selected: false, apply: host.client.apply)
        default:
            host.proxy.text += host.proxy.marked
            host.proxy.marked = ""
            host.end(.alreadyCommittedByClient)
        }
        host.activate()
    }
    #expect(host.key(5).handled)
    #expect(host.activations.count == 1 && !host.activations[0].resuming)
    #expect(host.proxy.keyboardOverrides == ["com.apple.keylayout.ABC"])
    #expect(host.proxy.text == "ㅎ" && host.proxy.marked.isEmpty && host.driver.composing.isEmpty)
    host.end()
    #expect(host.proxy.text == "ㅎ")
}

@Test("activation 경계: 다른 sender 와 layout 의 중첩 요청을 각각 전달한다")
func activationBoundaryDifferentTargetAndLayout() {
    let host = BoundaryHost(remote: true)
    let second = TextProxy()
    host.proxy.onOverrideKeyboard = { _ in
        host.proxy.onOverrideKeyboard = nil
        host.modes.withMemory { $0.remember(.english, for: "homi.tests") }
        host.activate(second)
    }
    host.activate()
    #expect(host.proxy.keyboardOverrides == ["com.apple.keylayout.2SetHangul"])
    #expect(second.keyboardOverrides == ["com.apple.keylayout.ABC"])
    #expect(host.becameActive == 2 && host.factoryCalls == 2 && host.activations.count == 2)
    #expect(host.modes.memory.mode(for: "homi.tests") == .english)
    #expect(host.proxy.queryCount == 0 && second.queryCount == 0)
}

@Test("activation 경계: ABC → Hangul → ABC 는 같은 proxy 에 세 요청을 전달한다")
func activationBoundaryLayoutABA() {
    let host = BoundaryHost(remote: true)
    host.modes.withMemory { $0.remember(.english, for: "homi.tests") }
    host.proxy.onOverrideKeyboard = { _ in
        switch host.proxy.keyboardOverrides.count {
        case 1:
            host.modes.withMemory { $0.remember(.korean, for: "homi.tests") }
            host.activate()
        case 2:
            host.modes.withMemory { $0.remember(.english, for: "homi.tests") }
            host.activate()
        default: break
        }
    }
    host.activate()
    #expect(host.proxy.keyboardOverrides == ["com.apple.keylayout.ABC", "com.apple.keylayout.2SetHangul", "com.apple.keylayout.ABC"])
    #expect(host.becameActive == 3 && host.activations.count == 3)
    #expect(host.modes.memory.mode(for: "homi.tests") == .english)
}

@Test("activation 경계: layout 중 일반 key 는 같은 입력 흐름에서 한 번 처리된다")
func activationBoundaryNestedKey() {
    let host = BoundaryHost()
    host.proxy.onOverrideKeyboard = { _ in #expect(host.key(5).handled) }
    host.activate()
    #expect(host.proxy.marked == "ㅎ" && host.driver.composing == "ㅎ")
    host.end()
    #expect(host.proxy.text == "ㅎ" && host.proxy.marked.isEmpty)
    #expect(host.proxy.keyboardOverrides.count == 1)
}

@Test("activation 경계: 다른 controller 의 공유 mode 전환 뒤 새 layout 요청을 전달한다")
func activationBoundarySharedModeToggle() {
    let host = BoundaryHost(remote: true)
    let secondProxy = TextProxy()
    let secondDriver = SessionDriver()
    let secondClient = Client(proxy: secondProxy, trace: secondDriver.clientTrace, submission: secondDriver.submission)
    let second = InputCoordinator(driver: secondDriver, modes: host.modes,
        profile: { _ in AppProfile(keyboardLayoutFollowsMode: true) }, fallbackApp: { "homi.tests" })
    host.proxy.onOverrideKeyboard = { _ in
        host.proxy.onOverrideKeyboard = nil
        second.modifiersChanged(client: secondClient, action: { _, _ in .toggle })
        host.activate()
    }
    host.activate()
    #expect(host.proxy.keyboardOverrides == ["com.apple.keylayout.2SetHangul", "com.apple.keylayout.ABC"])
    #expect(secondProxy.keyboardOverrides == ["com.apple.keylayout.ABC"])
    #expect(host.modes.memory.mode(for: "homi.tests") == .english)
    #expect(host.activations.count == 2 && host.becameActive == 2)
}

@Test("activation 경계: client 의 적용 시점에 따라 중첩 layout 최종 결과가 달라진다", arguments: [false, true])
func activationBoundaryClientApplyTiming(applyBeforeCallback: Bool) {
    let host = BoundaryHost(remote: true)
    var effective: String?
    host.proxy.onOverrideKeyboard = { layout in
        if applyBeforeCallback { effective = layout }
        if host.proxy.keyboardOverrides.count == 1 {
            host.modes.withMemory { $0.remember(.english, for: "homi.tests") }
            host.activate()
        }
        if !applyBeforeCallback { effective = layout }
    }
    host.activate()
    #expect(host.proxy.keyboardOverrides == ["com.apple.keylayout.2SetHangul", "com.apple.keylayout.ABC"])
    #expect(effective == (applyBeforeCallback ? "com.apple.keylayout.ABC" : "com.apple.keylayout.2SetHangul"))
}

@Test("activation 경계: 같은 요청 중첩도 현재 각 activation 을 실행한다")
func activationBoundarySameRequestReenters() {
    let host = BoundaryHost()
    host.proxy.onOverrideKeyboard = { _ in
        if host.proxy.keyboardOverrides.count < 3 { host.activate() }
    }
    host.activate()
    #expect(host.proxy.keyboardOverrides == Array(repeating: "com.apple.keylayout.ABC", count: 3))
    #expect(host.factoryCalls == 3 && host.becameActive == 3 && host.activations.count == 3)
}

@Test("activation 경계: 시작 알림 다음 layout, 그 뒤 표시이며 client 질의는 없다")
func activationBoundaryOrder() {
    let modes = BoundaryModes()
    let driver = SessionDriver()
    let proxy = TextProxy()
    var calls: [String] = []
    proxy.onBundleQuery = { calls.append("client-query") }
    proxy.onOverrideKeyboard = { _ in calls.append("layout") }
    let coordinator = InputCoordinator(driver: driver, modes: modes, profile: { _ in AppProfile() },
        fallbackApp: { "homi.tests" }, notice: { notice in
            if case .becameActive = notice { calls.append("activate") }
        })
    InputActivation.run(coordinator: coordinator, client: {
        calls.append("factory")
        return Client(proxy: proxy, trace: driver.clientTrace, submission: driver.submission)
    }, didActivate: { _ in calls.append("indicator") })
    #expect(calls == ["activate", "factory", "layout", "indicator"])
    #expect(proxy.queryCount == 0 && proxy.queries.isEmpty)
}

@Test("activation 경계: 같은 layout 이라도 다른 sender 의 요청은 각각 전달한다")
func activationBoundaryDifferentSenderSameLayout() {
    let host = BoundaryHost()
    let second = TextProxy()
    host.proxy.onOverrideKeyboard = { _ in
        host.proxy.onOverrideKeyboard = nil
        host.activate(second)
    }
    host.activate()
    #expect(host.proxy.keyboardOverrides == ["com.apple.keylayout.ABC"])
    #expect(second.keyboardOverrides == ["com.apple.keylayout.ABC"])
    #expect(host.becameActive == 2 && host.activations.count == 2)
}

@Test("activation 경계: 실제 client 의 영문 시작은 이어지는 입력에는 다시 적용하지 않는다")
func activationBoundaryStartRuleResumingAndNewStart() {
    let host = BoundaryHost(startsInEnglish: true)
    // 첫 event 에서 실제 ID 를 얻어 시작 규칙을 적용하고, 주인이 한글로 전환한다.
    host.coordinator.modifiersChanged(client: host.client, action: { _, _ in nil })
    #expect(host.coordinator.clientApp?.bundleID == "homi.tests")
    #expect(host.modes.memory.mode(for: "homi.tests") == .english)
    host.coordinator.modifiersChanged(client: host.client, action: { _, _ in .toggle })
    #expect(host.modes.memory.mode(for: "homi.tests") == .korean)
    let saves = host.modes.saved.count
    host.proxy.onMark = { host.activate() }
    #expect(host.key(5).handled)
    #expect(host.activations.last?.resuming == true)
    #expect(host.proxy.marked == "ㅎ" && host.driver.composing == "ㅎ")
    #expect(host.modes.memory.mode(for: "homi.tests") == .korean)
    #expect(host.modes.saved.count == saves)
    host.end()
    host.activate() // 조합 종료 뒤 실제 새 activation
    #expect(host.activations.last?.resuming == false)
    #expect(host.modes.memory.mode(for: "homi.tests") == .english)
    #expect(host.modes.saved.count == saves + 1)
    #expect(host.proxy.text == "ㅎ" && host.proxy.marked.isEmpty)
}

@Test("activation 경계: cached 시작 규칙과 명시적 종료는 중첩 layout 에서도 보존된다")
func activationBoundaryCachedStartAndNestedCommit() {
    let host = BoundaryHost(startsInEnglish: true)
    host.coordinator.modifiersChanged(client: host.client, action: { _, _ in nil })
    host.coordinator.modifiersChanged(client: host.client, action: { _, _ in .toggle })
    #expect(host.key(5).handled)
    #expect(host.proxy.marked == "ㅎ")
    var calls: [String] = []
    host.proxy.onOverrideKeyboard = { _ in
        switch host.proxy.keyboardOverrides.count {
        case 1:
            calls.append("outer layout")
            host.end()
            calls.append("commit returned")
            #expect(host.activations.isEmpty)
            host.activate()
            #expect(host.activations.count == 1)
            calls.append("inner returned")
        case 2: calls.append("inner layout")
        default: Issue.record("예상하지 않은 layout 재진입")
        }
    }
    host.activate()
    #expect(calls == ["outer layout", "commit returned", "inner layout", "inner returned"])
    // 중첩 호출의 didActivate 가 먼저 돌아온다. 둘 다 같은 activation 결과를 가지므로 순서는 호출 중 count 로 확인한다.
    #expect(host.activations.count == 2)
    #expect(host.activations.allSatisfy { !$0.resuming && $0.mode == .english })
    #expect(host.modes.memory.mode(for: "homi.tests") == .english)
    #expect(host.proxy.text == "ㅎ" && host.proxy.marked.isEmpty && host.driver.composing.isEmpty)
    #expect(!host.driver.isHandlingEvent && !host.driver.hasExplicitEnd)
    host.end()
    #expect(host.proxy.text == "ㅎ")
}

@Test("activation 경계: cached 시작 mode 저장과 알림은 layout 및 표시보다 먼저다")
func activationBoundaryCachedStartOrder() {
    let modes = BoundaryModes()
    let driver = SessionDriver()
    let proxy = TextProxy()
    let client = Client(proxy: proxy, trace: driver.clientTrace, submission: driver.submission)
    var calls: [String] = []
    let coordinator = InputCoordinator(driver: driver, modes: modes,
        profile: { _ in AppProfile(startsInEnglish: true) }, fallbackApp: { "homi.tests" }, notice: { notice in
            switch notice {
            case .becameActive: calls.append("active")
            case .modePrepared(_, let mode, _): calls.append("prepared \(mode)")
            default: break
            }
        })
    coordinator.modifiersChanged(client: client, action: { _, _ in nil })
    coordinator.modifiersChanged(client: client, action: { _, _ in .toggle })
    #expect(modes.memory.mode(for: "homi.tests") == .korean)
    calls = []
    modes.onSave = { _ in calls.append("save") }
    proxy.onOverrideKeyboard = { _ in calls.append("layout") }
    InputActivation.run(coordinator: coordinator, client: {
        calls.append("factory")
        return client
    }, didActivate: { activation in
        calls.append("indicator \(activation.mode)")
    })
    #expect(calls == ["active", "save", "prepared english", "factory", "layout", "indicator english"])
    #expect(modes.memory.mode(for: "homi.tests") == .english)
    #expect(proxy.queryCount == 0)
}
