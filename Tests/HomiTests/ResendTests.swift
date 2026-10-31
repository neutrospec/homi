import AppKit
import InputSession
import Testing

@testable import homi

private nonisolated final class ResendModes: ModeStore {
    var memory = ModeMemory(modes: ["homi.tests": .korean])
    func withMemory<Result: Sendable>(_ operation: (inout ModeMemory) -> Result) -> Result { operation(&memory) }
    func save(_ snapshot: ModeMemory) {}
}

/// CGEvent 는 만들되 system 에 보내지 않는다. 목적지와 전송 순서는 fake transport 로 검사한다.
private final class ResendEnvironment {
    var work: [Resend.Work] = []
    var sent: [(pid: pid_t, type: CGEventType, code: Int64, flags: CGEventFlags)] = []
    var running = true
    var frontmost: pid_t = 123
    var targetQueries = 0
    var unavailable: String?

    let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .shift,
        timestamp: 10, windowNumber: 42, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
        isARepeat: false, keyCode: 36)!

    func prepare(app: ClientAppID?) -> Resend? {
        Resend.prepare(event, app: unavailable == "client" ? nil : app,
            target: {
                self.targetQueries += 1
                if self.unavailable == "target" { return nil }
                return ResendTarget(pid: self.unavailable == "pid" ? 0 : self.frontmost,
                    bundleID: self.unavailable == "identity" ? "other.app" : "homi.tests",
                    isRunning: { self.running })
            }, allowed: { self.unavailable != "permission" },
            make: { code, down in
                if self.unavailable == (down ? "down" : "up") { return nil }
                return CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
            }, post: { event, pid in
                self.sent.append((pid, event.type, event.getIntegerValueField(.keyboardEventKeycode), event.flags))
            })
    }

    nonisolated func enqueue(_ item: @escaping Resend.Work) { MainActor.assumeIsolated { work.append(item) } }
    func drain() { while !work.isEmpty { work.removeFirst()() } }
}

@Test("resend: 권한·대상·down/up 준비 실패 때 원래 key 를 먹지 않는다",
    arguments: ["permission", "target", "client", "identity", "pid", "down", "up"])
func resendPreparationFailurePassesOriginalKey(failure: String) {
    let environment = ResendEnvironment()
    environment.unavailable = failure
    let coordinator = InputCoordinator(modes: ResendModes(),
        profile: { _ in AppProfile(resendWhileComposing: [36]) }, fallbackApp: { "homi.tests" })
    let proxy = TextProxy()
    let client = Client(proxy: proxy, submission: coordinator.driver.submission)
    coordinator.keyDown(KeyEvent(keyCode: 5), client: client)
    var prepared: Resend?
    let outcome = coordinator.keyDown(KeyEvent(keyCode: 36), client: client, canResend: {
        prepared = environment.prepare(app: coordinator.clientApp)
        return prepared != nil
    }, after: { result, _ in
        if result.resend { prepared?.send(afterEvent: coordinator.driver.afterEvent, enqueue: environment.enqueue) }
    })
    environment.drain()
    #expect(!outcome.handled && !outcome.resend)
    #expect(proxy.text == "ㅎ" && proxy.marked.isEmpty)
    #expect(environment.sent.isEmpty)
}

@Test("resend: 원래 event 의 lifecycle 반영 뒤 예약하고 원래 app 에 down/up 을 한 번 보낸다")
func resendKeepsTargetAndWaitsForClientFlush() throws {
    let environment = ResendEnvironment()
    let coordinator = InputCoordinator(modes: ResendModes(),
        profile: { _ in AppProfile(resendWhileComposing: [36]) }, fallbackApp: { "homi.tests" })
    let driver = coordinator.driver
    let proxy = TextProxy()
    let client = Client(proxy: proxy, submission: driver.submission)
    coordinator.keyDown(KeyEvent(keyCode: 5), client: client)
    proxy.onInsert = {
        driver.end(.commitToClient, apply: client.apply)
        #expect(environment.work.isEmpty)
        #expect(environment.sent.isEmpty)
    }
    var prepared: Resend?
    let outcome = coordinator.keyDown(KeyEvent(keyCode: 36), client: client, canResend: {
        prepared = environment.prepare(app: coordinator.clientApp)
        return prepared != nil
    }, after: { result, _ in
        #expect(result.resend)
        prepared?.send(afterEvent: driver.afterEvent, enqueue: environment.enqueue)
        prepared?.send(afterEvent: driver.afterEvent, enqueue: environment.enqueue)
        #expect(environment.work.isEmpty)
    })
    #expect(outcome.handled && outcome.resend)
    #expect(proxy.text == "ㅎ" && proxy.marked.isEmpty && driver.composing.isEmpty)
    #expect(environment.work.count == 1)
    environment.frontmost = 456 // 기다리는 동안 다른 app 이 앞으로 와도 목적지를 바꾸지 않는다.
    environment.drain()
    #expect(environment.targetQueries == 1)
    #expect(environment.sent.map(\.pid) == [123, 123])
    #expect(environment.sent.map(\.type) == [.keyDown, .keyUp])
    #expect(environment.sent.map(\.code) == [36, 36])
    #expect(environment.sent.allSatisfy { $0.flags.contains(.maskShift) })
}

@Test("resend: 원래 app 이 종료되면 다른 app 에 보내거나 재시도하지 않는다")
func resendDoesNotRetargetExitedApp() throws {
    let environment = ResendEnvironment()
    let prepared = try #require(environment.prepare(app: ClientAppID("homi.tests")))
    prepared.send(afterEvent: { $0() }, enqueue: environment.enqueue)
    environment.running = false
    environment.frontmost = 456
    environment.drain()
    #expect(environment.sent.isEmpty)
    #expect(environment.work.isEmpty)
    #expect(environment.targetQueries == 1)
}
