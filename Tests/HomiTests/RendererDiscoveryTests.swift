import Foundation
import InputSession
import Testing

@testable import homi

private let fixtureApp = URL(fileURLWithPath: "/homi-tests/Example.app")
private let fixtureFrameworks = fixtureApp.appending(path: "Contents/Frameworks")
private struct Unreadable: Error {}

private final class Directories {
    var entries: [String: [String]] = [:]
    var calls: [String] = []

    func read(_ url: URL) throws -> [String] {
        calls.append(url.path)
        guard let names = entries[url.path] else { throw Unreadable() }
        return names
    }
}

@Test("renderer: cold 첫 commit 도 기존 helper 정책을 쓰고 cache 뒤에도 source 는 새로 읽는다", arguments: [false, true])
func rendererFirstColdCommit(nested: Bool) throws {
    let app = try #require(ClientAppID("homi.tests.renderer"))
    let files = Directories()
    let helpers = fixtureFrameworks.appending(path: "Example.framework/Helpers")
    files.entries[fixtureFrameworks.path] = nested ? ["Example.framework"] : ["Example Helper (Renderer).app"]
    if nested { files.entries[helpers.path] = ["Example Helper (Renderer).app"] }
    var lookups = 0
    let discovery = RendererDiscovery(locate: { _ in lookups += 1; return fixtureApp }, contents: files.read)
    let driver = SessionDriver()
    var delivered: [Action] = []
    var sourceReads = 0

    func compose() {
        for code: UInt16 in [5, 40, 1] { // 한
            driver.perform({ $0.handle(KeyEvent(keyCode: code), mode: .korean) }, apply: { _ in })
        }
    }

    compose()
    let first = CommitPolicy.decide(app: app, inspect: { discovery.inspect($0.bundleID) }, homiSelected: {
        sourceReads += 1
        #expect(!files.calls.isEmpty)
        return true
    })
    driver.end(first.ending) { delivered += $0 }
    #expect(first.renderer == .helperRenderer)
    #expect(delivered.isEmpty) // client 확정 뒤 callback 에서 같은 글자를 다시 넣지 않는다.
    #expect(driver.composing.isEmpty)
    let readsAfterFirst = files.calls.count

    compose()
    let second = CommitPolicy.decide(app: app, inspect: { discovery.inspect($0.bundleID) }, homiSelected: {
        sourceReads += 1
        return false
    })
    driver.end(second.ending) { delivered += $0 }
    #expect(delivered == [.insert("한")])
    #expect(files.calls.count == readsAfterFirst)
    #expect(lookups == 1)
    #expect(sourceReads == 2)
}

@Test("renderer: 확인한 부재만 cache 한다")
func rendererConfirmedAbsenceIsCached() {
    let files = Directories()
    files.entries[fixtureFrameworks.path] = []
    let discovery = RendererDiscovery(locate: { _ in fixtureApp }, contents: files.read)
    #expect(discovery.inspect("homi.tests.native") == .notFound)
    let reads = files.calls.count
    #expect(discovery.inspect("homi.tests.native") == .notFound)
    #expect(files.calls.count == reads)
}

@Test("renderer: 위치·읽기 실패는 부재로 고정하지 않고 다음 callback 에 회복한다", arguments: [false, true])
func rendererUnavailableCanRecover(locationMissing: Bool) throws {
    let app = try #require(ClientAppID("homi.tests.recovered"))
    let files = Directories()
    var available = false
    let discovery = RendererDiscovery(locate: { _ in
        locationMissing && !available ? nil : fixtureApp
    }, contents: files.read)
    var sourceReads = 0
    func decide() -> CommitPolicy.Decision {
        CommitPolicy.decide(app: app, inspect: { discovery.inspect($0.bundleID) }, homiSelected: {
            sourceReads += 1
            return true
        })
    }
    let first = decide()
    #expect(first.renderer == .unavailable)
    #expect(first.ending == .commitToClient)
    #expect(sourceReads == 0)

    available = true
    files.entries[fixtureFrameworks.path] = ["Example Helper (Renderer).app"]
    let recovered = decide()
    #expect(recovered.renderer == .helperRenderer)
    #expect(recovered.ending == .alreadyCommittedByClient)
    #expect(sourceReads == 1)
}

