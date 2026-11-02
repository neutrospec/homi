import InputSession
import Testing

@testable import homi

private nonisolated final class InterleavingModes: ModeStore {
    var memory = ModeMemory(modes: ["homi.tests": .korean])
    func withMemory<Result: Sendable>(_ operation: (inout ModeMemory) -> Result) -> Result { operation(&memory) }
    func save(_ snapshot: ModeMemory) {}
}

private nonisolated final class InterleavingHost {
    let modes = InterleavingModes()
    let proxy = TextProxy()
    let coordinator: InputCoordinator
    let client: Client
    var driver: SessionDriver { coordinator.driver }

    init(startsInEnglish: Bool) {
        let driver = SessionDriver()
        coordinator = InputCoordinator(driver: driver, modes: modes,
            profile: { _ in AppProfile(startsInEnglish: startsInEnglish) }, fallbackApp: { "fallback" })
        client = Client(proxy: proxy, trace: driver.clientTrace, submission: driver.submission)
        _ = coordinator.activate()
        // 실제 client ID 를 얻어 시작 규칙을 적용한 다음, 영문 시작이면 전환해 한글을 준비한다.
        coordinator.modifiersChanged(client: client, action: { _, _ in nil })
        #expect(modes.memory.mode(for: "homi.tests") == (startsInEnglish ? .english : .korean))
        if startsInEnglish { coordinator.modifiersChanged(client: client, action: { _, _ in .toggle }) }
    }

    @discardableResult func key(_ code: UInt16) -> Outcome {
        coordinator.keyDown(KeyEvent(keyCode: code), client: client)
    }
    func end() { driver.end(.commitToClient, apply: client.apply) }

    func run(_ events: [InterleavingEvent]) {
        for event in events {
            switch event {
            case .activate: _ = coordinator.activate()
            case .deactivate: driver.deactivate(apply: client.apply)
            case .commit: end()
            case .confirmed:
                // client 가 현재 mark 를 실제로 확정한다. insert 직후라면 이미 이전 mark 가 확정됐다.
                proxy.text += proxy.marked
                proxy.marked = ""
                driver.end(.alreadyCommittedByClient, apply: client.apply)
            case .sourceFalse: driver.sourceChanged(selected: false, apply: client.apply)
            }
        }
    }
}

private enum InterleavingEvent: String, CaseIterable {
    case activate, deactivate, commit, confirmed, sourceFalse
}

private let interleavingSequences: [[InterleavingEvent]] = {
    let events = InterleavingEvent.allCases
    return [[]] + events.map { [$0] } + events.flatMap { first in events.map { [first, $0] } }
}()

@Test("coordinator·Client: insert·mark 직후 lifecycle 유한 순서에서 글자와 조합을 보존한다", arguments: [false, true])
func interleavingLifecycleMatrix(startsInEnglish: Bool) {
    for insertEvents in interleavingSequences {
        for markEvents in interleavingSequences {
            let host = InterleavingHost(startsInEnglish: startsInEnglish)
            #expect(host.coordinator.clientApp?.bundleID == "homi.tests")
            #expect(host.modes.memory.mode(for: "homi.tests") == .korean)
            for code: UInt16 in [5, 40, 1] { #expect(host.key(code).handled) } // 한
            host.proxy.onInsert = { host.run(insertEvents) }
            host.proxy.onMark = { host.run(markEvents) }
            #expect(host.key(15).handled) // insert 한 → mark ㄱ
            let context = "start=\(startsInEnglish), insert=\(insertEvents), mark=\(markEvents)"
            #expect(host.proxy.text + host.proxy.marked == "한ㄱ", "\(context)")
            #expect(host.proxy.marked == host.driver.composing, "\(context)")
            #expect(!host.driver.isHandlingEvent && !host.driver.hasExplicitEnd, "\(context)")
            host.end()
            host.end()
            #expect(host.proxy.text == "한ㄱ" && host.proxy.marked.isEmpty, "\(context)")
            #expect(host.driver.composing.isEmpty && !host.driver.isHandlingEvent, "\(context)")
        }
    }
}

@Test("coordinator·Client: 일반 key 가 순서대로 오면 조합과 mark 가 일치한다")
func interleavingOrdinaryKeySequential() {
    let host = InterleavingHost(startsInEnglish: false)
    for code: UInt16 in [5, 40, 1, 15, 40] { #expect(host.key(code).handled) }
    #expect(host.proxy.text == "한")
    #expect(host.proxy.marked == "가")
    #expect(host.driver.composing == "가")
    host.end()
    #expect(host.proxy.text == "한가")
}

// 같은 controller 에 일반 key 가 client 호출 중 재진입할 수 있다는 조건의 코드 반례다.
// 2026-11-03 실제 IMK 는 insert·mark 호출 중의 새 key 를 homi 에 넣지 않았다 — 글자 그대로 넣거나 버렸다 (docs/macos-input.md).
// 이 test 는 그 전달 경로를 가정한 code 의 동작을 고정한다.
@Test("coordinator·Client: 가정한 insert 직후 일반 key 재진입의 조합 일치")
func interleavingOrdinaryKeyNested() {
    let host = InterleavingHost(startsInEnglish: false)
    for code: UInt16 in [5, 40, 1] { #expect(host.key(code).handled) }
    host.proxy.onInsert = { #expect(host.key(40).handled) }
    #expect(host.key(15).handled)
    #expect(host.proxy.text == "한")
    #expect(host.driver.composing == "가")
    withKnownIssue("일반 key 중첩을 가정하면 오래된 mark 가 덮는다. 실제 IMK 는 insert·mark 중의 새 key 를 homi 에 넣지 않았다 (2026-11-03).") {
        #expect(host.proxy.marked == host.driver.composing)
    }
}
