import AppKit
import Carbon
import InputSession

/// 실제 NSTextInputContext → IMKServer → 입력기 → NSTextView 경로. 입력은 이 창에 만든 test 글자뿐이다.
@MainActor
enum ProbeChecks {
    private static let homi = "com.unocult.inputmethod.homi.korean"
    private static let codes: [Character: UInt16] = ["g": 5, "k": 40, "s": 1, "r": 15, "m": 46, "f": 3, "w": 13]

    static func run(_ view: ProbeTextView, previousSource: String, previousApp: NSRunningApplication?,
                    manual: Bool, inputOnly: Bool = false, otherView: ProbeTextView? = nil) async {
        var failed = false
        var blocked = false
        let settings: Preferences = {
            if inputOnly { return .standard }
            guard let data = UserDefaults(suiteName: "com.unocult.inputmethod.homi")?.data(forKey: "preferences"),
                let value = try? JSONDecoder().decode(Preferences.self, from: data) else { return .standard }
            return value
        }()
        func check(_ condition: Bool, _ name: String) {
            journal?.write("CHECK \(condition ? "PASS" : "FAIL") \(name)")
            if !condition { failed = true }
        }
        if inputOnly {
            await settle()
            if systemSource() != homi || view.inputContext?.selectedKeyboardInputSource != homi {
                journal?.write("CHECK WAIT 첫 입력칸에서 homi 를 선택한다 — 검사 도구는 source 를 바꾸지 않는다")
                while systemSource() != homi || view.inputContext?.selectedKeyboardInputSource != homi {
                    await settle()
                }
            }
            if systemSource() == homi, view.inputContext?.selectedKeyboardInputSource == homi {
                check(true, "현재 homi 선택 확인 — source 는 바꾸지 않는다")
            } else {
                journal?.write("CHECK BLOCKED 기본 입력 검사는 현재 homi 가 선택되어 있어야 한다 — source 는 바꾸지 않는다")
                blocked = true
            }
        } else {
            view.inputContext?.selectedKeyboardInputSource = homi
            await settle()
            check(systemSource() == homi, "homi selected")
        }

        if manual, !failed && !blocked {
            journal?.write("CHECK WAIT 한글 모드에서 가 를 입력해 준비한다")
            if inputOnly {
                // 주인의 실제 입력을 기다리는 경로다. 기다리다 창을 닫으면 app 이 종료된다.
                while view.string != "가" || !view.hasMarkedText() { await settle() }
            } else {
                for _ in 0..<150 {
                    if view.string == "가", view.hasMarkedText() { break }
                    await settle()
                }
            }
            if view.string != "가" || !view.hasMarkedText() {
                journal?.write("CHECK BLOCKED 한글 모드·marked text 준비가 끝나지 않음")
                blocked = true
            }
        } else if !manual { type("rk", in: view) }
        if !manual, view.string == "rk" {
            clear(view)
            await toggle(settings, in: view)
            await settle()
            type("rk", in: view)
            if view.string == "rk" {
                journal?.write("CHECK BLOCKED context 에 만든 수식키로 한글 모드에 들어가지 못함 — --check-manual 로 준비할 수 있다")
                blocked = true
            }
        }
        if inputOnly, !failed && !blocked {
            if systemSource() == homi, view.inputContext?.selectedKeyboardInputSource == homi {
                check(true, "수동 준비 뒤에도 homi 선택 확인")
            } else {
                journal?.write("CHECK BLOCKED 준비 중 input source 가 바뀜 — homi 검사로 세지 않는다")
                blocked = true
            }
        }
        if !blocked { check(view.string == "가" && view.hasMarkedText(), "한글 모드·marked text") }
        if !failed && !blocked {
            clear(view)
            type("gksrmf", in: view)
            check(view.string == "한글", "두 음절 조합")
            key(51, characters: "\u{7f}", in: view)
            check(view.string == "한그", "Backspace 자소")
            view.inputContext?.discardMarkedText()
            check(view.string == "한그" && !view.hasMarkedText(), "명시적 commit")

            clear(view)
            type("gks", in: view)
            var insertedReentry = false
            view.onInsertOnce = {
                insertedReentry = true
                journal?.write("INJECT insertText 중 context deactivate → activate")
                view.inputContext?.deactivate()
                view.inputContext?.activate()
            }
            type("rmf", in: view)
            let insertedDuringInput = insertedReentry
            view.onInsertOnce = nil
            view.inputContext?.discardMarkedText()
            check(insertedDuringInput && view.string == "한글" && !view.hasMarkedText(), "insertText callback 에서 context 재활성화 뒤 글자 보존")

            clear(view)
            type("gk", in: view)
            var markedReentry = false
            view.onMarkOnce = {
                markedReentry = true
                journal?.write("INJECT setMarkedText 중 context deactivate → activate")
                view.inputContext?.deactivate()
                view.inputContext?.activate()
            }
            // 완성된 한 음절의 mark 에서 흔든다. context 가 명시적 commit 을 요청해도 음절 경계는 보존된다.
            type("srmf", in: view)
            let markedDuringInput = markedReentry
            view.onMarkOnce = nil
            view.inputContext?.discardMarkedText()
            check(markedDuringInput && view.string == "한글" && !view.hasMarkedText(), "setMarkedText callback 에서 context 재활성화 뒤 글자 보존")

            if inputOnly {
                if let otherView, let window = view.window, otherView.window === window {
                    clear(view)
                    otherView.string = ""
                    otherView.setSelectedRange(NSRange(location: 0, length: 0))
                    type("rmf", in: view)
                    check(view.string == "글" && view.hasMarkedText(), "입력칸 이동 전 조합")
                    journal?.write("CHECK MOVE own 입력칸 A → B — first responder")
                    let moved = window.makeFirstResponder(otherView)
                    await settle()
                    check(moved && view.string == "글" && !view.hasMarkedText(), "입력칸 이동 시 옛 칸에 한 번만 commit")
                    if moved {
                        check(otherView.string.isEmpty && !otherView.hasMarkedText(), "새 key 전에도 새 입력칸은 비어 있다")
                        type("gks", in: otherView)
                        otherView.inputContext?.discardMarkedText()
                        check(view.string == "글" && otherView.string == "한" && !otherView.hasMarkedText(),
                            "새 입력칸에 옛 조합이 새지 않는다")
                    }
                } else {
                    journal?.write("CHECK BLOCKED 기본 입력 검사의 두 번째 own 입력칸이 없다")
                    blocked = true
                }
            } else {
                clear(view)
                view.string = "한자"
                view.setSelectedRange(NSRange(location: 0, length: 2))
                var queriedReentry = false
                view.onSelectionQueryOnce = {
                    queriedReentry = true
                    journal?.write("INJECT selectedRange 중 context deactivate → activate")
                    view.inputContext?.deactivate()
                    view.inputContext?.activate()
                }
                if settings.effectiveHanjaKey == .optionReturn {
                    key(36, characters: "\r", modifiers: .option, in: view)
                    await settle()
                    key(18, characters: "1", in: view)
                    check(queriedReentry && view.string == "漢字" && !view.hasMarkedText(), "한자 key 의 context 처리 중 재활성화")
                } else {
                    journal?.write("CHECK BLOCKED 한자 수식키 tap 은 실제 keyboard 경로가 필요함")
                    blocked = true
                }
                view.onSelectionQueryOnce = nil

                clear(view)
                type("gks", in: view)
                check(view.string == "한" && view.hasMarkedText(), "source 전환 전 조합")
                check(select("com.apple.keylayout.ABC"), "외부 process 의 ABC 선택")
                await settle()
                check(view.string == "한" && !view.hasMarkedText(), "source 전환 시 한 번만 commit")
            }
        }
        view.onInsertOnce = nil
        view.onMarkOnce = nil
        view.onSelectionQueryOnce = nil
        otherView?.onInsertOnce = nil
        otherView?.onMarkOnce = nil
        otherView?.onSelectionQueryOnce = nil
        view.inputContext?.discardMarkedText()
        otherView?.inputContext?.discardMarkedText()
        if inputOnly, !failed && !blocked {
            let activeView = otherView ?? view
            check(systemSource() == homi && activeView.inputContext?.selectedKeyboardInputSource == homi,
                  "검사 종료에도 homi 선택 유지")
        }
        if !inputOnly {
            _ = select(previousSource)
            previousApp?.activate(options: [])
        }
        let result = failed ? "FAIL" : blocked ? "BLOCKED" : "PASS"
        journal?.write("CHECK RESULT \(result)")
        exit(failed ? EXIT_FAILURE : blocked ? 2 : EXIT_SUCCESS)
    }

