import Foundation
import HangulCore

/// 한/영 모드. 영문은 key 를 그대로 넘긴다.
public enum Mode: Sendable, Equatable {
    case korean
    case english

    public var toggled: Mode { self == .korean ? .english : .korean }
}

/// 입력칸(client)에 할 일.
public enum Action: Sendable, Equatable {
    /// 조합 중인 글자를 marked text 로 보인다. 빈 문자열이면 marked text 를 지운다.
    /// marked text 가 없고 선택 영역이 있으면 그것을 대신한다.
    case mark(String)
    /// 이미 확정된 글자 `range`(문서 위치)를 marked text 로 되돌린다 — ⌥↩ 가 방금 친 단어를 바꿀 때만 (결정 5 의 예외).
    case markCommitted(String, range: NSRange)
    /// 글자를 확정해 넣는다. marked text 가 있으면 그 자리를, 선택 영역이 있으면 그것을 대신한다.
    case insert(String)
    /// 한자 후보 창을 보이거나 고친다 — `selected` 는 전체 목록에서 고른 자리.
    case showCandidates([Candidate], selected: Int)
    /// 한자 후보 창을 닫는다.
    case hideCandidates
    /// homi 아래의 keyboard layout 을 바꾼다 — 한/영을 layout 으로 알리는 app 에서 모드가 바뀔 때 (`AppProfile.keyboardLayoutFollowsMode`).
    case layout(String)
}

/// key 하나를 처리한 결과.
public struct Outcome: Sendable, Equatable {
    /// true 면 homi 가 먹었다 — app 은 이 key 를 모른다. false 면 app 이 이어서 처리한다.
    public var handled: Bool
    /// client 에게 이 순서대로 한다.
    public var actions: [Action]
    /// 이 key 다음의 모드. 다음 key 는 이 모드로 처리된다.
    public var mode: Mode
    /// 이 key 를 먹은 뒤 app 에 다시 보낸다 (`AppProfile.resendWhileComposing`). 그때는 조합이 없다.
    public var resend: Bool

    public init(handled: Bool, actions: [Action], mode: Mode, resend: Bool = false) {
        self.handled = handled
        self.actions = actions
        self.mode = mode
        self.resend = resend
    }
}

/// 입력칸(client) session 하나의 입력. IMK 를 모른다 — 조합 규칙은 docs/spec.md.
///
/// client 를 직접 부르지 않고 할 일을 돌려준다. IMK 는 우리의 `insertText` 도중에 deactivate 를 끼워 부를 수 있어서,
/// 상태를 바꾸는 중에 client 를 부르면 그 사이에 다시 들어온 `commit` 과 겹친다 (docs/research/app-compat-and-hangul.md §1).
/// 조합 중인 글자는 marked text 로만 보이고, 이미 확정한 글자는 다시 쓰지 않는다 (AGENTS.md 결정 5) —
/// 예외는 ⌥↩ 가 방금 친 단어를 바꿀 때 하나: 교체를 제대로 받는 client 에서, 그 자리 글자를 확인한 뒤에만.
///
/// 모드는 session 밖(app 별 기억)에 있고 key 마다 받아서 돌려준다. 전환(`toggle`)은 전환 key 의 event 처리 안에서 끝난다 —
/// 전환 key(Caps Lock·오른쪽 ⌘ 의 tap)와 다음 key 가 같은 흐름에서 차례로 오므로 "전환 → 다음 key" 순서가 구조로 보장된다 (결정 1·3).
public struct Session: Sendable {
    private var composer = Composer()
    private let hanja: HanjaDictionary?
    /// 이 입력칸에 homi 가 방금 이어서 친 한글 중 확정된 것 — ⌥↩ 가 바꿀 단어를 찾는 곳 (app 의 문서를 뒤지지 않는다).
    /// 커서가 움직일 만한 일(한글 아닌 key, 수식키 조합, click, 입력칸 이동, 전환)이 있으면 비운다.
    private var recent = ""
    /// 한자 후보를 고르는 중이면 그 상태.
    private var choosing: Choosing?

