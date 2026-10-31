import AppKit
import InputMethodKit
import HangulCore
import InputSession

extension KeyEvent {
    /// NSEvent 에서 판단에 쓰는 것만 옮긴다.
    nonisolated init(_ event: NSEvent) {
        let flags = event.modifierFlags
        let pairs: [(NSEvent.ModifierFlags, Modifiers)] = [
            (.shift, .shift), (.control, .control), (.option, .option),
            (.command, .command), (.capsLock, .capsLock), (.function, .function),
        ]
        let modifiers = pairs.reduce(into: Modifiers()) { result, pair in
            if flags.contains(pair.0) { result.insert(pair.1) }
        }
        self.init(keyCode: event.keyCode, modifiers: modifiers)
    }
}

extension ModifierEvent {
    /// flagsChanged 당시의 방향과 활동 번호를 함께 옮긴다.
    nonisolated init(_ event: NSEvent, activity: ModifierActivity) {
        let position = ModifierPosition(keyCode: event.keyCode, flags: UInt64(event.modifierFlags.rawValue))
        self.init(keyCode: event.keyCode, modifiers: KeyEvent(event).modifiers, time: event.timestamp, activity: activity,
            isDown: position.isDown, oppositeSideDown: position.oppositeSideDown)
    }
}

/// IMK 의 client proxy 에 Session 이 정한 일을 한다.
/// replacementRange 는 NSNotFound — 문서 위치를 믿지 않는다 (AGENTS.md 결정 5).
/// 예외는 `markCommitted` 하나: ⌥↩ 가 방금 친 단어를 바꿀 때, 교체를 제대로 받는 client 에서 그 자리 글자를 확인한 뒤에만.
nonisolated struct Client: InputClient {
    let proxy: any IMKTextInput & NSObjectProtocol
    weak var owner: HomiInputController?
    private let traceOverride: ClientTrace?
    private let candidatesOverride: CandidatePresentation?
    private let submissionOverride: CompositionSubmission?

    init(proxy: any IMKTextInput & NSObjectProtocol, owner: HomiInputController? = nil, trace: ClientTrace? = nil,
         candidates: CandidatePresentation? = nil, submission: CompositionSubmission? = nil) {
        self.proxy = proxy
        self.owner = owner
        self.traceOverride = trace
        self.candidatesOverride = candidates
        self.submissionOverride = submission
    }

    private var trace: ClientTrace? { traceOverride ?? owner?.clientTrace }
    private var submission: CompositionSubmission? { submissionOverride ?? owner?.compositionSubmission }
    private var candidatePresentation: CandidatePresentation? { candidatesOverride ?? owner.map { CandidatePresentation(owner: $0) } }

    private static let nowhere = NSRange(location: NSNotFound, length: 0)

    func apply(_ actions: [Action]) {
        if let submission { submission.withActions(actions) { applyTraced(actions) } }
        else { applyTraced(actions) }
    }

    private func applyTraced(_ actions: [Action]) {
        if let trace {
            let batch = trace.plan(actions, state: trace.snapshot.cachedState)
            trace.withBatch(batch) { apply(actions, batch: batch) }
        } else {
            apply(actions, batch: nil)
        }
    }

    private func apply(_ actions: [Action], batch: ClientTrace.Batch?) {
        for (index, action) in actions.enumerated() {
            let planned = batch?.call(at: index)
            submission?.willApply(action)
            switch action {
            case .mark(let text):
                record("  mark \"\(text)\"")
                let caret = NSRange(location: (text as NSString).length, length: 0)
                call("mark", planned: planned, kind: .mark) {
                    proxy.setMarkedText(text, selectionRange: caret, replacementRange: Self.nowhere)
                }
            case .markCommitted(let text, let range):
                record("  mark \"\(text)\" over {\(range.location),\(range.length)}")
                let caret = NSRange(location: (text as NSString).length, length: 0)
                call("markCommitted", planned: planned, kind: .mark) {
                    proxy.setMarkedText(text, selectionRange: caret, replacementRange: range)
                }
            case .insert(let text):
                record("  insert \"\(text)\"")
                // {NSNotFound, NSNotFound} 실험은 Chrome 의 실패를 해결하지 못했다. 기존 range 로 복귀한다.
                call("insert", planned: planned, kind: .insert) {
                    proxy.insertText(text, replacementRange: Self.nowhere)
                }
            case .showCandidates(let candidates, let selected):
                record("  candidates \(selected)/\(candidates.count)")
                let line = caretLine()  // key 처리 도중에 묻는다 — ModeHUD 와 같은 이유
                candidatePresentation?.show(candidates, selected: selected, below: line)
            case .hideCandidates:
                record("  candidates hidden")
                candidatePresentation?.hide()
            case .layout(let id):
                record("  layout \(id)")
                call("layout", planned: planned, kind: .layout) { proxy.overrideKeyboard(withKeyboardNamed: id) }
            }
        }
    }

    /// call frame 을 올린 뒤에만 관측한다. 반환은 proxy 호출의 완료이지 renderer 확정의 증거가 아니다.
    private func call<Result>(_ name: String, planned: ClientTrace.PlannedCall? = nil,
                              kind: ClientTrace.CallKind = .query, _ body: () -> Result) -> Result {
        guard let trace else { return body() }
        var callID: UInt64?
        let invoke = {
            callID = trace.snapshot.frame?.id
            self.owner?.observeClient("client.\(name).begin")
            return body()
        }
        let result: Result
        if let planned { result = trace.withCall(planned, invoke) }
        else { result = trace.withCall(kind, invoke) }
        owner?.observeClient("client.\(name).return", returnedCall: callID)
        return result
    }
}