    private static func settle() async { try? await Task.sleep(for: .milliseconds(200)) }
    private static func clear(_ view: ProbeTextView) {
        view.inputContext?.discardMarkedText()
        view.string = ""
        view.setSelectedRange(NSRange(location: 0, length: 0))
    }
    private static func type(_ letters: String, in view: ProbeTextView) {
        for letter in letters { key(codes[letter]!, characters: String(letter), in: view) }
    }
    private static func key(_ code: UInt16, characters: String, modifiers: NSEvent.ModifierFlags = [], in view: ProbeTextView) {
        let raw = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)!
        raw.timestamp = UInt64(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
        raw.flags = CGEventFlags(rawValue: UInt64(modifiers.rawValue))
        let units = Array(characters.utf16)
        units.withUnsafeBufferPointer { raw.keyboardSetUnicodeString(stringLength: units.count, unicodeString: $0.baseAddress) }
        let event = NSEvent(cgEvent: raw)!
        view.keyDown(with: event)
    }
    private static func tap(_ code: UInt16, flag: NSEvent.ModifierFlags, in view: ProbeTextView) async {
        let device: UInt64 = code == 54 ? 0x10 : code == 61 ? 0x40 : 0x2000
        for down in [true, false] {
            let raw = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
            raw.type = .flagsChanged
            raw.timestamp = UInt64(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
            raw.flags = CGEventFlags(rawValue: down ? UInt64(flag.rawValue) | device : 0)
            // probe 자신의 context 에 public API 로 전달한다.
            let event = NSEvent(cgEvent: raw)!
            journal?.write("CHECK flags → context kc=\(code) down=\(down)")
            _ = view.inputContext?.handleEvent(event)
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
    private static func toggle(_ settings: Preferences, in view: ProbeTextView) async {
        if settings.toggleKeys.contains(.rightCommand) { await tap(54, flag: .command, in: view) }
        else if settings.toggleKeys.contains(.rightOption) { await tap(61, flag: .option, in: view) }
        else if settings.toggleKeys.contains(.capsLock) { await tap(62, flag: .control, in: view) }
        else { key(49, characters: " ", modifiers: .shift, in: view) }
    }
    private static func select(_ id: String) -> Bool {
        let sources = TISCreateInputSourceList(nil, false).takeRetainedValue() as! [TISInputSource]
        guard let source = sources.first(where: { source in
            guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return false }
            return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String == id
        }) else { return false }
        return TISSelectInputSource(source) == noErr
    }
}
