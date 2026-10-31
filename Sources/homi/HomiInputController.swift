import AppKit
import InputMethodKit
import InputSession
import Synchronization

/// IMK 가 입력칸(client) session 마다 하나씩 만드는 controller. 입력의 판단은 `Session`·`ModifierKeys`·`AppRules` 가 하고,
/// 여기서는 event 를 넘기고 결과를 client 에 옮길 뿐이다 (AGENTS.md 결정 7).
///
/// 한/영 모드는 app 별 기억(`memory`)에 있고, key 마다 이 입력칸의 app 으로 읽는다 —
/// activate 알림이 늦거나 빠져도 틀리지 않는다.
/// IMK header 에는 actor 표시가 없어 override 들이 nonisolated 여야 한다. 불리는 곳은 main thread 다.
@objc(HomiInputController)
nonisolated final class HomiInputController: IMKInputController {
    private let session = SessionDriver(hanja: hanjaDictionary)
    private var modifierKeys = ModifierKeys()
    private var modifierBinding = ModifierEventBinding()
    private lazy var capsLockHold = HoldTimer(owner: self)
    /// 이 controller 가 맡은 입력칸의 app — controller 는 client 하나에 묶여 있어 바뀌지 않는다.
    private var app: String?
    private var modeActivation = ModeActivation()
    /// SessionDriver 의 종료 flush 와 실제 입력 event 를 구분한다.
    private var inputDepth = 0
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
        let resuming = inputDepth > 0 && !session.hasExplicitEnd
        modeActivation.activate(resumingInput: resuming)
        session.activate()
        let controller = Unchecked(self)
        MainActor.assumeIsolated { ActiveInputSession.controller = controller.value }
        // 실제 ID 를 이미 알며 client 반영 중이 아닐 때만 즉시 초기화한다. 그 밖에는 실제 입력 경계까지 intent 를 보존한다.
        if !session.isHandlingEvent, inputDepth == 0, let app { prepareMode(for: app) }
        // activate 안에서는 client 에 묻지 않으며 fallback app 의 기억도 reset 하지 않는다.
        let app = app ?? frontmostApp()
        let profile = profile(for: app)
        let mode = memory.withLock { $0.mode(for: app) }
        // homi 가 넘긴 key 는 이 layout 으로 문자가 된다 — 늘 ABC, 원격 화면의 한글 모드만 두벌식 (`AppProfile.keyboardLayout`).
        // 새 시작의 layout 은 activate 에서만 준비한다. 같은 event 의 재활성화는 기존 layout 도 이어 간다.
        let layoutMode: Mode = modeActivation.needsStart && profile.startsInEnglish ? .english : mode
        let layout = profile.keyboardLayout(in: layoutMode)
        if !resuming, let proxy = sender as? any IMKTextInput & NSObjectProtocol {
            Client(proxy: proxy, owner: self).apply([.layout(layout)])
        }
        log.info("activate \(app, privacy: .public), controller: \(self.traceID, privacy: .public)")
        record("activate \(app) \(profile.passThrough ? "pass-through" : "\(mode)") \(resuming ? "layout preserved" : layout)")
        showIndicator(mode, app: app, passThrough: profile.passThrough)
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
            session.clientConfirmed { target?.apply($0) }
        } else {
            commit()
        }
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, let proxy = sender as? any IMKTextInput & NSObjectProtocol else { return false }
        inputDepth += 1
        defer { inputDepth -= 1 }
        return session.withEvent {
            let controller = Unchecked(self)
            MainActor.assumeIsolated { ActiveInputSession.controller = controller.value }
            let app = resolveApp(Client(proxy: proxy, owner: self))
            if !receivedEvent {
                receivedEvent = true
                log.info("receiving events from \(app, privacy: .public), controller: \(self.traceID, privacy: .public)")
            }
            switch event.type {
            case .keyDown:
                prepareMode(for: app)
                return keyDown(event, app: app, client: Client(proxy: proxy, owner: self))
            case .flagsChanged:
                prepareMode(for: app)
                modifiersChanged(event, app: app, client: Client(proxy: proxy, owner: self))
                return false
            case .leftMouseDown:
                record("mouseDown")
                cancelModifiers(endingGesture: true)
                commit()
                return false
            default:
                return false
            }
        }
    }

    private func keyDown(_ event: NSEvent, app: String, client: Client) -> Bool {
        cancelModifiers()
        let key = KeyEvent(event)
        record("key \(key)")
        let mode = memory.withLock { $0.mode(for: app) }
        let input = modeActivation.beginInput(app: app, trusted: self.app != nil)
        // 질의·상태 변경·client 반영을 같은 동기 경계에 둔다. 그 사이의 lifecycle 은 경계 끝에서 처리한다.
        var outcome = session.perform({
            $0.handle(key, mode: mode, profile: profile(for: app), selectedText: { client.selectedText() },
                textBefore: { client.textBefore($0) })
        }, apply: { _ in })
        preserveInputMode(input, outcome: outcome, from: mode)
        if outcome.resend && !Resend.allowed() {
            // 다시 보낼 수 없으면 먹지 않는다 — key 를 잃는 것보다 예전처럼 넘기는 게 낫다.
            outcome.handled = false
            outcome.resend = false
            record("  resend not allowed — passed")
        }
        switchMode(to: outcome.mode, from: mode, app: app)
        client.apply(outcome.actions)
        if outcome.mode != mode { showMode(outcome.mode, near: client) }
        if outcome.resend {
            record("  resend")
            Resend.post(event)
        }
        record(outcome.handled ? "  handled" : "  passed")
        return outcome.handled
    }

    /// 수식키 — tap·hold 의 판정과 뜻(한/영 전환·한자·대문자 고정)은 `ModifierKeys` 가 주인의 설정대로 정하고, 여기서는 그 일을 한다.
    private func modifiersChanged(_ event: NSEvent, app: String, client: Client) {
        let profile = profile(for: app)
        guard !profile.passThrough else { cancelModifiers(endingGesture: true); return }
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
        guard let action = result.action else { return }
        record("modifier kc=\(event.keyCode) → \(action)")
        switch action {
        case .toggle:
            toggle(app: app, profile: profile, client: client)
        case .hanja:
            let mode = memory.withLock { $0.mode(for: app) }
            let input = modeActivation.beginInput(app: app, trusted: self.app != nil)
            session.perform({
                $0.hanjaTapped(mode: mode, profile: profile, selectedText: { client.selectedText() },
                    textBefore: { client.textBefore($0) })
            }, apply: {
                if let outcome = $0 {
                    preserveInputMode(input, outcome: outcome, from: mode)
                    client.apply(outcome.actions)
                }
            })
        case .capsLock:
            // 표시는 macOS 의 Caps Lock 표시에 맡긴다 — homi 가 따로 띄우면 겹친다 (주인, 2026-09-25).
            CapsLockState.toggle()
        }
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

    private func toggle(app: String, profile: AppProfile, client: Client) {
        let mode = memory.withLock { $0.mode(for: app) }
        let input = modeActivation.beginInput(app: app, trusted: self.app != nil)
        session.perform({ $0.toggle(from: mode, profile: profile) }, apply: { outcome in
            preserveInputMode(input, outcome: outcome, from: mode)
            switchMode(to: outcome.mode, from: mode, app: app)
            client.apply(outcome.actions)
            showMode(outcome.mode, near: client)
        })
    }

    /// 실제 조합·mode 변경이 있을 때만 불확실한 app 의 입력을 늦은 ID 보정에 이어 준다.
    private func preserveInputMode(_ input: ModeActivation.Input?, outcome: Outcome, from mode: Mode) {
        // Session 판단이 반환된 뒤라 mutating 접근은 끝났다. 진단 cache 를 입력 판단에 쓰지 않는다.
        modeActivation.inputHandled(input, modeChanged: outcome.mode != mode,
            composing: !session.composing.isEmpty || session.hasCandidates)
    }

    /// 커서 옆 말풍선. 커서 줄의 위치는 지금(key 처리 도중, app 이 homi 를 기다리는 동안) 묻고 — 그 밖에서 client 를 부르면
    /// app 과 교착할 수 있다 (조사: Chrome) — 그리는 일은 key 처리 뒤로 미룬다.
    private func showMode(_ mode: Mode, near client: Client) {
        let line = client.caretLine()
        let text = mode.glyph
        Task { @MainActor in ModeHUD.shared.show(text, below: line) }
    }

    private func switchMode(to mode: Mode, from old: Mode, app: String) {
        guard mode != old else { return }
        let updated = memory.withLock { memory in
            memory.remember(mode, for: app)
            return memory
        }
        Memory.save(updated)
        log.info("mode \(String(describing: mode), privacy: .public) for \(app, privacy: .public)")
        record("mode \(mode)")
        // menu bar 표시는 key 처리 밖에서 — 결정 4
        showIndicator(mode, app: app, passThrough: profile(for: app).passThrough)
    }

    /// client 의 실제 ID(또는 그 cache)를 아는 경계에서 시작 규칙을 한 번 적용한다.
    private func prepareMode(for app: String) {
        let profile = profile(for: app)
        let trusted = self.app != nil
        let initializing = modeActivation.needsStart && trusted
        let (mode, changed) = memory.withLock { memory in
            let before = memory
            let mode = modeActivation.prepare(app: app, trusted: trusted, profile: profile, memory: &memory)
            return (mode, memory != before ? memory : nil)
        }
        if let changed { Memory.save(changed) }
        if initializing || changed != nil {
            log.info("input start prepared for \(app, privacy: .public), controller: \(self.traceID, privacy: .public), mode: \(String(describing: mode), privacy: .public)")
            record("input start \(app) \(mode)")
            showIndicator(mode, app: app, passThrough: profile.passThrough)
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

    /// 이 입력칸의 app. client 가 bundle ID 를 모르면 맨 앞 app 으로 (조사: nil 일 수 있다).
    private func resolveApp(_ client: Client) -> String {
        if let app { return app }
        let id = client.bundleIdentifier() ?? ""
        let resolved = id.isEmpty ? frontmostApp() : id
        // 불확실한 fallback 은 영구 cache 하지 않는다. 다음 key 에 client 가 답하면 바로잡는다.
        if !id.isEmpty {
            app = resolved
            showIndicator(memory.withLock { $0.mode(for: resolved) }, app: resolved, passThrough: profile(for: resolved).passThrough)
        }
        return resolved
    }

    private func frontmostApp() -> String {
        MainActor.assumeIsolated { NSWorkspace.shared.frontmostApplication?.bundleIdentifier } ?? "unknown"
    }

    /// 조합 중인 글자를 이 controller 가 맡은 client 에 확정한다.
    /// deactivate·commitComposition 의 sender 는 이미 다른 client 일 수 있어 쓰지 않는다 (docs/research).
    /// `insert` 가 false 면 client 가 조합을 이미 확정했다 — homi 의 조합만 버리고 글자는 넣지 않는다.
    private func commit(insert: Bool = true) {
        if !insert { record("  finished by client — not inserting") }
        let target = client().map { Client(proxy: $0, owner: self) }
        session.commit(insert: insert) { target?.apply($0) }
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
        let context = "controller=\(traceID) inputDepth=\(inputDepth) mutation=\(session.isMutatingSession) explicitEnd=\(session.hasExplicitEnd) needsStart=\(modeActivation.needsStart) returnedCall=\(returned) \(state)"
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
