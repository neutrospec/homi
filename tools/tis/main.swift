// tis — input source 를 보고, 지켜보고, 바꾸는 개발 도구.
//
// input source 는 System Settings 의 "입력 소스" 목록 항목이다. 종류가 둘이다.
//   keyboard layout  key → 문자 표. 조합이 없다.        예) com.apple.keylayout.ABC
//   input method     조합하는 program. 안에 mode 가 여럿일 수 있다.
//                    예) com.apple.inputmethod.Korean (method) 안의 com.apple.inputmethod.Korean.2SetKorean (mode)
// TIS(Text Input Sources)는 이 목록과 "지금 무엇이 선택됐나"를 관리하는 Carbon(HIToolbox) API 다.

import Carbon
import Foundation

let usage = """
    usage: tis <command>
      list [--all]     keyboard input source 목록. 기본은 활성화된 것만, --all 은 설치된 전부
                       E = enabled, S = selected, A = ASCII-capable
      current          지금 선택된 input source 와 그 아래 keyboard layout
      watch            선택·활성 변화를 시간순으로 출력 (Ctrl-C 로 끝)
      register <path>  input method bundle 을 TIS 에 등록
      enable <id>      활성화 — System Settings 의 목록에 넣는다
      disable <id>     비활성화
      select <id>      선택 — 지금 쓰는 input source 로 만든다
    """

func property<T>(_ source: TISInputSource, _ key: CFString) -> T? {
    guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
    return Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue() as? T
}

func sourceID(_ source: TISInputSource) -> String {
    property(source, kTISPropertyInputSourceID) ?? "?"
}

/// keyboard 범주의 input source. `all` 이 false 면 활성화된 것만.
func keyboardSources(all: Bool, id: String? = nil) -> [TISInputSource] {
    var filter: [String: Any] = [
        kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String
    ]
    if let id { filter[kTISPropertyInputSourceID as String] = id }
    guard let list = TISCreateInputSourceList(filter as CFDictionary, all)?.takeRetainedValue() else { return [] }
    return (list as NSArray).map { $0 as! TISInputSource }
}

func pad(_ s: String, _ width: Int) -> String {
    s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
}

func stamp() -> String {
    var now = timeval()
    gettimeofday(&now, nil)
    var seconds = now.tv_sec
    var local = tm()
    localtime_r(&seconds, &local)
    return String(format: "%02d:%02d:%02d.%03d", local.tm_hour, local.tm_min, local.tm_sec, Int(now.tv_usec / 1000))
}

func row(_ source: TISInputSource) -> String {
    let enabled: Bool = property(source, kTISPropertyInputSourceIsEnabled) ?? false
    let selected: Bool = property(source, kTISPropertyInputSourceIsSelected) ?? false
    let ascii: Bool = property(source, kTISPropertyInputSourceIsASCIICapable) ?? false
    let type: String = property(source, kTISPropertyInputSourceType) ?? "?"
    let name: String = property(source, kTISPropertyLocalizedName) ?? ""
    let flags = (enabled ? "E" : "·") + (selected ? "S" : "·") + (ascii ? "A" : "·")
    let kind = type.replacingOccurrences(of: "TISTypeKeyboard", with: "")
    return "\(flags)  \(pad(sourceID(source), 50)) \(pad(kind, 24)) \(name)"
}

func current() {
    // 지금 key 를 받는 input source 와, 그 아래에서 key code → 문자를 정하는 keyboard layout 은 따로 있다.
    // ASCII-capable 쪽은 영문이 필요할 때 system 이 쓰는, 가장 최근에 선택된 ASCII 입력 가능 source 다.
    let rows: [(String, Unmanaged<TISInputSource>?)] = [
        ("keyboard input source", TISCopyCurrentKeyboardInputSource()),
        ("keyboard layout", TISCopyCurrentKeyboardLayoutInputSource()),
        ("ASCII-capable source", TISCopyCurrentASCIICapableKeyboardInputSource()),
        ("ASCII-capable layout", TISCopyCurrentASCIICapableKeyboardLayoutInputSource()),
    ]
    for (label, source) in rows {
        print("\(pad(label, 22)) \(source.map { sourceID($0.takeRetainedValue()) } ?? "-")")
    }
}

/// TIS 가 보내는 distributed notification 을 받아 시간순으로 적는다.
final class Watcher: NSObject {
    @objc func selectedChanged(_ note: Notification) { report("selected") }
    @objc func enabledChanged(_ note: Notification) { report("enabled ") }

    func report(_ what: String) {
        let now = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        print("\(stamp())  \(what)  \(sourceID(now))")
    }
}

func watch() -> Never {
    let watcher = Watcher()
    let center = DistributedNotificationCenter.default()
    center.addObserver(
        watcher, selector: #selector(Watcher.selectedChanged(_:)),
        name: .init(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil,
        suspensionBehavior: .deliverImmediately)
    center.addObserver(
        watcher, selector: #selector(Watcher.enabledChanged(_:)),
        name: .init(kTISNotifyEnabledKeyboardInputSourcesChanged as String), object: nil,
        suspensionBehavior: .deliverImmediately)
    watcher.report("start   ")
    RunLoop.main.run()
    exit(0)
}

func check(_ status: OSStatus, _ what: String) {
    guard status != noErr else { return }
    FileHandle.standardError.write("tis: \(what) failed — OSStatus \(status)\n".data(using: .utf8)!)
    exit(1)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("tis: \(message)\n".data(using: .utf8)!)
    exit(2)
}

setvbuf(stdout, nil, _IOLBF, 0)
let args = Array(CommandLine.arguments.dropFirst())

switch args.first {
case "list":
    keyboardSources(all: args.contains("--all")).map(row).forEach { print($0) }
case "current":
    current()
case "watch":
    watch()
case "register":
    guard args.count == 2 else { fail("register <path>") }
    check(TISRegisterInputSource(URL(fileURLWithPath: args[1]) as CFURL), "register")
case "enable", "disable", "select":
    guard args.count == 2 else { fail("\(args[0]) <id>") }
    guard let source = keyboardSources(all: true, id: args[1]).first else { fail("no input source \(args[1])") }
    switch args[0] {
    case "enable": check(TISEnableInputSource(source), "enable")
    case "disable": check(TISDisableInputSource(source), "disable")
    default: check(TISSelectInputSource(source), "select")
    }
default:
    print(usage)
    exit(args.isEmpty ? 0 : 2)
}