extension Client {
    nonisolated func bundleIdentifier() -> String? { call("bundleIdentifier") { proxy.bundleIdentifier() } }

    /// 선택 영역의 글자 — ⌥↩ 로 단어를 한자로 바꿀 때만, key 처리 도중에 묻는다. 없거나 너무 길면 nil.
    nonisolated func selectedText() -> String? {
        let range = call("selectedRange") { proxy.selectedRange() }
        guard range.location != NSNotFound, range.length > 0, range.length <= 40 else { return nil }
        return call("selectedSubstring") { proxy.attributedSubstring(from: range)?.string }
    }

    /// 조합 중인 글자(없으면 커서) 바로 앞 `count` 글자와 그 끝의 문서 위치 — ⌥↩ 가 방금 친 단어를 바꿀 수 있는지 볼 때만,
    /// key 처리 도중에 묻는다. 확정된 글자의 교체를 제대로 받는 client 가 아니거나, 선택 영역이 있거나, 답이 없으면 nil.
    nonisolated func textBefore(_ count: Int) -> (text: String, end: Int)? {
        guard replacesLikeTextView() else { return nil }
        let marked = call("markedRange") { proxy.markedRange() }
        let end: Int
        if marked.location != NSNotFound, marked.length > 0 {
            end = marked.location
        } else {
            let selected = call("selectedRange") { proxy.selectedRange() }
            guard selected.location != NSNotFound, selected.length == 0 else { return nil }
            end = selected.location
        }
        guard count > 0, end >= count,
            let text = call("precedingSubstring", { proxy.attributedSubstring(from: NSRange(location: end - count, length: count))?.string })
        else { return nil }
        return (text, end)
    }

    /// 확정된 글자를 marked text 로 되돌리는 교체(`replacementRange`)를 제대로 받는 client 인가 — macOS 의 text 엔진(NSTextView)처럼
    /// 교체 범위와 받아쓰기 대안(`NSTextAlternatives`)까지 받는다고 알릴 때만. Chromium·WebKit 은 앞의 것만 알리고
    /// (그 위의 JS editor 가 교체를 모른다), JetBrains Runtime·terminal 은 아무것도 알리지 않는다 (docs/macos-input.md).
    nonisolated func replacesLikeTextView() -> Bool {
        let attributes = Set((call("validMarkedAttributes") { proxy.validAttributesForMarkedText() } ?? []).compactMap { $0 as? String })
        return attributes.isSuperset(of: ["NSTextInputReplacementRangeAttributeName", "NSTextAlternatives"])
    }

    /// 커서가 있는 줄의 사각형 (화면 좌표) — 입력기가 후보 창을 띄울 때 쓰는 IMK 의 질의. 모르는 client 는 빈 사각형.
    nonisolated func caretLine() -> NSRect {
        var line = NSRect.zero
        _ = call("caretAttributes") { proxy.attributes(forCharacterIndex: 0, lineHeightRectangle: &line) }
        return line
    }
}
