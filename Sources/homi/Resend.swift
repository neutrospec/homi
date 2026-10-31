import AppKit
import InputSession
import Synchronization

/// 원래 key 의 목적지. main queue 를 기다리는 사이 frontmost app 이 바뀌어도 다시 고르지 않는다.
nonisolated struct ResendTarget {
    let pid: pid_t
    let bundleID: String
    let isRunning: @MainActor @Sendable () -> Bool

    @MainActor static func current() -> ResendTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication, let bundleID = app.bundleIdentifier else { return nil }
        return ResendTarget(pid: app.processIdentifier, bundleID: bundleID, isRunning: { !app.isTerminated })
    }
}

/// 먹기로 한 key 의 down/up 을 미리 준비하고, client 반영이 끝난 뒤 원래 app 에 한 번 보낸다.
/// OS queue 에 이미 들어간 다음 key 와의 순서·같은 app 안의 입력칸까지 보장하는 경계는 아니다.
nonisolated final class Resend {
    typealias Work = @MainActor @Sendable () -> Void
    private static let requested = Mutex(false)
    private let target: ResendTarget
    private let down: CGEvent
    private let up: CGEvent
    private let post: @MainActor @Sendable (CGEvent, pid_t) -> Void
    private var scheduled = false

    private init(target: ResendTarget, down: CGEvent, up: CGEvent,
                 post: @escaping @MainActor @Sendable (CGEvent, pid_t) -> Void) {
        self.target = target
        self.down = down
        self.up = up
        self.post = post
    }

    /// 준비 실패는 원래 key 를 넘기는 경로로 돌린다. down 만 보낸 뒤 up 생성이 실패하지 않게 한다.
    static func prepare(_ event: NSEvent, app: ClientAppID?,
        target: @MainActor () -> ResendTarget? = ResendTarget.current,
        allowed: () -> Bool = Resend.allowed,
        make: (CGKeyCode, Bool) -> CGEvent? = { code, down in
            CGEvent(keyboardEventSource: CGEventSource(stateID: .hidSystemState), virtualKey: code, keyDown: down)
        },
        post: @escaping @MainActor @Sendable (CGEvent, pid_t) -> Void = { $0.postToPid($1) }) -> Resend? {
        guard let app, let target = MainActor.assumeIsolated({ target() }),
              target.pid > 0, target.bundleID == app.bundleID, allowed(),
              let down = make(CGKeyCode(event.keyCode), true),
              let up = make(CGKeyCode(event.keyCode), false) else { return nil }
        let flags = event.cgEvent?.flags ?? CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
        down.flags = flags
        up.flags = flags
        log.debug("resend prepared for \(target.bundleID, privacy: .public), pid: \(target.pid)")
        return Resend(target: target, down: down, up: up, post: post)
    }

    /// 원래 event 의 client IPC 가 nested run loop 를 돌려도 그 도중에는 작업을 예약하지 않는다.
    func send(afterEvent: (@escaping () -> Void) -> Void,
              enqueue: @escaping (@escaping Work) -> Void = { work in DispatchQueue.main.async(execute: work) }) {
        guard !scheduled else { return }
        scheduled = true
        let prepared = Unchecked(self)
        afterEvent {
            enqueue {
                let request = prepared.value
                guard request.target.isRunning() else {
                    log.info("resend target exited before delivery")
                    return
                }
                request.post(request.down, request.target.pid)
                request.post(request.up, request.target.pid)
                log.debug("resend posted to pid: \(request.target.pid)")
                record("  resent to pid=\(request.target.pid)")
            }
        }
    }

    /// 허가가 없으면 한 번만 요청한다. 기존 설치본과 같은 손쉬운 사용 권한이다.
    static func allowed() -> Bool {
        if CGPreflightPostEventAccess() { return true }
        let first = requested.withLock { asked in
            defer { asked = true }
            return !asked
        }
        if first {
            log.info("requesting post-event access")
            _ = CGRequestPostEventAccess()
        }
        return false
    }
}
