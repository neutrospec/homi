import AppKit
import InputSession
import Testing
@testable import homi

private nonisolated final class ModeOwner: CandidateOwner {
    let driver = SessionDriver()
    var candidateRevision: UInt64 { driver.candidateRevision }
    var hasCandidates: Bool { driver.hasCandidates }
    var isHandlingEvent: Bool { driver.isHandlingEvent }
    func afterEvent(_ presentation: @escaping () -> Void) { driver.afterEvent(presentation) }
}

private nonisolated final class ModeQueue {
    var work: [ModePresentation.Work] = []
    func enqueue(_ action: @escaping ModePresentation.Work) { work.append(action) }
    @MainActor func run(_ index: Int = 0) { work.remove(at: index)() }
}

private final class ModeDisplay {
    weak var active: ModeOwner?
    var context: ModePresentationContext? = .init(app: "test.app", mode: .korean, passThrough: false)
    var shows: [(String, NSRect)] = []
}

private final class ModeHost {
    let owner = ModeOwner()
    let queue = ModeQueue()
    let display = ModeDisplay()
    lazy var presentation = ModePresentation(owner: owner, context: { [display] _ in display.context },
        isActive: { [display] in display.active === $0 },
        display: { [display] text, line in display.shows.append((text, line)) }, enqueue: queue.enqueue)
    init() { display.active = owner }
    var korean: ModePresentationContext { .init(app: "test.app", mode: .korean, passThrough: false) }
    var english: ModePresentationContext { .init(app: "test.app", mode: .english, passThrough: false) }
    func request(_ text: String, _ expected: ModePresentationContext?, caret: () -> NSRect = { NSRect(x: 4, y: 5, width: 1, height: 1) }) {
        presentation.request(text, expected: expected, caret: caret)
    }
}

@Test("mode 표시: caret 질의 중 새 요청과 역순 Task는 최신만 그린다")
func modePresentationNestedAndReversed() {
    let host = ModeHost()
    host.request("old", host.korean) {
        host.display.context = host.english
        host.request("new", host.english) { NSRect(x: 10, y: 20, width: 1, height: 1) }
        return NSRect(x: 1, y: 2, width: 1, height: 1)
    }
    #expect(host.queue.work.count == 2)
    host.queue.run(1); host.queue.run()
    #expect(host.display.shows.count == 1 && host.display.shows[0].0 == "new")
    #expect(host.display.shows[0].1.origin == NSPoint(x: 10, y: 20))
}

@Test("mode 표시: mode ABA는 오래된 요청을 되살리지 않는다")
func modePresentationModeABA() {
    let host = ModeHost()
    host.request("first", host.korean)
    host.display.context = host.english; host.request("middle", host.english)
    host.display.context = host.korean; host.request("last", host.korean)
    host.queue.run(2); host.queue.run(); host.queue.run()
    #expect(host.display.shows.map(\.0) == ["last"])
}

@Test("mode 표시: owner·app·mode·pass-through 불일치와 미확인 app은 표시하지 않는다", arguments: ["owner", "app", "mode", "pass", "unknown"])
func modePresentationInvalidContext(kind: String) {
    let host = ModeHost()
    host.request("old", kind == "unknown" ? nil : host.korean)
    switch kind {
    case "owner": host.display.active = nil
    case "app": host.display.context = .init(app: "other", mode: .korean, passThrough: false)
    case "mode": host.display.context = host.english
    case "pass": host.display.context = .init(app: "test.app", mode: .korean, passThrough: true)
    default: break
    }
    while !host.queue.work.isEmpty { host.queue.run() }
    #expect(host.display.shows.isEmpty)
}

@Test("mode 표시: 무효화 뒤 같은 owner·context로 돌아와도 옛 요청을 되살리지 않는다")
func modePresentationLifecycleInvalidation() {
    let host = ModeHost()
    host.request("old", host.korean)
    // 제품 lifecycle hook 은 이 invalidate 를 호출한다. 소유권 자체는 별도 active 검사다.
    host.presentation.invalidate()
    host.display.active = nil
    host.display.active = host.owner
    host.queue.run()
    #expect(host.display.shows.isEmpty)
}

@Test("mode 표시: 새 event가 busy일 때는 event 종료까지 다시 연결하고 입력 상태를 건드리지 않는다")
func modePresentationWaitsForEvent() {
    let host = ModeHost()
    var caretQueries = 0
    host.request("한", host.korean) {
        caretQueries += 1
        return NSRect(x: 4, y: 5, width: 1, height: 1)
    }
    host.owner.driver.withEvent {
        host.queue.run()
        #expect(host.queue.work.isEmpty && host.display.shows.isEmpty)
        let outcome = host.owner.driver.perform({ $0.handle(KeyEvent(keyCode: 5), mode: .korean) }, apply: { _ in })
        #expect(outcome.handled && host.owner.driver.composing == "ㅎ")
    }
    #expect(host.queue.work.count == 1)
    let revision = host.owner.driver.inputRevision
    host.queue.run()
    #expect(host.display.shows.map(\.0) == ["한"])
    #expect(host.owner.driver.composing == "ㅎ" && host.owner.driver.inputRevision == revision)
    #expect(caretQueries == 1)
}

@Test("mode 표시: 무변화 event는 기존 요청을 취소하지 않는다")
func modePresentationUnchangedEvent() {
    let host = ModeHost()
    host.request("한", host.korean)
    host.owner.driver.withEvent {}
    host.queue.run()
    #expect(host.display.shows.map(\.0) == ["한"])
}

@Test("mode 표시: owner가 사라지면 대기 작업은 화면에 그리지 않는다")
func modePresentationOwnerLifetime() {
    let queue = ModeQueue()
    let display = ModeDisplay()
    var owner: ModeOwner? = ModeOwner()
    display.active = owner
    var presentation: ModePresentation? = ModePresentation(owner: owner!, context: { [display] _ in display.context },
        isActive: { [display] in display.active === $0 },
        display: { [display] text, line in display.shows.append((text, line)) }, enqueue: queue.enqueue)
    presentation!.request("한", expected: .init(app: "test.app", mode: .korean, passThrough: false)) { .zero }
    owner = nil
    presentation = nil
    queue.run()
    #expect(display.shows.isEmpty)
}
