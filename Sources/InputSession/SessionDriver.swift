import HangulCore

/// controller 하나의 Session 과 client 반영을 함께 맡는다. client 호출 중의 lifecycle 도 여기로 들어온다.
/// 한 thread 의 동기 경계다 — lock·timer·비동기 재시도를 쓰지 않는다.
public final class SessionDriver {
    private var session: Session
    private var depth = 0
    private var pendingDeactivation: (([Action]) -> Void)?
    private var pendingCommit: (insert: Bool, apply: ([Action]) -> Void)?
    private var presentations: [() -> Void] = []
    private var finishing = false
    private var mutationDepth = 0
    /// 관측 전용 cache. callback 은 Session 대신 이것의 primitive snapshot 을 읽는다.
    public let clientTrace = ClientTrace()
    /// 지연된 UI 가 이미 끝난 조합을 다시 보이지 않게 하는 세대.
    public private(set) var revision: UInt64 = 0

    public init(hanja: HanjaDictionary? = nil) { session = Session(hanja: hanja) }
    public var composing: String { session.composing }
    public var hasCandidates: Bool { session.hasCandidates }
    public var isHandlingEvent: Bool { depth > 0 }
    /// 명시적인 commit 은 activate 가 취소하지 않는다. 종료 flush 도 실제 입력 event 의 continuation 과 구분한다.
    public var hasExplicitEnd: Bool { pendingCommit != nil || finishing }
    public var isMutatingSession: Bool { mutationDepth > 0 }

    @discardableResult
    public func perform<Result>(_ operation: (inout Session) -> Result, apply: (Result) -> Void) -> Result {
        withEvent {
            mutationDepth += 1
            let result = operation(&session)
            mutationDepth -= 1
            updateTraceState()
            apply(result)
            return result
        }
    }

    /// app 판별·수식키·caret 질의도 같은 경계 안에 둔다.
    public func withEvent<Result>(_ body: () -> Result) -> Result {
        clientTrace.withEvent {
            if depth == 0 { revision &+= 1 }
            depth += 1
            defer {
                depth -= 1
                if depth == 0 {
                    // flush 의 client 호출도 재진입할 수 있다. 그 callback 역시 다음 flush 로 모은다.
                    depth = 1
                    drain()
                    depth = 0
                    let ready = presentations
                    presentations = []
                    ready.forEach { $0() }
                }
            }
            return body()
        }
    }

    /// 한 event 안에서 명시적 commit 없이 같은 controller 가 재활성화되면 조합을 이어 간다.
    /// 실제 blur 에서 온 commitComposition 은 별개라 취소하지 않는다.
    public func activate() { pendingDeactivation = nil }

    /// UI 의 Task 도 질의·flush 가 모두 끝난 뒤에 만든다. client IPC 의 nested run loop 를 피한다.
    public func afterEvent(_ presentation: @escaping () -> Void) {
        if depth > 0 { presentations.append(presentation) }
        else { presentation() }
    }

    /// deactivate 가 빠지는 외부 process 의 source 전환도 명시적인 종료다.
    public func sourceChanged(selected: Bool, apply: @escaping ([Action]) -> Void) {
        if !selected { commit(apply: apply) }
    }

    /// client 가 이미 확정한 글자는 다시 넣지 않는다. 외부 callback 은 반환 전에 Session 을 끝낸다.
    /// 처리 도중의 callback 만 같은 event 의 반영 끝까지 보류한다 — 다음 key·입력칸으로 넘기지 않는다.
    public func clientConfirmed(apply: @escaping ([Action]) -> Void) {
        commit(insert: false, apply: apply)
    }

    public func deactivate(apply: @escaping ([Action]) -> Void) {
        if depth > 0 { pendingDeactivation = apply }
        else { commit(apply: apply) }
    }

    public func commit(insert: Bool = true, apply: @escaping ([Action]) -> Void) {
        if depth > 0 {
            // 이미 client 가 확정한 조합은 뒤의 deactivate 가 다시 넣어서는 안 된다.
            let shouldInsert = insert && (pendingCommit?.insert ?? true)
            pendingCommit = (shouldInsert, apply)
        } else {
            withEvent { finish(insert: insert, apply: apply) }
        }
    }

    private func drain() {
        while pendingCommit != nil || pendingDeactivation != nil {
            let request = pendingCommit ?? pendingDeactivation.map { (insert: true, apply: $0) }!
            pendingCommit = nil
            pendingDeactivation = nil
            finish(insert: request.insert, apply: request.apply)
        }
    }

    private func finish(insert: Bool, apply: ([Action]) -> Void) {
        finishing = true
        defer { finishing = false }
        revision &+= 1
        mutationDepth += 1
        let committed = session.commit()
        mutationDepth -= 1
        updateTraceState()
        let actions = committed.filter {
            if case .insert = $0 { return insert }
            return true
        }
        if !actions.isEmpty { apply(actions) }
    }

    private func updateTraceState() {
        clientTrace.updateState(.init(composing: !session.composing.isEmpty, candidates: session.hasCandidates))
    }
}