    /// 한자 후보를 고르는 중 — 무엇을 바꾸는지, 바꿀 단어들(긴 것부터)과 지금 고른 자리.
    /// 바꿀 한글은 늘 marked text 다: 조합 중인 글자, ⌥↩ 때 선택 영역에서 시작한 조합, 또는 marked text 로 되돌린 단어.
    /// 그래서 고르는 key 는 marked text 가 있는 채로 app 에 닿고(app 이 그 key 를 입력기의 것으로 본다),
    /// 고르면 조합을 확정하는 것과 같은 `insert` 한 번으로 바뀐다.
    private struct Choosing: Sendable {
        enum Target: Sendable, Equatable {
            case composing
            case selection
            /// 커서 앞의 확정된 글자 — `end` 는 그 끝의 문서 위치.
            case committed(end: Int)
        }
        struct Option: Sendable {
            let word: String
            let candidates: [Candidate]
        }
        let target: Target
        let options: [Option]
        /// ⌥↩ 를 다시 누르면 다음(더 짧은) 단어로 — 방금 친 단어일 때만 여럿이다.
        var option = 0
        var index = 0

        var current: Option { options[option] }

        /// 고르지 않고 끝낼 때 — marked text 로 바꿔 두었던 한글을 그대로 확정한다. 조합 중인 글자는 조합 중으로 남는다.
        var restore: [Action] { target == .composing ? [] : [.insert(current.word)] }
    }

    /// 한 쪽에 보이는 후보 수 — 1–9 로 고른다.
    public static let page = 9
    /// ⌥↩ 가 찾는 단어의 최대 길이 (음절).
    public static let longestWord = 8

    public init(hanja: HanjaDictionary? = nil) {
        self.hanja = hanja
    }

    /// 조합 중인 글자.
    public var composing: String { composer.composing }

    /// key 하나를 처리한다. `profile` 은 이 입력칸의 app 규칙 (`AppRules`).
    /// ⌥↩ 때만 app 에게 묻는 것 둘 — key 처리 도중이라 안전하다:
    /// - `selectedText`: 선택 영역의 글자
    /// - `textBefore(n)`: 조합 중인 글자(없으면 커서) 바로 앞 n 글자와 그 끝의 문서 위치.
    ///   확정된 글자의 교체를 제대로 받는 client 만 답한다 — 아니면 nil 이고, 조합 중인 글자만 바꾼다.
    public mutating func handle(
        _ key: KeyEvent, mode: Mode, profile: AppProfile = AppProfile(), selectedText: () -> String? = { nil },
        textBefore: (Int) -> (text: String, end: Int)? = { _ in nil }
    ) -> Outcome {
        let outcome = handleKey(key, mode: mode, profile: profile, selectedText: selectedText, textBefore: textBefore)
        return Self.following(outcome, from: mode, profile: profile)
    }

    private mutating func handleKey(
        _ key: KeyEvent, mode: Mode, profile: AppProfile, selectedText: () -> String? = { nil },
        textBefore: (Int) -> (text: String, end: Int)? = { _ in nil }
    ) -> Outcome {
        if profile.passThrough {
            // 한/영 전환 없는 app — 전환도 조합도 하지 않는다. (조합이 남아 있을 수 없지만, 있다면 잃지 않게 확정한다.)
            return Outcome(handled: false, actions: commit(), mode: mode)
        }
        if choosing != nil { return choose(key, mode: mode, profile: profile) }
        if profile.toggleKeys.contains(.shiftSpace), key.isShiftSpace { return flip(from: mode) }
        if mode == .korean, profile.hanjaKey == .optionReturn, key.isHanjaKey,
            let outcome = openHanja(profile: profile, selectedText: selectedText, textBefore: textBefore)
        {
            return outcome
        }
        if profile.englishTriggers.contains(where: { $0.matches(key) }) {
            // 확정하고 영문으로. key 는 app 에 간다 — 조합 중이라 app 이 그 key 를 잃는다면 다시 보낸다.
            return pass(key, profile: profile, mode: .english)
        }
        guard mode == .korean else {
            // 영문: 그대로 넘긴다. (조합이 남아 있을 수 없지만, 있다면 잃지 않게 확정한다.)
            return Outcome(handled: false, actions: commit(), mode: mode)
        }
        // ⌘·⌃·⌥·fn 조합은 app·system 의 몫이다. ⌥ 도 영문일 때와 같게 넘긴다 (2026-09-25 주인 결정).
        if !key.modifiers.isDisjoint(with: [.command, .control, .option, .function]) {
            return Outcome(handled: false, actions: commit(), mode: mode)
        }
        if key.keyCode == KeyCode.delete {
            guard composer.backspace() else {
                if !recent.isEmpty { recent.removeLast() }  // app 이 확정된 글자 하나를 지운다
                return Outcome(handled: false, actions: [], mode: mode)
            }
            return Outcome(handled: true, actions: [.mark(composer.composing)], mode: mode)
        }
        guard let jamo = Dubeolsik.jamo(keyCode: key.keyCode, shift: key.modifiers.contains(.shift)) else {
            // Space·Return·문장부호·화살표…: 확정하고, 문자는 아래 layout 이 만들게 넘긴다.
            return pass(key, profile: profile, mode: mode)
        }
        let committed = composer.type(jamo)
        remember(committed)
        let actions: [Action] = committed.isEmpty ? [] : [.insert(committed)]
        return Outcome(handled: true, actions: actions + [.mark(composer.composing)], mode: mode)
    }

