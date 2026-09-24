// probe — 입력기가 app(client)에게 무엇을 어떤 순서로 하는지 보는 test client.
//
// key 하나가 글자가 되는 길:
//   key event → app 의 view.keyDown → NSTextInputContext → 선택된 input method (별도 process)
//   input method 는 client(= 이 view)의 NSTextInputClient method 를 불러 결과를 돌려준다.
//     setMarkedText  조합 중인 글자(marked text) — 밑줄 친 "하"가 이것이다
//     insertText     글자를 확정(commit)해 넣는다
//     doCommand      Return·Backspace·화살표 같은 편집 명령 (input method 가 먹지 않은 key)
// NSTextView 가 NSTextInputClient 를 구현하므로 그 method 들을 가로채 시간순으로 적는다.
// input source 변화도 두 층에서 적는다: system 전체(TIS notification)와 이 app 의 context.
//
// 들여쓰기가 호출 중첩이다:
//   keyDown
//     handleEvent →          app 이 context 를 통해 input method 에 event 를 넘김
//       ? selectedRange      input method 가 처리 중에 client 에게 묻는 것 (? 로 시작)
//       insertText …         input method 가 처리 중에 client 에게 시키는 것
//     handleEvent ← handled  input method 가 event 를 먹었나 (not handled 면 app 이 이어서 처리)
//
// 위 칸에 타이핑하면 아래 칸과 stdout 에 나온다. ⌘K 는 log 비우기. 띄우기: scripts/probe.sh

import AppKit
import Carbon

func stamp() -> String {
    var now = timeval()
    gettimeofday(&now, nil)
    var seconds = now.tv_sec
    var local = tm()
    localtime_r(&seconds, &local)
    return String(format: "%02d:%02d:%02d.%03d", local.tm_hour, local.tm_min, local.tm_sec, Int(now.tv_usec / 1000))
}

let keyNames: [UInt16: String] = [
    36: "return", 48: "tab", 49: "space", 50: "`", 51: "delete", 53: "esc", 57: "capslock",
    54: "rcmd", 55: "lcmd", 56: "lshift", 60: "rshift", 58: "lopt", 61: "ropt",
    59: "lctrl", 62: "rctrl", 63: "fn", 123: "left", 124: "right", 125: "down", 126: "up",
]

func modifiers(_ flags: NSEvent.ModifierFlags) -> String {
    var s = ""
    if flags.contains(.capsLock) { s += "⇪" }
    if flags.contains(.control) { s += "⌃" }
    if flags.contains(.option) { s += "⌥" }
    if flags.contains(.shift) { s += "⇧" }
    if flags.contains(.command) { s += "⌘" }
    if flags.contains(.function) { s += "fn" }
    return s.isEmpty ? "-" : s
}

/// 문자열과 code point. 호환 자모(U+3131…)와 조합형 자모(U+1100…)를 구분해 보려고 둘 다 적는다.
func quoted(_ value: Any) -> String {
    let text = (value as? NSAttributedString)?.string ?? (value as? String) ?? "\(value)"
    let points = text.unicodeScalars.map { String(format: "%04X", $0.value) }.joined(separator: " ")
    return "\"\(text)\" [\(points)]"
}

func range(_ r: NSRange) -> String {
    r.location == NSNotFound ? "{-,\(r.length)}" : "{\(r.location),\(r.length)}"
}

func systemSource() -> String {
    let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "?" }
    return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
}

final class Journal {
    let view: NSTextView
    let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    var depth = 0

    init(view: NSTextView) { self.view = view }

    func write(_ text: String) {
        let line = "\(stamp())  \(String(repeating: "  ", count: depth))\(text)\n"
        FileHandle.standardOutput.write(line.data(using: .utf8)!)
        view.textStorage?.append(
            NSAttributedString(string: line, attributes: [.font: font, .foregroundColor: NSColor.textColor]))
        view.scrollToEndOfDocument(nil)
    }

    func clear() { view.string = "" }
}

/// log 는 하나다. AppDelegate 가 창을 만들 때 채운다.
var journal: Journal?

