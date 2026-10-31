import AppKit
import HangulCore
import InputSession
import Testing

@testable import homi

private let candidateDictionary = try! HanjaDictionary(contentsOf: URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appending(path: "Sources/homi/Bundle/Resources/hanja.txt"))
private let convert = KeyEvent(keyCode: KeyCode.returnKey, modifiers: .option)

private nonisolated final class CandidateTestOwner: CandidateOwner {
    let driver: SessionDriver
    init(driver: SessionDriver) { self.driver = driver }
    var candidateRevision: UInt64 { driver.candidateRevision }
    var hasCandidates: Bool { driver.hasCandidates }
    var isHandlingEvent: Bool { driver.isHandlingEvent }
    func afterEvent(_ presentation: @escaping () -> Void) { driver.afterEvent(presentation) }
}

private nonisolated final class CandidateModes: ModeStore {
    var memory = ModeMemory(modes: ["homi.tests": .korean])
    func withMemory<Result: Sendable>(_ operation: (inout ModeMemory) -> Result) -> Result { operation(&memory) }
    func save(_ snapshot: ModeMemory) {}
}

/// 실제 Task 대신 원하는 순서로 실행한다. 입력·판단·Client·표시 guard 는 제품 코드다.
private nonisolated final class CandidateQueue {
    var work: [CandidatePresentation.Work] = []
    func enqueue(_ item: @escaping CandidatePresentation.Work) { work.append(item) }
    @MainActor func run(_ index: Int = 0) { work.remove(at: index)() }
    @MainActor func drainReversed() { while !work.isEmpty { run(work.count - 1) } }
}

private final class CandidateDisplay: CandidateDisplaying {
    weak var active: (any CandidateOwner)?
    weak var displayedOwner: (any CandidateOwner)?
    var candidates: [Candidate] = []
    var selected: Int?
    var shown = 0
    var hidden = 0
    var line: NSRect?

    func show(_ candidates: [Candidate], selected: Int, below line: NSRect, owner: any CandidateOwner) {
        displayedOwner = owner
        self.candidates = candidates
        self.selected = selected
        self.line = line
        shown += 1
    }
    func hide(owner: any CandidateOwner) {
        guard displayedOwner === owner else { return }
        displayedOwner = nil
        candidates = []
        selected = nil
        hidden += 1
    }
}

private final class CandidateHost {
    let owner = CandidateTestOwner(driver: SessionDriver(hanja: candidateDictionary))
    let modes = CandidateModes()
    let proxy = TextProxy()
    let queue = CandidateQueue()
    let display: CandidateDisplay
    let client: Client
    let coordinator: InputCoordinator
    var driver: SessionDriver { owner.driver }

    init(display: CandidateDisplay = CandidateDisplay()) {
        self.display = display
        display.active = owner
        let presentation = CandidatePresentation(owner: owner, panel: { display },
            isActive: { display.active === $0 }, enqueue: queue.enqueue)
        client = Client(proxy: proxy, trace: owner.driver.clientTrace, candidates: presentation)
        coordinator = InputCoordinator(driver: owner.driver, modes: modes,
            profile: { _ in AppProfile() }, fallbackApp: { "homi.tests" })
    }

    func type(_ codes: [UInt16] = [5, 40, 1]) { // 한
        for code in codes { send(KeyEvent(keyCode: code)) }
    }
    func send(_ key: KeyEvent) { coordinator.keyDown(key, client: client) }
    func open() { type(); send(convert) }

    /// 표시 작업만 실행해서 문서·Session·mode·질의 횟수가 달라지면 안 된다.
    func drainWithoutInputChanges() {
        let text = proxy.text, marked = proxy.marked, composing = driver.composing
        let memory = modes.memory, queries = proxy.queryCount, choosing = driver.hasCandidates
        queue.drainReversed()
        #expect(proxy.text == text && proxy.marked == marked)
        #expect(driver.composing == composing && driver.hasCandidates == choosing)
        #expect(modes.memory == memory)
        #expect(proxy.queryCount == queries)
    }
}