    /// 확정된 한글을 기억한다 — 한글 음절이 아닌 것이 확정되면 단어가 끊긴다.
    private mutating func remember(_ committed: String) {
        guard !committed.isEmpty else { return }
        if committed.unicodeScalars.allSatisfy(\.isHangulSyllable) {
            recent = String((recent + committed).suffix(Self.longestWord))
        } else {
            recent = ""
        }
    }

    /// ⌥↩ — 방금 친 단어(Apple 입력기처럼 선택 없이), 조합 중인 글자, 선택한 한글 순으로 한자 후보를 연다.
    /// nil 이면 한자 변환이 아니다 — ⌥↩ 를 평소처럼 처리한다.
    private mutating func openHanja(
        profile: AppProfile, selectedText: () -> String?, textBefore: (Int) -> (text: String, end: Int)?
    ) -> Outcome? {
        guard let hanja else { return nil }
        let consume = Outcome(handled: true, actions: [], mode: .korean)
        // 낱자모가 조합 중이면 한자가 없다 — 그래도 먹는다 (⌥↩ 가 조합을 확정하고 줄을 바꾸지 않게).
        guard composing.unicodeScalars.allSatisfy(\.isHangulSyllable) else { return consume }

        if profile.convertsEnteredText, profile.hanjaRecentWord, let outcome = openRecent(textBefore) { return outcome }
        if !composing.isEmpty {
            let candidates = hanja.candidates(for: composing)
            guard !candidates.isEmpty else { return consume }
            return open(Choosing(target: .composing, options: [.init(word: composing, candidates: candidates)]))
        }
        guard profile.convertsEnteredText, let text = selectedText(), !text.isEmpty,
            text.unicodeScalars.allSatisfy(\.isHangulSyllable)
        else { return nil }
        // 선택한 한글이면 후보가 없어도 먹는다 — app 에 넘기면 많은 app 이 선택 영역을 줄바꿈으로 바꿔 버린다.
        let candidates = hanja.candidates(for: text)
        guard !candidates.isEmpty else { return consume }
        // 선택 영역에서 조합을 시작한다 — 선택 영역에 한글을 칠 때와 같은 길이다 (위치를 주지 않는다).
        return open(Choosing(target: .selection, options: [.init(word: text, candidates: candidates)]), [.mark(text)])
    }

