/// client IPC 의 계획·호출 순서만 관찰한다. 한 thread 에서 동기적으로 쓰며 Session 을 소유하거나 읽지 않는다.
/// snapshot 에는 입력 내용·key·문서 위치가 없다. token 은 호출의 식별자이지 client 가 적용한 글자의 증거가 아니다.
public final class ClientTrace {
    /// Session 을 안전하게 읽을 수 있는 경계에서 caller 가 옮긴 값. 재진입 callback 안에서는 갱신하지 않는다.
    public struct State: Sendable, Equatable {
        public let composing: Bool
        public let candidates: Bool

        public init(composing: Bool, candidates: Bool) {
            self.composing = composing
            self.candidates = candidates
        }
    }

    public enum CallKind: String, Sendable {
        case insert
        case mark
        case query
        case layout
    }

    /// Action 의 case 만 옮긴다. payload 나 원래 Action 목록은 보관하지 않는다.
    public struct PlannedCall: Sendable, Equatable {
        public let kind: CallKind
        public let batchID: UInt64?
        public let actionIndex: Int?
        public let markPlan: UInt64?
    }

    public struct Batch: Sendable {
        public let id: UInt64
        private let calls: [PlannedCall?]

        fileprivate init(id: UInt64, calls: [PlannedCall?]) {
            self.id = id
            self.calls = calls
        }

        /// 원래 Action 목록의 index. 후보 UI action 은 client 호출이 아니라 nil 이다.
        public func call(at index: Int) -> PlannedCall? {
            guard calls.indices.contains(index) else { return nil }
            return calls[index]
        }
    }

    public struct Frame: Sendable, Equatable {
        public let id: UInt64
        public let kind: CallKind
        public let eventID: UInt64?
        public let batchID: UInt64?
        public let actionIndex: Int?
        public let markPlan: UInt64?
        public let depth: Int
    }

    /// lifecycle callback 은 이 값만 읽는다. Session 의 mutating 질의 중에도 exclusive access 와 겹치지 않는다.
    public struct Snapshot: Sendable, Equatable, CustomStringConvertible {
        public let cachedState: State
        public let eventID: UInt64?
        public let batchID: UInt64?
        /// 가장 최근에 계획한 mark 호출. 조합 종료 뒤에도 호출 이력으로 남는다.
        public let localMarkPlan: UInt64?
        public let lastMarkCallAttempt: UInt64?
        /// proxy 호출이 정상 반환한 이력. renderer 의 적용·확정을 보장하지 않는다.
        public let lastMarkCallReturn: UInt64?
        public let frame: Frame?

        public var description: String {
            func token(_ value: UInt64?) -> String { value.map(String.init) ?? "none" }
            let call: String
            if let frame {
                let action = frame.actionIndex.map(String.init) ?? "none"
                call = "id=\(frame.id),kind=\(frame.kind.rawValue),event=\(token(frame.eventID)),batch=\(token(frame.batchID)),action=\(action),markPlan=\(token(frame.markPlan)),depth=\(frame.depth)"
            } else {
                call = "none"
            }
            return "cachedState(composing=\(cachedState.composing),candidates=\(cachedState.candidates)) event=\(token(eventID)) batch=\(token(batchID)) localMarkPlan=\(token(localMarkPlan)) markAttempt=\(token(lastMarkCallAttempt)) markReturn=\(token(lastMarkCallReturn)) call(\(call))"
        }
    }

    private var cachedState: State
    private var currentEventID: UInt64?
    private var currentBatchID: UInt64?
    private var localMarkPlan: UInt64?
    private var lastMarkCallAttempt: UInt64?
    private var lastMarkCallReturn: UInt64?
    private var frames: [Frame] = []
    private var nextEventID: UInt64 = 0
    private var nextBatchID: UInt64 = 0
    private var nextMarkPlan: UInt64 = 0
    private var nextCallID: UInt64 = 0

    public init(state: State = State(composing: false, candidates: false)) {
        cachedState = state
    }

    public var snapshot: Snapshot {
        Snapshot(
            cachedState: cachedState, eventID: currentEventID,
            batchID: currentBatchID ?? frames.last?.batchID,
            localMarkPlan: localMarkPlan, lastMarkCallAttempt: lastMarkCallAttempt,
            lastMarkCallReturn: lastMarkCallReturn, frame: frames.last
        )
    }

    public func updateState(_ state: State) { cachedState = state }

    /// Session operation 이 돌아온 뒤, 첫 client IPC 전에 목록 전체를 계획한다.
    /// insert(old) → mark(next) 의 insert callback 에서도 next 의 token 을 볼 수 있다.
    public func plan(_ actions: [Action], state: State) -> Batch {
        updateState(state)
        nextBatchID &+= 1
        let id = nextBatchID
        let calls = actions.enumerated().map { index, action -> PlannedCall? in
            let kind: CallKind
            switch action {
            case .insert: kind = .insert
            case .mark, .markCommitted: kind = .mark
            case .layout: kind = .layout
            case .showCandidates, .hideCandidates: return nil
            }
            let markPlan = kind == .mark ? allocateMarkPlan() : nil
            return PlannedCall(kind: kind, batchID: id, actionIndex: index, markPlan: markPlan)
        }
        return Batch(id: id, calls: calls)
    }

    /// 중첩된 처리도 같은 event 에 속한다. scope 밖의 lifecycle 에는 event ID 가 없다.
    public func withEvent<Result>(_ body: () throws -> Result) rethrows -> Result {
        let previous = currentEventID
        if currentEventID == nil {
            nextEventID &+= 1
            currentEventID = nextEventID
        }
        defer { currentEventID = previous }
        return try body()
    }

    public func withBatch<Result>(_ batch: Batch, _ body: () throws -> Result) rethrows -> Result {
        let previous = currentBatchID
        currentBatchID = batch.id
        defer { currentBatchID = previous }
        return try body()
    }

    /// client 호출 직전에 frame 을 올리고, 정상 반환 또는 throw 뒤에 이전 frame 을 복구한다.
    public func withCall<Result>(_ call: PlannedCall, _ body: () throws -> Result) rethrows -> Result {
        nextCallID &+= 1
        let frame = Frame(
            id: nextCallID, kind: call.kind, eventID: currentEventID,
            batchID: call.batchID ?? currentBatchID ?? frames.last?.batchID,
            actionIndex: call.actionIndex, markPlan: call.markPlan, depth: frames.count + 1
        )
        frames.append(frame)
        if let markPlan = call.markPlan { lastMarkCallAttempt = markPlan }
        defer { frames.removeLast() }
        let result = try body()
        if let markPlan = call.markPlan { lastMarkCallReturn = markPlan }
        return result
    }

    /// Action 목록 밖의 질의·layout 호출도 같은 frame stack 으로 관찰한다.
    public func withCall<Result>(_ kind: CallKind, _ body: () throws -> Result) rethrows -> Result {
        let call = PlannedCall(
            kind: kind, batchID: nil, actionIndex: nil,
            markPlan: kind == .mark ? allocateMarkPlan() : nil
        )
        return try withCall(call, body)
    }

    private func allocateMarkPlan() -> UInt64 {
        nextMarkPlan &+= 1
        localMarkPlan = nextMarkPlan
        return nextMarkPlan
    }
}