@Test("후보 표시: Option release·무시한 event·무변화 한자 key 는 예약한 show 를 지우지 않는다",
    arguments: ["modifier", "ignored", "convert"], ["key", "tap"])
func candidateDisplaySurvivesUnchangedInput(event: String, trigger: String) {
    let host = CandidateHost()
    host.type()
    if trigger == "key" { host.send(convert) }
    else { host.coordinator.modifiersChanged(client: host.client, action: { _, _ in .hanja }) }
    #expect(host.queue.work.count == 1)
    let before = host.driver.inputRevision
    switch event {
    case "modifier": host.coordinator.modifiersChanged(client: host.client, action: { _, _ in nil })
    case "ignored": host.coordinator.ignoredEvent(client: host.client)
    default: host.send(convert)
    }
    #expect(host.driver.inputRevision != before)
    #expect(host.driver.hasCandidates)
    host.drainWithoutInputChanges()
    #expect(host.display.shown == 1)
    #expect(host.display.selected == 0)
    #expect(host.display.candidates.first?.hanja == "韓")
    #expect(host.display.line == NSRect(x: 10, y: 20, width: 0, height: 18))
    #expect(host.proxy.queryCount == 1) // 후보 위치 질의 하나. Task 는 client 에 묻지 않는다.
}

@Test("후보 표시: 최신 선택을 보인 뒤 늦은 show 가 선택을 되돌리지 않는다")
func candidateDisplayRejectsOldSelection() {
    let host = CandidateHost()
    host.open()
    host.send(KeyEvent(keyCode: KeyCode.down))
    #expect(host.queue.work.count == 2)
    host.drainWithoutInputChanges()
    #expect(host.display.shown == 1)
    #expect(host.display.selected == 1)
    #expect(host.proxy.queryCount == 2)
}

@Test("후보 표시: 취소·확정·전환·focus 종료 뒤 늦은 show 가 되살아나지 않는다",
    arguments: ["escape", "pick", "toggle", "deactivate", "source", "confirmed", "mouse"])