    /// 방금 친 단어 — 기억(`recent`)과 조합 중인 글자를 이은 것에서 사전에 있는 끝부분을 긴 것부터 고른다 (나는한자 → 한자, 자).
    /// 확정된 글자가 들어간 단어가 있으면 app 에게 그 자리 글자를 확인하고, 조합 중인 글자를 확정한 뒤 단어를 marked text 로 되돌린다.
    /// nil 이면 확정된 글자가 들어간 단어가 없거나, app 이 답하지 않거나, 기억과 다르다 — 조합 중인 글자만 본다.
    private mutating func openRecent(_ textBefore: (Int) -> (text: String, end: Int)?) -> Outcome? {
        guard let hanja, !recent.isEmpty else { return nil }
        let current = composing
        let word = recent + current
        let options: [Choosing.Option] = stride(from: min(word.count, Self.longestWord), through: 1, by: -1)
            .compactMap { length in
                let suffix = String(word.suffix(length))
                let candidates = hanja.candidates(for: suffix)
                return candidates.isEmpty ? nil : .init(word: suffix, candidates: candidates)
            }
        guard let longest = options.first, longest.word.count > current.count else { return nil }
        let committed = longest.word.count - current.count
        guard let found = textBefore(committed) else { return nil }
        guard found.text == String(recent.suffix(committed)) else {
            recent = ""  // app 의 글자가 기억과 다르다 — 커서가 homi 모르게 움직였다
            return nil
        }
        let end = found.end + current.utf16.count  // 조합 중인 글자를 확정한 뒤의 끝
        remember(composer.flush())
        let state = Choosing(target: .committed(end: end), options: options)
        return open(state, (current.isEmpty ? [] : [.insert(current)]) + [Self.mark(state.current.word, endingAt: end)])
    }

    private static func mark(_ word: String, endingAt end: Int) -> Action {
        let length = word.utf16.count
        return .markCommitted(word, range: NSRange(location: end - length, length: length))
    }

    private mutating func open(_ state: Choosing, _ actions: [Action] = []) -> Outcome {
        choosing = state
        return Outcome(handled: true, actions: actions + [Self.show(state)], mode: .korean)
    }

    private static func show(_ state: Choosing) -> Action {
        .showCandidates(state.current.candidates, selected: state.index)
    }

    /// 후보를 고르는 동안의 key — 1–9 고르기, ↑↓ 옮기기, ←→ 쪽 넘기기, Enter·Space 확정, ESC 취소.
    /// 그 밖의 key 는 후보를 닫고 평소처럼 처리한다.
    private mutating func choose(_ key: KeyEvent, mode: Mode, profile: AppProfile) -> Outcome {
        guard var state = choosing else { return Outcome(handled: false, actions: [], mode: mode) }
        let count = state.current.candidates.count
        let pageStart = state.index / Self.page * Self.page

        if profile.hanjaKey == .optionReturn, key.isHanjaKey { return again(mode: mode) }
        if key.modifiers.subtracting([.capsLock, .function]).isEmpty {
            if let digit = KeyCode.digits.firstIndex(of: key.keyCode), digit > 0 {
                let index = pageStart + digit - 1
                return index < count ? pick(index, mode: mode) : Outcome(handled: true, actions: [], mode: mode)
            }
            switch key.keyCode {
            case KeyCode.down:
                state.index = min(state.index + 1, count - 1)
            case KeyCode.up:
                state.index = max(state.index - 1, 0)
            case KeyCode.right:
                state.index = min(pageStart + Self.page, count - 1)
            case KeyCode.left:
                state.index = max(pageStart - Self.page, 0)
            case KeyCode.returnKey, KeyCode.enter, KeyCode.space:
                return pick(state.index, mode: mode)
            case KeyCode.escape:
                // 취소 — 한글은 그대로 남는다. 조합 중이던 글자는 조합 중으로.
                choosing = nil
                return Outcome(handled: true, actions: [.hideCandidates] + state.restore, mode: mode)
            default:
                return closeAndHandle(key, mode: mode, profile: profile)
            }
            choosing = state
            return Outcome(handled: true, actions: [Self.show(state)], mode: mode)
        }
        return closeAndHandle(key, mode: mode, profile: profile)
    }

    /// 한자 key 를 다시 — 방금 친 단어면 다음(더 짧은) 단어로, 마지막 다음은 처음으로 (한자 → 자 → 한자).
    /// 그 밖에는 이미 열려 있으니 먹기만 한다 — 넘기면 app 이 그 key 를 받는다 (IntelliJ 의 ⌥↩ = context action 등).
    private mutating func again(mode: Mode) -> Outcome {
        guard var state = choosing, case .committed(let end) = state.target, state.options.count > 1 else {
            return Outcome(handled: true, actions: [], mode: mode)
        }
        let restore = state.restore
        state.option = (state.option + 1) % state.options.count
        state.index = 0
        choosing = state
        let actions = restore + [Self.mark(state.current.word, endingAt: end), Self.show(state)]
        return Outcome(handled: true, actions: actions, mode: mode)
    }