/// app 이 input method 에 event 를 넘기는 관문. 들어가고 나오는 것과, 그 사이인지를 알려준다.
/// NSTextInputContext 는 SDK 에서 actor 격리가 없어 이 class 도 nonisolated 다. 불리는 곳은 늘 main thread.
nonisolated final class ProbeInputContext: NSTextInputContext {
    private(set) var inside = false

    override func handleEvent(_ event: NSEvent) -> Bool {
        let start = ProcessInfo.processInfo.systemUptime
        MainActor.assumeIsolated {
            journal?.write("handleEvent →")
            journal?.depth += 1
        }
        inside = true
        let handled = super.handleEvent(event)
        inside = false
        let took = (ProcessInfo.processInfo.systemUptime - start) * 1000
        let result = "handleEvent ← \(handled ? "handled" : "not handled") " + String(format: "%.0fms", took)
        MainActor.assumeIsolated {
            journal?.depth -= 1
            journal?.write(result)
        }
        return handled
    }
}

final class ProbeTextView: NSTextView {
    // lazy 로 두면 안 된다: context 는 init 안에서 client 에게 validAttributesForMarkedText 를 묻고,
    // 그 질문을 기록하려고 context 를 다시 만들면 무한 재귀다. 만들어지기 전에는 nil 로 둔다.
    private var probeContext: ProbeInputContext?
    override var inputContext: NSTextInputContext? {
        if let probeContext { return probeContext }
        let context = ProbeInputContext(client: self)
        probeContext = context
        return context
    }

    private var contextSource: String { inputContext?.selectedKeyboardInputSource ?? "-" }

    /// event 가 만들어진 뒤 여기 오기까지 걸린 시간.
    private func delay(_ event: NSEvent) -> String {
        String(format: "+%.0fms", (ProcessInfo.processInfo.systemUptime - event.timestamp) * 1000)
    }

    /// input method 가 event 처리 중에 client 에게 묻는 것만 적는다. 평소 text system 이 스스로 묻는 것은 너무 많다.
    private func asked(_ text: String) {
        if probeContext?.inside == true { journal?.write("? \(text)") }
    }

    override func keyDown(with event: NSEvent) {
        let name = keyNames[event.keyCode].map { " \($0)" } ?? ""
        let repeated = event.isARepeat ? " repeat" : ""
        journal?.write(
            "keyDown     kc=\(event.keyCode)\(name) chars=\(quoted(event.characters ?? "")) "
                + "mods=\(modifiers(event.modifierFlags))\(repeated) \(delay(event))  ctx=\(contextSource)")
        journal?.depth += 1
        super.keyDown(with: event)
        journal?.depth -= 1
    }

    override func flagsChanged(with event: NSEvent) {
        let name = keyNames[event.keyCode].map { " \($0)" } ?? ""
        journal?.write("flags       kc=\(event.keyCode)\(name) mods=\(modifiers(event.modifierFlags)) \(delay(event))")
        journal?.depth += 1
        super.flagsChanged(with: event)
        journal?.depth -= 1
    }

    override var selectedRange: NSRange {
        get {
            let value = super.selectedRange
            asked("selectedRange → \(range(value))")
            return value
        }
        set { super.selectedRange = newValue }
    }

    override func markedRange() -> NSRange {
        let value = super.markedRange()
        asked("markedRange → \(range(value))")
        return value
    }

    override func hasMarkedText() -> Bool {
        let value = super.hasMarkedText()
        asked("hasMarkedText → \(value)")
        return value
    }

    override func attributedSubstring(forProposedRange proposed: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        let value = super.attributedSubstring(forProposedRange: proposed, actualRange: actualRange)
        asked("attributedSubstring \(range(proposed)) → \(value.map { quoted($0) } ?? "nil")")
        return value
    }

    override func firstRect(forCharacterRange proposed: NSRange, actualRange: NSRangePointer?) -> NSRect {
        let value = super.firstRect(forCharacterRange: proposed, actualRange: actualRange)
        asked("firstRect \(range(proposed))")
        return value
    }

    override func characterIndex(for point: NSPoint) -> Int {
        let value = super.characterIndex(for: point)
        asked("characterIndex → \(value)")
        return value
    }

