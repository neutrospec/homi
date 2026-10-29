import AppKit
import ApplicationServices
import CoreGraphics
import IOKit.hidsystem
import InputSession
import Synchronization

/// keyCode 는 어느 수식키가 바뀌었는지, 좌우 bit 는 그 key 를 눌렀는지 뗐는지를 알려 준다.
nonisolated struct ModifierPosition {
    let isDown: Bool
    let oppositeSideDown: Bool

    init(keyCode: UInt16, flags: UInt64) {
        let bits: (CGEventFlags, Int32, Int32)
        switch keyCode {
        case 54: bits = (.maskCommand, NX_DEVICERCMDKEYMASK, NX_DEVICELCMDKEYMASK)
        case 61: bits = (.maskAlternate, NX_DEVICERALTKEYMASK, NX_DEVICELALTKEYMASK)
        case 62: bits = (.maskControl, NX_DEVICERCTLKEYMASK, NX_DEVICELCTLKEYMASK)
        default:
            isDown = false
            oppositeSideDown = false
            return
        }
        let right = UInt64(bits.1), left = UInt64(bits.2)
        oppositeSideDown = flags & left != 0
        // 좌우 bit 를 주지 않는 event 는 반대쪽 누름의 증거가 없을 때만 기존 aggregate flag 를 쓴다.
        isDown = flags & right != 0 || (flags & (right | left) == 0 && flags & bits.0.rawValue != 0)
    }
}

