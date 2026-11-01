import AppKit
import InputSession

nonisolated struct ModePresentationContext: Equatable, Sendable {
    let app: String
    let mode: Mode
    let passThrough: Bool
}

/// 말풍선 요청의 순서만 관리한다. 위치 조회와 mode 변경은 호출자가 동기 event 안에서 끝낸다.
nonisolated final class ModePresentation {
    typealias Work = @MainActor @Sendable () -> Void
    private weak var owner: (any CandidateOwner)?
    private var revision: UInt64 = 0
    private let isActive: @MainActor @Sendable (any CandidateOwner) -> Bool
    private let context: @MainActor @Sendable (any CandidateOwner) -> ModePresentationContext?
    private let display: @MainActor @Sendable (String, NSRect) -> Void
    private let enqueue: (@escaping Work) -> Void

    init(owner: any CandidateOwner,
         context: @escaping @MainActor @Sendable (any CandidateOwner) -> ModePresentationContext?,
         isActive: @escaping @MainActor @Sendable (any CandidateOwner) -> Bool = { ActiveInputSession.controller === $0 },
         display: @escaping @MainActor @Sendable (String, NSRect) -> Void = { ModeHUD.shared.show($0, below: $1) },
         enqueue: @escaping (@escaping Work) -> Void = { work in Task { @MainActor in work() } }) {
        self.owner = owner
        self.context = context
        self.isActive = isActive
        self.display = display
        self.enqueue = enqueue
    }

    /// caret 질의 전에 호출한다. 질의 도중 재진입한 더 새 요청이 우선한다.
    private func begin() -> UInt64 { revision &+= 1; return revision }
    func invalidate() { revision &+= 1 }

    func request(_ text: String, expected: ModePresentationContext?, caret: () -> NSRect) {
        let requestRevision = begin()
        let line = caret()
        guard let expected else { return }
        show(text, below: line, revision: requestRevision, expected: expected)
    }

    private func show(_ text: String, below line: NSRect, revision: UInt64, expected: ModePresentationContext) {
        let presentation = Unchecked(self)
        whenIdle { owner in
            let current = presentation.value
            guard current.revision == revision, current.isActive(owner), current.context(owner) == expected else { return }
            current.display(text, line)
        }
    }

    private func whenIdle(_ update: @escaping @MainActor @Sendable (any CandidateOwner) -> Void) {
        guard let owner else { return }
        let presentation = Unchecked(self)
        owner.afterEvent {
            presentation.value.enqueue {
                let current = presentation.value
                guard let owner = current.owner else { return }
                if owner.isHandlingEvent { current.whenIdle(update) }
                else { update(owner) }
            }
        }
    }
}