@Test("renderer: 없는 Frameworks·Helpers 는 부모 목록으로 확인한 뒤 부재로 cache 한다", arguments: [false, true])
func rendererMissingDirectoryNeedsParentEvidence(missingFrameworks: Bool) {
    let files = Directories()
    if missingFrameworks {
        files.entries[fixtureApp.appending(path: "Contents").path] = ["Info.plist", "MacOS"]
    } else {
        files.entries[fixtureFrameworks.path] = ["Native.framework"]
        files.entries[fixtureFrameworks.appending(path: "Native.framework").path] = ["Native", "Versions"]
    }
    let discovery = RendererDiscovery(locate: { _ in fixtureApp }, contents: files.read)
    #expect(discovery.inspect("homi.tests.native") == .notFound)
    let reads = files.calls.count
    #expect(discovery.inspect("homi.tests.native") == .notFound)
    #expect(files.calls.count == reads)
}

@Test("renderer: 일부 경로를 못 읽으면 다른 renderer 를 발견했어도 부재를 확정하지 않는다", arguments: [false, true])
func rendererPartialReadRemainsUnknown(otherPresent: Bool) {
    let files = Directories()
    files.entries[fixtureFrameworks.path] = ["Partial.framework"] + (otherPresent ? ["Codex (Renderer).app"] : [])
    let framework = fixtureFrameworks.appending(path: "Partial.framework")
    files.entries[framework.path] = ["Helpers"]
    let discovery = RendererDiscovery(locate: { _ in fixtureApp }, contents: files.read)
    #expect(discovery.inspect("homi.tests.partial") == .unavailable)
    files.entries[framework.appending(path: "Helpers").path] = ["Example Helper (Renderer).app"]
    #expect(discovery.inspect("homi.tests.partial") == .helperRenderer)
}

@Test("renderer: 앞 경로를 못 읽었어도 뒤에서 확인한 기존 helper 는 유효하다")
func rendererPositiveHelperSurvivesOtherReadFailure() {
    let files = Directories()
    files.entries[fixtureFrameworks.path] = ["Unreadable.framework", "Browser.framework"]
    files.entries[fixtureFrameworks.appending(path: "Unreadable.framework").path] = ["Helpers"]
    files.entries[fixtureFrameworks.appending(path: "Browser.framework/Helpers").path] = ["Example Helper (Renderer).app"]
    let discovery = RendererDiscovery(locate: { _ in fixtureApp }, contents: files.read)
    #expect(discovery.inspect("homi.tests.browser") == .helperRenderer)
    let reads = files.calls.count
    #expect(discovery.inspect("homi.tests.browser") == .helperRenderer)
    #expect(files.calls.count == reads)
}

@Test("renderer: ChatGPT 의 다른 helper 이름은 발견하되 기존 commit 우회를 적용하지 않는다",
    arguments: ["Codex (Renderer).app", "Codex (Aperitif Renderer).app"])
func rendererOtherNamesRemainEvidence(name: String) throws {
    let app = try #require(ClientAppID("com.openai.codex"))
    let files = Directories()
    files.entries[fixtureFrameworks.path] = ["Codex Framework.framework"]
    files.entries[fixtureFrameworks.appending(path: "Codex Framework.framework/Helpers").path] = [name]
    let discovery = RendererDiscovery(locate: { _ in fixtureApp }, contents: files.read)
    let decision = CommitPolicy.decide(app: app, inspect: { discovery.inspect($0.bundleID) }, homiSelected: {
        Issue.record("다른 renderer 이름의 발견만으로 source 를 읽거나 우회를 적용하면 안 된다")
        return true
    })
    #expect(decision.renderer == .otherRenderer)
    #expect(decision.ending == .commitToClient)
    #expect(decision.sourceSelected == nil)
}

@Test("renderer: 다른 이름을 먼저 찾아도 기존 helper 탐색을 끝낸다")
func rendererHelperTakesPrecedenceOverOtherNames() {
    let files = Directories()
    files.entries[fixtureFrameworks.path] = ["Codex (Renderer).app", "Browser.framework"]
    files.entries[fixtureFrameworks.appending(path: "Browser.framework/Helpers").path] = ["Example Helper (Renderer).app"]
    let discovery = RendererDiscovery(locate: { _ in fixtureApp }, contents: files.read)
    #expect(discovery.inspect("homi.tests.mixed") == .helperRenderer)
}