    /// 한자 key 가 수식키 tap(오른쪽 ⌥·⌘)일 때 — tap 의 판정은 homi app 층이 하고, 여기서 연다. 후보가 열려 있으면 다시 누른 것과 같다.
    /// nil 이면 한자 변환이 아니다 — tap 은 아무 일도 하지 않는다.
    public mutating func hanjaTapped(
        mode: Mode, profile: AppProfile, selectedText: () -> String? = { nil },
        textBefore: (Int) -> (text: String, end: Int)? = { _ in nil }
    ) -> Outcome? {
        guard !profile.passThrough else { return nil }
        if choosing != nil { return again(mode: mode) }
        guard mode == .korean else { return nil }
        return openHanja(profile: profile, selectedText: selectedText, textBefore: textBefore)
    }

    private mutating func closeAndHandle(_ key: KeyEvent, mode: Mode, profile: AppProfile) -> Outcome {
        let restore = choosing?.restore ?? []
        choosing = nil
        var outcome = handleKey(key, mode: mode, profile: profile)
        outcome.actions.insert(contentsOf: [.hideCandidates] + restore, at: 0)
        return outcome
    }

    /// 후보 하나로 바꾼다 — 바꿀 한글은 marked text 이므로 `insert` 가 그 자리를 대신한다.
    private mutating func pick(_ index: Int, mode: Mode) -> Outcome {
        guard let state = choosing else { return Outcome(handled: true, actions: [], mode: mode) }
        choosing = nil
        recent = ""  // 한자 뒤로는 새 단어다
        _ = composer.flush()  // 조합 중인 글자였다면 한자가 대신한다
        return Outcome(
            handled: true, actions: [.hideCandidates, .insert(state.current.candidates[index].hanja)], mode: mode)
    }

    /// 조합을 확정하고 key 를 app 에 넘긴다. 조합 중이었고 이 app 이 그 key 를 잃는다면, 먹고 다시 보낸다.
    private mutating func pass(_ key: KeyEvent, profile: AppProfile, mode: Mode) -> Outcome {
        let wasComposing = !composing.isEmpty
        let actions = commit()
        let resend = wasComposing && profile.resendWhileComposing.contains(key.keyCode)
        return Outcome(handled: resend, actions: actions, mode: mode, resend: resend)
    }

    /// 한/영 전환 — 조합 중이면 먼저 확정한다. `profile` 은 이 입력칸의 app 규칙 (layout 을 따라 바꾸는 app 이 있다).
    public mutating func toggle(from mode: Mode, profile: AppProfile = AppProfile()) -> Outcome {
        Self.following(flip(from: mode), from: mode, profile: profile)
    }

    private mutating func flip(from mode: Mode) -> Outcome {
        Outcome(handled: true, actions: commit(), mode: mode.toggled)
    }

    /// 모드가 바뀌었으면, 한/영을 keyboard layout 으로 알리는 app(원격 화면)에서는 homi 아래의 layout 도 바꾼다 —
    /// 그 app 은 입력기의 글자가 아니라 이 layout 으로 만든 글자를 보낸다. 확정한 글자를 넣은 뒤에.
    private static func following(_ outcome: Outcome, from mode: Mode, profile: AppProfile) -> Outcome {
        guard outcome.mode != mode, profile.keyboardLayoutFollowsMode, !profile.passThrough else { return outcome }
        var outcome = outcome
        outcome.actions.append(.layout(profile.keyboardLayout(in: outcome.mode)))
        return outcome
    }

    /// 조합 중인 글자를 확정한다 — 입력칸을 떠날 때, client 가 요청할 때, 넘기는 key 앞에서.
    /// 비우면서 돌려주므로 두 번 불려도 한 번만 들어간다. 한자 후보를 고르던 중이었다면 창을 닫는다.
    public mutating func commit() -> [Action] {
        let closing: [Action] = choosing.map { [.hideCandidates] + $0.restore } ?? []
        choosing = nil
        recent = ""
        let text = composer.flush()
        return closing + (text.isEmpty ? [] : [.insert(text)])
    }
}
