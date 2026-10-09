import Foundation
import Testing

@testable import InputSession

@Suite("ClientTrace — 내용 없는 client 호출 관측")
struct ClientTraceTests {
    private let composing = ClientTrace.State(composing: true, candidates: false)

    @Test("driver 의 cache 는 mutating 질의 중에도 읽고 반환 뒤에만 갱신한다")
    func driverCacheDuringQuery() {
        let driver = SessionDriver(hanja: dictionary)
        let trace = driver.clientTrace
        var observed: ClientTrace.Snapshot?
        _ = driver.perform({
            $0.handle(optionReturn, mode: .korean, selectedText: {
                #expect(driver.isMutatingSession)
                observed = trace.snapshot
                driver.deactivate(apply: { _ in })
                driver.activate()
                #expect(trace.snapshot == observed)
                return "한자"
            })
        }, apply: { _ in })
        #expect(observed?.cachedState == .init(composing: false, candidates: false))
        #expect(trace.snapshot.cachedState == .init(composing: false, candidates: true))
        #expect(!driver.isMutatingSession)
        driver.commit(apply: { _ in })
        #expect(trace.snapshot.cachedState == .init(composing: false, candidates: false))
    }

    @Test("insert 중 callback 은 다음 mark 계획과 이전 mark 호출을 구분한다")
    func nextPlanDuringInsert() throws {
        let trace = ClientTrace()
        let previous = trace.plan([.mark("한")], state: composing)
        let oldMark = try #require(previous.call(at: 0))
        trace.withCall(oldMark) {}

        let batch = trace.plan([.insert("한"), .mark("ㄱ")], state: composing)
        let insert = try #require(batch.call(at: 0))
        let mark = try #require(batch.call(at: 1))
        var callback: ClientTrace.Snapshot?
        trace.withEvent {
            trace.withBatch(batch) {
                trace.withCall(insert) { callback = trace.snapshot }
                trace.withCall(mark) {}
            }
        }

        let observed = try #require(callback)
        #expect(observed.cachedState == composing)
        #expect(observed.localMarkPlan == mark.markPlan)
        #expect(observed.lastMarkCallAttempt == oldMark.markPlan)
        #expect(observed.lastMarkCallReturn == oldMark.markPlan)
        #expect(observed.localMarkPlan != observed.lastMarkCallAttempt)
        #expect(observed.frame?.kind == .insert)
        #expect(observed.frame?.actionIndex == 0)
        #expect(observed.batchID == batch.id)
        #expect(observed.eventID != nil)
        #expect(trace.snapshot.lastMarkCallReturn == mark.markPlan)
        #expect(trace.snapshot.eventID == nil)
        #expect(trace.snapshot.batchID == nil)
        #expect(trace.snapshot.frame == nil)
    }

    @Test("mark 중 callback 은 호출 시작과 정상 반환을 구분한다")
    func markAttemptBeforeReturn() throws {
        let trace = ClientTrace()
        let old = try #require(trace.plan([.mark("ㅎ")], state: composing).call(at: 0))
        trace.withCall(old) {}
        let next = try #require(trace.plan([.mark("하")], state: composing).call(at: 0))
        trace.withCall(next) {
            let callback = trace.snapshot
            #expect(callback.localMarkPlan == next.markPlan)
            #expect(callback.lastMarkCallAttempt == next.markPlan)
            #expect(callback.lastMarkCallReturn == old.markPlan)
            #expect(callback.frame?.markPlan == next.markPlan)
        }
        #expect(trace.snapshot.lastMarkCallReturn == next.markPlan)
    }

    @Test("중첩 call·batch·event 가 끝나면 이전 frame 과 scope 를 복구한다")
    func nestedScopesRestore() throws {
        let trace = ClientTrace()
        let outer = trace.plan([.insert("한"), .mark("ㄱ")], state: composing)
        let outerCall = try #require(outer.call(at: 0))
        trace.withEvent {
            let eventID = trace.snapshot.eventID
            trace.withBatch(outer) {
                trace.withCall(outerCall) {
                    let outerFrame = trace.snapshot.frame
                    trace.withEvent {
                        let inner = trace.plan([.layout("private-layout")], state: composing)
                        trace.withBatch(inner) {
                            trace.withCall(.query) {
                                #expect(trace.snapshot.eventID == eventID)
                                #expect(trace.snapshot.batchID == inner.id)
                                #expect(trace.snapshot.frame?.kind == .query)
                                #expect(trace.snapshot.frame?.depth == 2)
                            }
                        }
                    }
                    #expect(trace.snapshot.frame == outerFrame)
                    #expect(trace.snapshot.batchID == outer.id)
                    #expect(trace.snapshot.eventID == eventID)
                }
                #expect(trace.snapshot.frame == nil)
            }
            #expect(trace.snapshot.batchID == nil)
        }
        #expect(trace.snapshot.eventID == nil)
    }

