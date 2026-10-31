import AppKit
import InputMethodKit
import InputSession
import Synchronization

/// IMK 가 입력칸(client) session 마다 하나씩 만드는 controller. 입력 순서는 `InputCoordinator`,
/// 입력의 판단은 `Session`·`ModifierKeys`·`AppRules` 가 맡는다 (AGENTS.md 결정 7).
///
/// 한/영 모드는 app 별 기억(`memory`)에 있고, key 마다 이 입력칸의 app 으로 읽는다 —
/// activate 알림이 늦거나 빠져도 틀리지 않는다.
/// IMK header 에는 actor 표시가 없어 override 들이 nonisolated 여야 한다. 불리는 곳은 main thread 다.
@objc(HomiInputController)
nonisolated final class HomiInputController: IMKInputController {
    // Session·사전은 기존처럼 controller 생성 때 준비한다. lazy coordinator 의 첫 key 로 사전 I/O 를 옮기지 않는다.
    private let session = SessionDriver(hanja: hanjaDictionary)
    private lazy var coordinator = InputCoordinator(driver: session, modes: StoredModes(),
        profile: { AppRules.profile(for: $0, preferences: preferences.withLock { $0 }) },
        fallbackApp: { MainActor.assumeIsolated { NSWorkspace.shared.frontmostApplication?.bundleIdentifier } ?? "unknown" },
        notice: { [weak self] in self?.inputNotice($0) })
    private var app: String? { coordinator.clientApp?.bundleID }
    private var modifierKeys = ModifierKeys()
    private var modifierBinding = ModifierEventBinding()
    private lazy var capsLockHold = HoldTimer(owner: self)
    private var receivedEvent = false
    /// process 와 생성 순서를 식별한다. 객체 해제 뒤 주소가 재사용돼도 ID 는 재사용하지 않는다.
    let traceID = ControllerTraceID.make()

    /// flagsChanged 는 수식키 tap(오른쪽 ⌘·⌥, Caps Lock)을 보려고 받는다. 그러면 IMK 의 기본 mouse 처리
    /// (조합 영역 밖을 click 하면 commitComposition) 가 꺼지므로 leftMouseDown 도 받아 직접 확정한다 — IMKInputController.h.
    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask([.keyDown, .flagsChanged, .leftMouseDown]).rawValue)
    }

    override func activateServer(_ sender: Any!) {
        observeClient("activate.begin", lifecycle: true)
        defer { observeClient("activate.return", lifecycle: true) }
        let activation = coordinator.activate()
        let (app, mode, layout) = (activation.app.bundleID, activation.mode, activation.layout)
        // homi 가 넘긴 key 는 이 layout 으로 문자가 된다 — 늘 ABC, 원격 화면의 한글 모드만 두벌식 (`AppProfile.keyboardLayout`).
        // 새 시작의 layout 은 activate 에서만 준비한다. 같은 event 의 재활성화는 기존 layout 도 이어 간다.
        if !activation.resuming, let proxy = sender as? any IMKTextInput & NSObjectProtocol {
            Client(proxy: proxy, owner: self).apply([.layout(layout)])
        }
        log.info("activate \(app, privacy: .public), controller: \(self.traceID, privacy: .public)")
        record("activate \(app) \(activation.passThrough ? "pass-through" : "\(mode)") \(activation.resuming ? "layout preserved" : layout)")
        showIndicator(mode, app: app, passThrough: activation.passThrough)
    }

    override func deactivateServer(_ sender: Any!) {
        observeClient("deactivate.begin", lifecycle: true)
        defer { observeClient("deactivate.return", lifecycle: true) }
        let id = app ?? "unknown"
        log.info("deactivate \(id, privacy: .public), controller: \(self.traceID, privacy: .public)")
        record("deactivate \(id)")
        cancelModifiers(endingGesture: true)
        let target = client().map { Client(proxy: $0, owner: self) }
        session.deactivate { target?.apply($0) }
    }

    /// client 가 조합을 끝내 달라고 할 때 — focus 이동, input source 전환.
    override func commitComposition(_ sender: Any!) {
        observeClient("commitComposition.begin", lifecycle: true)
        defer { observeClient("commitComposition.return", lifecycle: true) }
        record("commitComposition \(app ?? "unknown")")
        // 기존 Chromium 우회로 복귀한다. TIS 는 source 전환 중 아직 homi 일 수 있어 이 구분은 불완전하다.
        // callback 뒤의 mark 질의로 보완하려던 처리는 새 입력칸에 글자를 넣었다 — Chrome 원장.
        let sourceSelected = app.flatMap { app -> Bool? in
            MainActor.assumeIsolated { Chromium.hosts(app) ? SourceWatcher.homiSelected() : nil }
        }
        let selected = sourceSelected.map { $0 ? "yes" : "no" } ?? "not Chromium"
        let id = app ?? "unknown"
        let senderType = sender.map { String(describing: type(of: $0)) } ?? "nil"
        let busy = session.isHandlingEvent
        let controllerID = traceID
        log.info("commit requested from \(id, privacy: .public), controller: \(controllerID, privacy: .public), source selected: \(selected, privacy: .public), sender: \(senderType, privacy: .public), inside event: \(busy)")
        if sourceSelected == true {
            let target = client().map { Client(proxy: $0, owner: self) }
            session.end(.alreadyCommittedByClient) { target?.apply($0) }
        } else {
            commit()
        }
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, let proxy = sender as? any IMKTextInput & NSObjectProtocol else { return false }
        let client = Client(proxy: proxy, owner: self)
        switch event.type {
        case .keyDown:
            let key = KeyEvent(event)
            return coordinator.keyDown(key, client: client, before: {
                cancelModifiers()
                record("key \(key)")
            }, canResend: {
                let allowed = Resend.allowed()
                if !allowed { record("  resend not allowed — passed") }
                return allowed
            }, after: { outcome, modeChanged in
                if modeChanged { showMode(outcome.mode, near: client) }
                if outcome.resend {
                    record("  resend")
                    Resend.post(event)
                }
                record(outcome.handled ? "  handled" : "  passed")
            }).handled
        case .flagsChanged:
            coordinator.modifiersChanged(client: client, action: { app, profile in
                modifierAction(event, app: app, profile: profile)
            }, showMode: { showMode($0, near: client) }, capsLock: {
                // 표시는 macOS 에 맡긴다 — homi 가 따로 띄우면 겹친다 (주인, 2026-09-25).
                CapsLockState.toggle()
            })
            return false
        case .leftMouseDown:
            coordinator.mouseDown(client: client, before: {
                record("mouseDown")
                cancelModifiers(endingGesture: true)
            }, boundClient: { self.client().map { Client(proxy: $0, owner: self) } })
            return false
        default:
            coordinator.ignoredEvent(client: client)
            return false
        }
    }

    /// 수식키 관찰과 tap·hold 판정. 결과의 Session 처리는 coordinator 에 돌려준다.
    private func modifierAction(_ event: NSEvent, app: String, profile: AppProfile) -> ModifierKeys.Action? {
        guard !profile.passThrough else { cancelModifiers(endingGesture: true); return nil }
        let raw = ModifierEvent(event, activity: LegacyActivity.now())
        let observer = ModifierActivityObserver.shared
        let translated = modifierBinding.translate(raw,
            claim: { observer.claim(keyCode: raw.keyCode, app: app) },
            release: { observer.release(for: $0, app: app) })
        let result = modifierKeys.changed(translated, profile: profile)
        capsLockHold.cancel()
        if result.startsHoldTimer { scheduleCapsLockHold() }
        if [54, 61, 62].contains(event.keyCode) {
            let origin: String
            switch translated.activity {
            case .events: origin = "event"
            case .counter: origin = "legacy"
            case .missing: origin = "missing"
            }
            // 전환 수식키의 판정만 기록한다. 일반 입력 key code·문자는 포함하지 않는다.
            let phase = translated.isDown ? "press" : "release"
            let action = result.action.map { String(describing: $0) } ?? "none"
            log.info("modifier decision: \(phase, privacy: .public), evidence: \(origin, privacy: .public), action: \(action, privacy: .public), controller: \(self.traceID, privacy: .public)")
        }
        guard let action = result.action else { return nil }
        record("modifier kc=\(event.keyCode) → \(action)")
        return action
    }

    /// key 를 치거나 입력칸을 떠났다 — 누르고 있던 수식키는 tap 이 아니다.
    private func cancelModifiers(endingGesture: Bool = false) {
        modifierKeys.cancel()
        if endingGesture { modifierBinding.end() }
        else { modifierBinding.cancel() }
        capsLockHold.cancel()
    }

    /// Caps Lock 을 누르고 `holdAfter` 가 지나면, 아직 단독으로 누르고 있을 때 대문자 고정을 뒤집는다 — 떼기 전에 (macOS 처럼).
    private func scheduleCapsLockHold() {
        guard let pressTime = modifierKeys.capsLockPressTime else { return }
        let delay = max(0, pressTime + ModifierTap.holdAfter - ProcessInfo.processInfo.systemUptime)
        capsLockHold.schedule(after: delay) { $0.capsLockHeld() }
    }

    private func capsLockHeld() {
        let evidence = ModifierActivityObserver.shared.hold(for: modifierKeys.capsLockPressTime,
            captured: modifierBinding.usesCapturedCaps)
        guard modifierKeys.capsLockHeld(at: ProcessInfo.processInfo.systemUptime,
            pressedAt: evidence.pressedAt, activity: evidence.activity) == .capsLock else { return }
        record("caps lock hold")
        log.info("modifier hold: caps lock, controller: \(self.traceID, privacy: .public)")
        CapsLockState.toggle()
    }

    /// 커서 옆 말풍선. 커서 줄의 위치는 지금(key 처리 도중, app 이 homi 를 기다리는 동안) 묻고 — 그 밖에서 client 를 부르면
    /// app 과 교착할 수 있다 (조사: Chrome) — 그리는 일은 key 처리 뒤로 미룬다.
    private func showMode(_ mode: Mode, near client: Client) {
        let line = client.caretLine()
        let text = mode.glyph
        Task { @MainActor in ModeHUD.shared.show(text, below: line) }
    }

    /// coordinator 의 알림은 관찰·표시에만 쓴다. 입력 판단의 상태는 coordinator 와 shared memory 에 있다.
    private func inputNotice(_ notice: InputCoordinator.Notice) {
        switch notice {
        case .becameActive:
            let controller = Unchecked(self)
            MainActor.assumeIsolated { ActiveInputSession.controller = controller.value }
        case .received(let app):
            if !receivedEvent {
                receivedEvent = true
                log.info("receiving events from \(app, privacy: .public), controller: \(self.traceID, privacy: .public)")
            }
        case .appResolved(let app, let mode, let passThrough):
            showIndicator(mode, app: app, passThrough: passThrough)
        case .modePrepared(let app, let mode, let passThrough):
            log.info("input start prepared for \(app, privacy: .public), controller: \(self.traceID, privacy: .public), mode: \(String(describing: mode), privacy: .public)")
            record("input start \(app) \(mode)")
            showIndicator(mode, app: app, passThrough: passThrough)
        case .modeChanged(let app, let mode, let passThrough):
            log.info("mode \(String(describing: mode), privacy: .public) for \(app, privacy: .public)")
            record("mode \(mode)")
            showIndicator(mode, app: app, passThrough: passThrough)
        }
    }

    /// 옛 activation 표시가 뒤늦게 현재 mode 를 덮지 않는다. client 에게는 묻지 않는다.
    private func showIndicator(_ mode: Mode, app: String, passThrough: Bool) {
        let controller = Unchecked(self)
        session.afterEvent {
            Task { @MainActor in
                guard ActiveInputSession.controller === controller.value,
                    controller.value.app == nil || controller.value.app == app,
                    controller.value.profile(for: app).passThrough == passThrough,
                    memory.withLock({ $0.mode(for: app) }) == mode else { return }
                Indicator.shared.show(passThrough ? nil : mode)
            }
        }
    }

    /// 이 입력칸의 규칙 — 주인의 설정과 app 규칙 표를 합친다.
    private func profile(for app: String) -> AppProfile {
        AppRules.profile(for: app, preferences: preferences.withLock { $0 })
    }

    /// 조합 중인 글자를 이 controller 가 맡은 client 에 확정한다.
    /// deactivate·commitComposition 의 sender 는 이미 다른 client 일 수 있어 쓰지 않는다 (docs/research).
    private func commit() {
        let target = client().map { Client(proxy: $0, owner: self) }
        session.end(.commitToClient) { target?.apply($0) }
    }

    /// source 전환 알림은 deactivate 가 빠져도 온다. bound client 에만 확정하고, 반복은 무해하다.
    func sourceChanged(selected: Bool) {
        guard !selected else { return }
        observeClient("sourceEnd.begin", lifecycle: true)
        defer { observeClient("sourceEnd.return", lifecycle: true) }
        log.info("source end handled, controller: \(self.traceID, privacy: .public)")
        cancelModifiers(endingGesture: true)
        let target = client().map { Client(proxy: $0, owner: self) }
        session.sourceChanged(selected: selected) { target?.apply($0) }
    }

    override func inputControllerWillClose() {
        observeClient("controllerClose.begin", lifecycle: true)
        defer { observeClient("controllerClose.return", lifecycle: true) }
        log.info("closing controller: \(self.traceID, privacy: .public)")
        cancelModifiers(endingGesture: true)
        commit()
        let controller = Unchecked(self)
        MainActor.assumeIsolated {
            if ActiveInputSession.controller === controller.value { ActiveInputSession.controller = nil }
        }
        super.inputControllerWillClose()
    }

    var sessionRevision: UInt64 { session.revision }
    var clientTrace: ClientTrace { session.clientTrace }
    /// 상태 cache 와 호출 이력만 읽는다. Session 의 mutating 질의 중에도 그 Session 이나 client 문서를 읽지 않는다.
    func observeClient(_ phase: String, returnedCall: UInt64? = nil, lifecycle: Bool = false) {
        let state = session.clientTrace.snapshot.description
        let returned = returnedCall.map(String.init) ?? "none"
        let context = "controller=\(traceID) inputDepth=\(coordinator.inputDepth) mutation=\(session.isMutatingSession) explicitEnd=\(session.hasExplicitEnd) needsStart=\(coordinator.needsStart) returnedCall=\(returned) \(state)"
        if lifecycle {
            log.info("trace \(phase, privacy: .public) \(context, privacy: .public)")
            record("trace \(phase) \(context)")
        } else {
            log.debug("trace \(phase, privacy: .public) \(context, privacy: .public)")
        }
    }
    var hasCandidates: Bool { session.hasCandidates }
    var isHandlingEvent: Bool { session.isHandlingEvent }
    func afterEvent(_ presentation: @escaping () -> Void) { session.afterEvent(presentation) }

    override func menu() -> NSMenu! {
        let menu = NSMenu()
        menu.addItem(withTitle: "설정…", action: #selector(openSettings(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "최근 key 기록 저장", action: #selector(saveRecentRecord(_:)), keyEquivalent: "")
        return menu
    }

    @objc func openSettings(_ sender: Any?) {
        MainActor.assumeIsolated { SettingsWindow.shared.show() }
    }

    @objc func saveRecentRecord(_ sender: Any?) {
        do {
            let file = try saveRecord()
            log.info("record saved: \(file.path, privacy: .public)")
            NSWorkspace.shared.activateFileViewerSelecting([file])
        } catch {
            log.error("record save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// 마지막으로 활성화되거나 event 를 받은 controller. 표시와 source 전환 보완에만 쓰며 붙잡지 않는다.
@MainActor
enum ActiveInputSession {
    static weak var controller: HomiInputController?
}

/// Sendable 이 아닌 것을 main thread 의 지연 작업에 넘길 때 — controller 는 늘 main thread 에서만 쓴다.
nonisolated struct Unchecked<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

/// 관찰 권한이 없는 환경의 기존 판정. event 시각과 조회 시각이 다르다는 한계가 남는다.
nonisolated enum LegacyActivity {
    static func now() -> ModifierActivity {
        .counter([CGEventType.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel].map {
            CGEventSource.counterForEventType(.hidSystemState, eventType: $0)
        })
    }
}

/// 먹은 key 를 app 에 다시 보낸다 (`Outcome.resend`) — 손쉬운 사용 권한이 필요하다.
/// 다시 보낸 key 는 event 대기열의 끝에 붙는다: 그 key 뒤 수 ms 안에 이미 눌린 key 가 있으면 순서가 바뀔 수 있다 (AGENTS.md).
nonisolated enum Resend {
    private static let requested = Mutex(false)

    /// 권한이 있는가. 없으면 한 번만 요청한다 — System Settings 의 손쉬운 사용에 homi 가 나타난다.
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

    /// 새 key event 를 만들어 실제 keyboard 와 같은 경로(HID)로 보낸다 — key code 와 수식키만 옮긴다.
    /// 원래 event 를 복사해 보냈더니 Telegram 에 닿지 않았다 ("틱" 소리, 2026-09-25): 복사본에 원래 event 의 창·시각이 따라간다.
    /// 원래 key 처리가 끝난 뒤에 보낸다 — app 이 아직 그 key 를 처리하는 도중이다.
    static func post(_ event: NSEvent) {
        let keyCode = CGKeyCode(event.keyCode)
        let flags = event.cgEvent?.flags ?? []
        DispatchQueue.main.async {
            let source = CGEventSource(stateID: .hidSystemState)
            for down in [true, false] {
                guard let key = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else { continue }
                key.flags = flags
                key.post(tap: .cghidEventTap)
            }
            record("  resent kc=\(keyCode)")
        }
    }
}
