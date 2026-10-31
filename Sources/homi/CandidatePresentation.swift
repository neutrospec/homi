import AppKit
import HangulCore

/// 지연된 후보 표시가 읽는 controller 상태. client 질의나 입력 상태 변경은 이 경계에 없다.
nonisolated protocol CandidateOwner: AnyObject {
    var candidateRevision: UInt64 { get }
    var hasCandidates: Bool { get }
    var isHandlingEvent: Bool { get }
    func afterEvent(_ presentation: @escaping () -> Void)
}

protocol CandidateDisplaying: AnyObject {
    func show(_ candidates: [Candidate], selected: Int, below line: NSRect, owner: any CandidateOwner)
    func hide(owner: any CandidateOwner)
}

/// 후보 표시의 실행 순서만 분리한다. 위치는 Client 가 동기 event 안에서 구해 넘긴다.
nonisolated struct CandidatePresentation {
    typealias Work = @MainActor @Sendable () -> Void
    private weak var owner: (any CandidateOwner)?
    private let panel: @MainActor @Sendable () -> any CandidateDisplaying
    private let isActive: @MainActor @Sendable (any CandidateOwner) -> Bool
    private let enqueue: (@escaping Work) -> Void

    init(owner: any CandidateOwner,
         panel: @escaping @MainActor @Sendable () -> any CandidateDisplaying = { CandidatePanel.shared },
         isActive: @escaping @MainActor @Sendable (any CandidateOwner) -> Bool = { ActiveInputSession.controller === $0 },
         enqueue: @escaping (@escaping Work) -> Void = { work in Task { @MainActor in work() } }) {
        self.owner = owner
        self.panel = panel
        self.isActive = isActive
        self.enqueue = enqueue
    }

    func show(_ candidates: [Candidate], selected: Int, below line: NSRect) {
        guard let owner else { return }
        let controller = Unchecked(owner)
        let revision = owner.candidateRevision
        let panel = panel, isActive = isActive, enqueue = enqueue
        owner.afterEvent {
            enqueue {
                let owner = controller.value
                guard !owner.isHandlingEvent, owner.candidateRevision == revision,
                    owner.hasCandidates, isActive(owner) else { return }
                panel().show(candidates, selected: selected, below: line, owner: owner)
            }
        }
    }

    func hide() {
        guard let owner else { return }
        let controller = Unchecked(owner)
        let revision = owner.candidateRevision
        let panel = panel, enqueue = enqueue
        owner.afterEvent {
            enqueue {
                let owner = controller.value
                guard !owner.isHandlingEvent, owner.candidateRevision == revision, !owner.hasCandidates else { return }
                panel().hide(owner: owner)
            }
        }
    }
}