    override func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        let value = super.validAttributesForMarkedText()
        asked("validAttributesForMarkedText")
        return value
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        journal?.write("setMarked   \(quoted(string)) sel=\(range(selectedRange)) repl=\(range(replacementRange))")
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        journal?.write("insertText  \(quoted(string)) repl=\(range(replacementRange))")
        super.insertText(string, replacementRange: replacementRange)
    }

    override func unmarkText() {
        journal?.write("unmarkText")
        super.unmarkText()
    }

    override func doCommand(by selector: Selector) {
        journal?.write("doCommand   \(NSStringFromSelector(selector))")
        super.doCommand(by: selector)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    var input: ProbeTextView?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let width: CGFloat = 900
        let input = ProbeTextView(frame: NSRect(x: 0, y: 0, width: width, height: 180))
        input.font = .systemFont(ofSize: 22)
        input.allowsUndo = true
        input.isAutomaticSpellingCorrectionEnabled = false
        input.isAutomaticTextReplacementEnabled = false
        input.isAutomaticQuoteSubstitutionEnabled = false

        let logView = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 480))
        logView.isEditable = false
        journal = Journal(view: logView)

        let split = NSSplitView(frame: NSRect(x: 0, y: 0, width: width, height: 680))
        split.isVertical = false
        split.dividerStyle = .thin
        split.addArrangedSubview(scrollable(input))
        split.addArrangedSubview(scrollable(logView))

        let window = NSWindow(
            contentRect: split.frame, styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = "probe"
        window.contentView = split
        split.setPosition(180, ofDividerAt: 0)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(input)
        window.orderFrontRegardless()
        NSApp.activate()

        self.window = window
        self.input = input
        observe()
        journal?.write("start       sys=\(systemSource())  ctx=\(input.inputContext?.selectedKeyboardInputSource ?? "-")")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    @objc func clearLog(_ sender: Any?) { journal?.clear() }

    // system 전체의 선택 변화(TIS)와, 이 app 의 context 가 아는 선택 변화는 따로 온다.
    @objc func systemSourceChanged(_ note: Notification) {
        journal?.write("sys source  → \(systemSource())")
    }

    @objc func contextSourceChanged(_ note: Notification) {
        journal?.write("ctx source  → \(input?.inputContext?.selectedKeyboardInputSource ?? "-")")
    }

    @objc func activeChanged(_ note: Notification) {
        journal?.write(note.name == NSApplication.didBecomeActiveNotification ? "app active" : "app inactive")
    }

    private func observe() {
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(systemSourceChanged(_:)),
            name: .init(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil,
            suspensionBehavior: .deliverImmediately)
        let center = NotificationCenter.default
        center.addObserver(
            self, selector: #selector(contextSourceChanged(_:)),
            name: NSTextInputContext.keyboardSelectionDidChangeNotification, object: nil)
        center.addObserver(
            self, selector: #selector(activeChanged(_:)), name: NSApplication.didBecomeActiveNotification, object: nil)
        center.addObserver(
            self, selector: #selector(activeChanged(_:)), name: NSApplication.didResignActiveNotification, object: nil)
    }

    private func scrollable(_ view: NSTextView) -> NSScrollView {
        let scroll = NSScrollView(frame: view.frame)
        scroll.hasVerticalScroller = true
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        view.textContainer?.widthTracksTextView = true
        scroll.documentView = view
        return scroll
    }
}

func mainMenu() -> NSMenu {
    let menu = NSMenu()

    let appItem = NSMenuItem()
    let appMenu = NSMenu()
    appMenu.addItem(withTitle: "Clear Log", action: #selector(AppDelegate.clearLog(_:)), keyEquivalent: "k")
    appMenu.addItem(.separator())
    appMenu.addItem(withTitle: "Quit probe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    appItem.submenu = appMenu
    menu.addItem(appItem)

    // 실제 app 처럼 ⌘ 단축키를 menu 가 먼저 가져가게 한다 — 입력기가 ⌘C 의 C 를 못 보는 상황도 재현된다.
    let editItem = NSMenuItem()
    let edit = NSMenu(title: "Edit")
    edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
    edit.addItem(.separator())
    edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    editItem.submenu = edit
    menu.addItem(editItem)

    return menu
}

// system 이 이 process 안에서 남기는 message(TSM·IMK 의 NSLog)도 같은 log 에 시간순으로 섞이게 한다.
dup2(STDOUT_FILENO, STDERR_FILENO)
setvbuf(stdout, nil, _IOLBF, 0)

let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.setActivationPolicy(.regular)
app.mainMenu = mainMenu()
app.run()