    @Test("throw 로 끝나도 frame 을 복구하고 mark 정상 반환으로 기록하지 않는다")
    func throwingCallRestores() throws {
        enum Failure: Error { case expected }
        let trace = ClientTrace()
        let mark = try #require(trace.plan([.mark("한")], state: composing).call(at: 0))
        trace.withCall(.query) {
            let outer = trace.snapshot.frame
            do {
                try trace.withCall(mark) { throw Failure.expected }
                Issue.record("throw 가 전달되어야 한다")
            } catch Failure.expected {
                #expect(trace.snapshot.frame == outer)
                #expect(trace.snapshot.lastMarkCallAttempt == mark.markPlan)
                #expect(trace.snapshot.lastMarkCallReturn == nil)
            } catch {
                Issue.record("예상과 다른 error")
            }
        }
        #expect(trace.snapshot.frame == nil)
    }

    @Test("Session mutating 질의 중 snapshot 은 cache 만 읽고 재진입을 관찰한다")
    func queryReadsCacheWithoutSessionAccess() {
        let trace = ClientTrace()
        let driver = SessionDriver(hanja: dictionary)
        var observed: ClientTrace.Snapshot?
        _ = trace.withEvent {
            driver.perform({ session in
                session.handle(optionReturn, mode: .korean, selectedText: {
                    trace.withCall(.query) {
                        observed = trace.snapshot
                        driver.deactivate(apply: { _ in })
                        driver.activate()
                        #expect(trace.snapshot == observed)
                        return "한자"
                    }
                })
            }, apply: { outcome in
                let state = ClientTrace.State(
                    composing: !driver.composing.isEmpty, candidates: driver.hasCandidates
                )
                _ = trace.plan(outcome.actions, state: state)
            })
        }
        #expect(observed?.cachedState == ClientTrace.State(composing: false, candidates: false))
        #expect(observed?.frame?.kind == .query)
        #expect(trace.snapshot.cachedState == ClientTrace.State(composing: false, candidates: true))
        #expect(driver.hasCandidates)
    }

    @Test("같은 내용·빈 mark·markCommitted 도 각각 새 token 을 받는다")
    func identicalContentHasDistinctTokens() throws {
        let trace = ClientTrace()
        let actions: [Action] = [
            .mark("ㄱ"), .insert("ㄱ"), .mark("ㄱ"), .mark(""),
            .markCommitted("ㄱ", range: NSRange(location: 901, length: 1)),
        ]
        let batch = trace.plan(actions, state: composing)
        let calls = try [0, 2, 3, 4].map { try #require(batch.call(at: $0)) }
        let tokens = try calls.map { try #require($0.markPlan) }
        #expect(Set(tokens).count == 4)
        #expect(tokens == tokens.sorted())
        #expect(trace.snapshot.localMarkPlan == tokens.last)
        for call in calls {
            trace.withCall(call) {}
        }
        #expect(trace.snapshot.lastMarkCallReturn == tokens.last)
    }

    @Test("계획은 모든 mark 를 첫 호출 전에 처리하고 후보 UI index 를 유지한다")
    func wholeBatchIsPlannedBeforeCalls() throws {
        let trace = ClientTrace()
        let batch = trace.plan([.hideCandidates, .mark("한"), .insert("한"), .mark("ㄱ")], state: composing)
        let first = try #require(batch.call(at: 1))
        let last = try #require(batch.call(at: 3))
        #expect(batch.call(at: 0) == nil)
        #expect(batch.call(at: -1) == nil)
        #expect(batch.call(at: 4) == nil)
        #expect(trace.snapshot.localMarkPlan == last.markPlan)
        trace.withCall(first) {
            #expect(trace.snapshot.localMarkPlan == last.markPlan)
            #expect(trace.snapshot.lastMarkCallAttempt == first.markPlan)
        }
    }

    @Test("snapshot·description 에 action payload 나 문서 위치를 넣지 않는다")
    func snapshotExcludesContents() throws {
        let trace = ClientTrace()
        let secret = "PRIVATE_TEST_SENTINEL_한글"
        let batch = trace.plan([
            .insert(secret), .mark(secret),
            .markCommitted(secret, range: NSRange(location: 987654321, length: 456789)),
            .layout(secret),
        ], state: composing)
        for index in 0..<4 {
            let call = try #require(batch.call(at: index))
            trace.withCall(call) {
                let description = trace.snapshot.description
                #expect(!description.contains(secret))
                #expect(!description.contains("987654321"))
                #expect(!description.contains("456789"))
                #expect(!description.contains("keyCode"))
                #expect(!description.contains("range"))
            }
        }
        trace.updateState(ClientTrace.State(composing: false, candidates: false))
        #expect(!trace.snapshot.cachedState.composing)
        #expect(trace.snapshot.localMarkPlan == trace.snapshot.lastMarkCallReturn)
    }
}
