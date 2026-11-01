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
    }, sourceSelection: {
        calls.append("source")
        return selected ? .selected : .other
    })
    #expect(calls == ["inspect", "source"])
    #expect(decision.renderer == .helperRenderer)
    #expect(decision.sourceSelection == (selected ? .selected : .other))
    #expect(decision.ending == (selected ? .alreadyCommittedByClient : .commitToClient))
}

@Test("commit 정책: 다른 renderer 이름·부재·미확인은 Chromium 우회로 승격하지 않는다",
    arguments: [RendererEvidence.otherRenderer, .notFound, .unavailable])
func commitPolicyKeepsUnverifiedEvidenceSeparate(renderer: RendererEvidence) throws {
    let app = try #require(ClientAppID("homi.tests.other-renderer"))
    let decision = CommitPolicy.decide(app: app, inspect: { _ in renderer }, sourceSelection: {
        Issue.record("이 근거에서는 source 를 질의하지 않아야 한다")
        return .selected
    })
    #expect(decision.renderer == renderer)
    #expect(decision.sourceSelection == nil)
    #expect(decision.ending == .commitToClient)
}

@Test("commit 정책: 실제 client ID 가 없으면 fallback app 을 조사하지 않는다")
func commitPolicyWithoutClientID() {
    let decision = CommitPolicy.decide(app: nil, inspect: { _ in
        Issue.record("ID 없는 callback 에서는 bundle 을 조사하지 않아야 한다")
        return .helperRenderer
    }, sourceSelection: {
        Issue.record("ID 없는 callback 에서는 source 를 질의하지 않아야 한다")
        return .selected
    })
    #expect(decision.renderer == .unavailable)
    #expect(decision.sourceSelection == nil)
    #expect(decision.ending == .commitToClient)
}

@Test("commit 정책: unknown 을 조회하지 않음과 구별하고 false fallback 을 명시한다",
    arguments: [SourceSelection.UnknownReason.sourceCopyNil, .propertyNil, .typeMismatch, .emptyID])
func commitPolicyUnknownKeepsCompatibility(reason: SourceSelection.UnknownReason) throws {
    let app = try #require(ClientAppID("homi.tests.renderer"))
    var reads = 0
    let decision = CommitPolicy.decide(app: app, inspect: { _ in .helperRenderer }, sourceSelection: {
        reads += 1
        return .unknown(reason)
    })
    #expect(reads == 1)
    #expect(decision.sourceSelection == .unknown(reason))
    #expect(decision.ending == .commitToClient)
    #expect(decision.sourceSelection?.diagnostic == "unknown(\(reason.rawValue))")
}
