import Testing

@testable import InputSession

@Test("commit 정책: 기존 helper 를 확인한 뒤 현재 source 를 한 번 읽는다", arguments: [false, true])
func commitPolicyReadsSourceAfterRenderer(selected: Bool) throws {
    let app = try #require(ClientAppID("homi.tests.renderer"))
    var calls: [String] = []
    let decision = CommitPolicy.decide(app: app, inspect: {
        #expect($0 == app)
        calls.append("inspect")
        return .helperRenderer
    }, homiSelected: {
        calls.append("source")
        return selected
    })
    #expect(calls == ["inspect", "source"])
    #expect(decision.renderer == .helperRenderer)
    #expect(decision.sourceSelected == selected)
    #expect(decision.ending == (selected ? .alreadyCommittedByClient : .commitToClient))
}

@Test("commit 정책: 다른 renderer 이름·부재·미확인은 Chromium 우회로 승격하지 않는다",
    arguments: [RendererEvidence.otherRenderer, .notFound, .unavailable])
func commitPolicyKeepsUnverifiedEvidenceSeparate(renderer: RendererEvidence) throws {
    let app = try #require(ClientAppID("homi.tests.other-renderer"))
    let decision = CommitPolicy.decide(app: app, inspect: { _ in renderer }, homiSelected: {
        Issue.record("이 근거에서는 source 를 질의하지 않아야 한다")
        return true
    })
    #expect(decision.renderer == renderer)
    #expect(decision.sourceSelected == nil)
    #expect(decision.ending == .commitToClient)
}

@Test("commit 정책: 실제 client ID 가 없으면 fallback app 을 조사하지 않는다")
func commitPolicyWithoutClientID() {
    let decision = CommitPolicy.decide(app: nil, inspect: { _ in
        Issue.record("ID 없는 callback 에서는 bundle 을 조사하지 않아야 한다")
        return .helperRenderer
    }, homiSelected: {
        Issue.record("ID 없는 callback 에서는 source 를 질의하지 않아야 한다")
        return true
    })
    #expect(decision.renderer == .unavailable)
    #expect(decision.sourceSelected == nil)
    #expect(decision.ending == .commitToClient)
}
