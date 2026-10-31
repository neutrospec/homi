import InputSession
import Testing

@testable import homi

private nonisolated final class BusyModes: ModeStore {
    var memory = ModeMemory(modes: ["homi.tests": .english])
    func withMemory<Result: Sendable>(_ operation: (inout ModeMemory) -> Result) -> Result { operation(&memory) }
    func save(_ snapshot: ModeMemory) {}
}

private nonisolated final class BusyHost {
    let driver = SessionDriver()
    let modes = BusyModes()
    let proxy = TextProxy()
    var seen: [ClientTrace.CallKind?] = []
    var duringNotice: (() -> Void)?
    lazy var coordinator = InputCoordinator(driver: driver, modes: modes, profile: { _ in AppProfile() },
        fallbackApp: { "homi.tests" }, notice: { [weak self] notice in
            guard case .keyEnteredWhileBusy = notice, let self else { return }
            self.seen.append(self.driver.clientTrace.snapshot.frame?.kind)
            self.duringNotice?()
        })
    lazy var client = Client(proxy: proxy, trace: driver.clientTrace, submission: driver.submission)
    @discardableResult func key() -> Outcome { coordinator.keyDown(KeyEvent(keyCode: 0), client: client) }
}

@Test("busy key 관측: 보통 key 와 lifecycle callback 만으로 기록하지 않는다")
func busyKeyNormalAndLifecycle() {
    let host = BusyHost()
    #expect(!host.key().handled)
    _ = host.coordinator.activate()
    host.driver.deactivate(apply: host.client.apply)
    host.driver.sourceChanged(selected: false, apply: host.client.apply)
    host.driver.end(.commitToClient, apply: host.client.apply)
    #expect(host.seen.isEmpty)
    #expect(host.proxy.queryCount == 0)
}

@Test("busy key 관측: client 호출 종류별 첫 건만 기록하고 새로운 controller 는 독립적이다")
func busyKeyClientKinds() {
    let host = BusyHost()
    var outcomes: [Outcome] = []
    func nested() { outcomes.append(host.key()) }
    for _ in 0..<2 {
        host.proxy.onInsert = nested
        host.client.apply([.insert("한")])
        host.proxy.onMark = nested
        host.client.apply([.mark("ㅎ")])
        host.proxy.onBundleQuery = nested
        _ = host.client.bundleIdentifier()
        host.proxy.onOverrideKeyboard = { _ in nested() }
        host.client.apply([.layout("com.apple.keylayout.ABC")])
    }
    #expect(host.seen == [.insert, .mark, .query, .layout])
    #expect(outcomes.count == 8 && outcomes.allSatisfy { !$0.handled && $0.actions.isEmpty && $0.mode == .english })
    #expect(host.proxy.text == "한한" && host.proxy.marked == "ㅎ")
    #expect(host.proxy.queryCount == 0)
    host.driver.withEvent { _ = host.key(); _ = host.key() }
    #expect(host.seen == [.insert, .mark, .query, .layout, nil])
    let other = BusyHost()
    other.proxy.onInsert = { _ = other.key() }
    other.client.apply([.insert("한")])
    #expect(other.seen == [.insert] && host.seen.count == 5)
}

@Test("busy key 관측: client frame 없는 event 와 여러 busy 조건은 한 종류로 한 번만 기록한다")
func busyKeyEventOnlyAndDedup() {
    let host = BusyHost()
    host.driver.withEvent { _ = host.key() } // driver busy, inputDepth 0
    _ = host.coordinator.keyDown(KeyEvent(keyCode: 0), client: host.client, before: {
        _ = host.key() // inputDepth 와 driver busy 동시
    })
    #expect(host.seen.count == 1 && host.seen[0] == nil)
    #expect(!host.driver.isHandlingEvent && host.coordinator.inputDepth == 0)
}

@Test("busy key 관측: notice 전 종류를 저장하므로 notice 재진입도 중복하지 않는다")
func busyKeyNoticeReentry() {
    let host = BusyHost()
    var nestedCount = 0
    host.duringNotice = {
        nestedCount += 1
        if nestedCount < 3 { _ = host.key() }
    }
    host.driver.withEvent { _ = host.key() }
    #expect(nestedCount == 1 && host.seen.count == 1 && host.seen[0] == nil)
}

@Test("busy key 관측: mutating 중 trace 상태는 Session 접근 없이 읽는다")
func busyKeyTraceDuringMutation() {
    let driver = SessionDriver()
    let trace = driver.clientTrace
    #expect(!trace.hasActiveCall)
    driver.perform({ _ in
        #expect(driver.isMutatingSession)
        trace.withCall(.query) {
            #expect(trace.hasActiveCall)
            #expect(trace.snapshot.frame?.kind == .query)
            #expect(driver.isHandlingEvent)
        }
        #expect(!trace.hasActiveCall)
    }, apply: { _ in })
    #expect(!driver.isMutatingSession && !trace.hasActiveCall)
}

@Test("busy key 관측: 제품 경계에 주입한 한글 중첩의 handled 와 action 을 바꾸지 않는다")
func busyKeyKoreanOutcomeUnchanged() {
    let host = BusyHost()
    host.modes.memory.remember(.korean, for: "homi.tests")
    for code: UInt16 in [5, 40, 1] {
        let outcome = host.coordinator.keyDown(KeyEvent(keyCode: code), client: host.client)
        #expect(outcome.handled)
    }
    var nested: Outcome?
    host.proxy.onInsert = {
        nested = host.coordinator.keyDown(KeyEvent(keyCode: 40), client: host.client)
    }
    let outer = host.coordinator.keyDown(KeyEvent(keyCode: 15), client: host.client)
    #expect(outer.handled && outer.actions == [.insert("한"), .mark("ㄱ")])
    #expect(nested?.handled == true && nested?.actions == [.mark("가")])
    #expect(host.seen == [.insert])
    // mark 일치 여부는 별도 known issue 가 검증한다.
    #expect(host.proxy.text == "한" && host.driver.composing == "가")
}