/// activity 의 획득만 event tap 에서 한다. mode·조합·client 는 계속 IMK event 안에서 처리한다.
/// 별도 thread 에서 원본을 즉시 돌려준다. callback 에 client 호출·출력·file I/O·lock 대기가 없다.
nonisolated final class ModifierActivityObserver: @unchecked Sendable {
    static let shared = ModifierActivityObserver()

    private let store = ModifierActivityStore()
    private let started = Atomic<Bool>(false)
    // 이 값들은 callback thread 에서만 다룬다. IMK 는 atomic store 만 읽는다.
    private var timeline = ModifierActivityTimeline()
    private var next = 0
    private var tap: CFMachPort?
    private var appliedContext: UInt64 = 0
    @MainActor private var contextApp: String?
    @MainActor private var claimed: [UInt16: (epoch: UInt64, gesture: UInt64)] = [:]

    func start() {
        guard !started.exchange(true, ordering: .acquiringAndReleasing) else { return }
        let thread = Thread { [self] in run() }
        thread.name = "homi.modifier-activity"
        thread.start()
    }

    /// source·app 변경 때 옛 기록을 즉시 읽지 못하게 한다. callback 은 다음 event 앞에서 새 세대를 시작한다.
    @MainActor func setContext(app: String?, force: Bool = false) {
        guard force || contextApp != app else { return }
        contextApp = app
        claimed.removeAll(keepingCapacity: true)
        let generation = store.contextGeneration.load(ordering: .sequentiallyConsistent)
        store.contextGeneration.store(generation &+ 1, ordering: .sequentiallyConsistent)
    }

    /// 유일하게 남아 있는 physical press 만 한 controller 에 준다. 모호한 backlog 는 기존 판정으로 넘긴다.
    func claim(keyCode: UInt16, app: String) -> ModifierCapture? {
        MainActor.assumeIsolated {
            guard store.available.load(ordering: .acquiring), contextApp == app else { return nil }
            let pending = store.pending(keyCode: keyCode, after: claimed[keyCode])
            if let latest = pending.latest { claimed[keyCode] = latest }
            return pending.capture
        }
    }

    func release(for press: ModifierCapture, app: String) -> ModifierCapture? {
        MainActor.assumeIsolated {
            guard store.available.load(ordering: .acquiring), contextApp == app else { return nil }
            return store.release(for: press)
        }
    }

    func hold(for pressTime: Double?, captured: Bool) -> (pressedAt: Double?, activity: ModifierActivity) {
        if captured {
            // IMK release 가 늦어도 관찰한 release 가 있으면 store 가 이미 누름을 끝냈다.
            // remap 된 modifier 의 keyState 조회를 관찰한 flagsChanged 와 같은 증거로 가정하지 않는다.
            let evidence = store.hold()
            let reportedDown = CGEventSource.keyState(.hidSystemState, key: 62)
            log.info("modifier hold evidence: observed down=\(evidence.pressedAt != nil), queried right control down=\(reportedDown)")
            return evidence
        }
        return (pressTime, LegacyActivity.now())
    }

    private func run() {
        // 권한은 요청하지 않는다. 허가가 없는 환경에서는 기존 counter 판정을 유지한다.
        guard AXIsProcessTrusted() else {
            log.info("modifier observation unavailable: accessibility access not granted; using legacy counters")
            return
        }
        let types: [CGEventType] = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let context = Unmanaged.passUnretained(self).toOpaque()
        // active tap 이 반환한 뒤 app 에 전달되므로 IMK 는 대응하는 snapshot 을 동기적으로 읽는다.
        // 원본 event 를 그대로 돌려준다.
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let observer = Unmanaged<ModifierActivityObserver>.fromOpaque(context).takeUnretainedValue()
                observer.receive(type, event)
                return Unmanaged.passUnretained(event)
            }, userInfo: context) else {
            log.error("modifier observation unavailable: cannot create event tap; using legacy counters")
            return
        }
        guard Self.hasRequestedEvents(mask),
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port)
            log.error("modifier observation unavailable: incomplete event mask; using legacy counters")
            return
        }
        tap = port
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
        invalidate()
        store.available.store(true, ordering: .releasing)
        log.info("modifier observation ready: gesture binding, dedicated thread, unmodified events")
        CFRunLoopRun()
        store.available.store(false, ordering: .releasing)
        invalidate()
        CFMachPortInvalidate(port)
        tap = nil
    }

    private func receive(_ type: CGEventType, _ event: CGEvent) {
        let requestedContext = store.contextGeneration.load(ordering: .sequentiallyConsistent)
        if requestedContext != appliedContext {
            appliedContext = requestedContext
            invalidate()
        }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            invalidate()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        if type == .flagsChanged {
            let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
            let position = ModifierPosition(keyCode: keyCode, flags: event.flags.rawValue)
            let time = Double(event.timestamp) / 1_000_000_000
            timeline.modifier(keyCode: keyCode, time: time, isDown: position.isDown)
            if let capture = timeline.lastCapture, case .events(let epoch, let serial) = capture.activity {
                store.publish(.init(keyCode: keyCode, time: time, isDown: position.isDown,
                    epoch: epoch, serial: serial, gesture: capture.gesture), index: next)
                next = (next + 1) % 256
            }
        } else {
            // 일반 key code·Unicode 를 읽지 않는다. event 종류는 mask 로 제한했다.
            timeline.input()
        }
        if case .events(let epoch, let serial) = timeline.currentActivity {
            store.publishHold(.init(keyCode: 62, time: timeline.capsPressTime ?? 0, isDown: timeline.capsPressTime != nil,
                epoch: epoch, serial: serial))
        }
    }

    private func invalidate() {
        timeline.invalidate()
        if case .events(let epoch, _) = timeline.currentActivity { store.invalidate(epoch: epoch, context: appliedContext) }
    }

    /// tap 생성 성공만으로 keyDown 관측까지 허용됐다고 보지 않는다 — Apple 은 허용하지 않은 mask bit 를 뺄 수 있다.
    private static func hasRequestedEvents(_ mask: CGEventMask) -> Bool {
        var count: UInt32 = 0
        guard CGGetEventTapList(0, nil, &count) == .success, count > 0 else { return false }
        var list = Array(repeating: CGEventTapInformation(), count: Int(count))
        guard CGGetEventTapList(count, &list, &count) == .success else { return false }
        return list.prefix(Int(count)).contains {
            $0.tappingProcess == getpid() && $0.tapPoint == .cgSessionEventTap
                && $0.options == .defaultTap && $0.eventsOfInterest & mask == mask
        }
    }
}
