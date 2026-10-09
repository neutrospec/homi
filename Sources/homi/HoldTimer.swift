import Dispatch

/// Caps Lock hold 의 지연 작업. owner 가 없어지면 실행할 일도 없다.
/// main thread 에서만 쓴다 — Dispatch 의 Sendable 표시에 필요한 격리다.
nonisolated final class HoldTimer<Owner: AnyObject>: @unchecked Sendable {
    private weak var owner: Owner?
    private var work: DispatchWorkItem?

    init(owner: Owner) { self.owner = owner }

    func schedule(after delay: Double, action: @escaping @Sendable (Owner) -> Void) {
        cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, let owner = self.owner else { return }
            self.work = nil
            action(owner)
        }
        work = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    func cancel() {
        work?.cancel()
        work = nil
    }

    deinit { work?.cancel() }
}