func candidateDisplayRejectsEndedComposition(ending: String) {
    let host = CandidateHost()
    host.open()
    switch ending {
    case "escape": host.send(KeyEvent(keyCode: KeyCode.escape))
    case "pick": host.send(KeyEvent(keyCode: KeyCode.returnKey))
    case "toggle": host.coordinator.modifiersChanged(client: host.client, action: { _, _ in .toggle })
    case "deactivate": host.driver.deactivate(apply: host.client.apply)
    case "source": host.driver.sourceChanged(selected: false, apply: host.client.apply)
    case "confirmed": host.driver.end(.alreadyCommittedByClient, apply: host.client.apply)
    default: host.coordinator.mouseDown(client: host.client, boundClient: { host.client })
    }
    #expect(!host.driver.hasCandidates)
    host.drainWithoutInputChanges()
    #expect(host.display.shown == 0)
    #expect(host.display.displayedOwner == nil)
    if ending == "escape" { #expect(host.driver.composing == "한") }
    else { #expect(host.driver.composing.isEmpty) }
}

@Test("후보 표시: 같은 글자로 다시 열어도 옛 show·hide 는 새 창을 바꾸지 않는다")
func candidateDisplayRejectsPreviousOpening() {
    let host = CandidateHost()
    host.open()
    host.send(KeyEvent(keyCode: KeyCode.escape))
    host.send(convert)
    #expect(host.queue.work.count == 3)
    host.drainWithoutInputChanges()
    #expect(host.display.shown == 1)
    #expect(host.display.hidden == 0)
    #expect(host.display.candidates.first?.hanja == "韓")
}

@Test("후보 표시: 후보 내용을 짧은 단어로 바꾼 뒤 옛 목록을 버린다")
func candidateDisplayRejectsOldContents() {
    let host = CandidateHost()
    host.type([5, 40, 1, 13, 40]) // 한자
    #expect(host.driver.composing == "자" && host.proxy.text == "한")
    host.driver.perform({ $0.handle(convert, mode: .korean, textBefore: { _ in ("한", 1) }) },
        apply: { host.client.apply($0.actions) })
    host.send(convert) // 한자 → 자
    #expect(host.queue.work.count == 2)
    host.drainWithoutInputChanges()
    #expect(host.display.shown == 1)
    #expect(host.display.candidates == candidateDictionary.candidates(for: "자"))
}

@Test("후보 표시: caret 질의 중 lifecycle 이 와도 flush 전에는 UI 를 예약하지 않는다", arguments: [false, true])
func candidateDisplayWaitsForCaretReentry(resuming: Bool) {
    let host = CandidateHost()
    host.type()
    host.proxy.onCaretQuery = {
        #expect(host.driver.isHandlingEvent)
        #expect(host.queue.work.isEmpty)
        host.driver.deactivate(apply: host.client.apply)
        if resuming { host.driver.activate() }
        #expect(host.queue.work.isEmpty)
    }
    host.send(convert)
    #expect(!host.driver.isHandlingEvent)
    host.drainWithoutInputChanges()
    #expect(host.display.shown == (resuming ? 1 : 0))
    #expect(host.proxy.text == (resuming ? "" : "한"))
}

@Test("후보 표시: 다른 owner 의 표시를 옛 show·hide 가 건드리지 않는다")
func candidateDisplayKeepsActiveOwner() {
    let first = CandidateHost()
    first.open()
    let second = CandidateHost(display: first.display)
    second.open()
    second.drainWithoutInputChanges()
    first.drainWithoutInputChanges()
    #expect(first.display.displayedOwner === second.owner)
    #expect(first.display.shown == 1)
    first.driver.deactivate(apply: first.client.apply)
    first.drainWithoutInputChanges()
    #expect(first.display.displayedOwner === second.owner)
    #expect(first.display.hidden == 0)
}

@Test("후보 표시: event·Session mutation 중에 실행된 UI 는 client·panel 을 건드리지 않는다", arguments: [false, true])
func candidateDisplayRejectsBusyOwner(mutating: Bool) {
    let host = CandidateHost()
    host.open()
    if mutating {
        host.driver.perform({ session in
            host.queue.run() // guard 가 Session 을 읽으면 exclusive access 와 충돌한다.
            return session.hasCandidates
        }, apply: { #expect($0) })
    } else { host.driver.withEvent { host.queue.run() } }
    #expect(host.display.shown == 0)
    #expect(host.driver.hasCandidates)
    #expect(host.proxy.queryCount == 1)
}

@Test("후보 표시: 보이는 창을 종료하고 modifier 가 와도 hide 는 실행한다")
func candidateDisplayHidesAfterUnchangedInput() {
    let host = CandidateHost()
    host.open()
    host.queue.run()
    #expect(host.display.displayedOwner === host.owner)
    host.coordinator.modifiersChanged(client: host.client, action: { _, _ in .toggle })
    host.coordinator.modifiersChanged(client: host.client, action: { _, _ in nil })
    host.drainWithoutInputChanges()
    #expect(host.display.displayedOwner == nil)
    #expect(host.display.hidden == 1)
    #expect(host.proxy.text == "한" && host.proxy.marked.isEmpty)
    #expect(host.modes.memory.mode(for: "homi.tests") == .english)
}

@Test("후보 표시: 기본 조합·Backspace·확정은 후보 revision·UI·caret 질의를 만들지 않는다")
func candidateDisplayLeavesOrdinaryCompositionAlone() {
    let host = CandidateHost()
    host.type([5, 40, 1, 15, 46, 3]) // 한글
    host.send(KeyEvent(keyCode: KeyCode.delete))
    #expect(host.proxy.marked == "그")
    host.send(KeyEvent(keyCode: 3))
    host.driver.deactivate(apply: host.client.apply)
    #expect(host.proxy.text == "한글" && host.proxy.marked.isEmpty)
    #expect(host.driver.candidateRevision == 0)
    #expect(host.queue.work.isEmpty)
    #expect(host.proxy.queryCount == 0)
}
