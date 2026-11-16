// tis — input source 를 보고, 지켜보고, 바꾸는 개발 도구.
//
// input source 는 System Settings 의 "입력 소스" 목록 항목이다. 종류가 둘이다.
//   keyboard layout  key → 문자 표. 조합이 없다.        예) com.apple.keylayout.ABC
//   input method     조합하는 program. 안에 mode 가 여럿일 수 있다.
//                    예) com.apple.inputmethod.Korean (method) 안의 com.apple.inputmethod.Korean.2SetKorean (mode)
// TIS(Text Input Sources)는 이 목록과 "지금 무엇이 선택됐나"를 관리하는 Carbon(HIToolbox) API 다.

import AudioToolbox
import Carbon
import Foundation
import IOKit

let usage = """
    usage: tis <command>
      list [--all]     keyboard input source 목록. 기본은 활성화된 것만, --all 은 설치된 전부
                       E = enabled, S = selected, A = ASCII-capable
      current          지금 선택된 input source 와 그 아래 keyboard layout, 보안 입력 상태
      snapshot         읽기 전용 JSON 관측 (완전 0, 부분 1, 사용 오류 2)
      watch            선택·활성·보안 입력 변화를 시간순으로 출력 (Ctrl-C 로 끝)
      secure           Secure Event Input(보안 입력)이 켜져 있는지와 그때의 앞 app (켠 process 가 아니다) —
                       켜진 동안 활성화된 문서는 secure 인 source 만 쓴다 (docs/macos-input.md)
      secure sources   활성화된 source 마다 secure 여부와 입력기 bundle 의 위치 (읽기 전용) —
                       keyboard layout, /System/ 아래, /Library/Input Methods/ 의 입력기만 secure 다
      secure hold <초> 실험용 — 그 초 동안 이 process 가 보안 입력을 켜 둔다 (session 전역, Ctrl-C 로 미리 끈다).
                       그 사이에 활성화한 다른 app 의 문서는 secure 가 아닌 입력기를 ABC 로 바꾼다. 끝나면 알림음. 주인이 직접 돌린다
      pasteboards      TIS 가 process 사이에 공유하는 named pasteboard 의 내용 (읽기 전용) —
                       UI 순서(⌃Space 가 도는 목록)·선택된 input method·history·layout override
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

// Secure Event Input(보안 입력)은 비밀번호 칸·잠금 화면·terminal 의 Secure Keyboard Entry 가 켜는 session 전역 상태다.
// 켜져 있는 동안 활성화된 문서에서 TSM 은 secure 인 source 만 고른다 — secure 가 아닌 입력기(~/Library/Input Methods 의 것)는 ABC 로 바뀌고,
// 꺼진 뒤 다음 문서 활성화에서 돌아온다 (2026-11-05 실험·주인 확인, docs/macos-input.md). 알림이 없으므로 polling 으로 읽는다. IORegistry 의 IOConsoleUsers 에 남는
// kCGSSessionSecureInputPID 는 켠 process 가 아니라 **그때의 앞 app** 이다 — CLI 와 WindowServer 연결을 가진 background app 둘 다로 확인했다 (11-05).
// 그래서 "front" 로 적는다. 켠 쪽은 그 시각에 살아 있는 process(예: 다른 agent 의 Playwright headless Chromium)와 대조해 찾는다.
func secureInputHolder() -> pid_t? {
    let root = IORegistryGetRootEntry(kIOMainPortDefault)
    defer { IOObjectRelease(root) }
    guard let users = IORegistryEntryCreateCFProperty(root, "IOConsoleUsers" as CFString, kCFAllocatorDefault, 0)?
        .takeRetainedValue() as? [[String: Any]] else { return nil }
    for user in users {
        if let pid = user["kCGSSessionSecureInputPID"] as? NSNumber, pid.int32Value > 0 { return pid.int32Value }
    }
    return nil
}

func processName(_ pid: pid_t) -> String {
    var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
    guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return "?" }
    return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
}

/// "on pid 1317 Safari" 또는 "off". IsSecureEventInputEnabled 는 thread safe 하지 않으므로 main thread 에서만 부른다.
func secureInputDescription() -> String {
    guard IsSecureEventInputEnabled() else { return "off" }
    guard let pid = secureInputHolder() else { return "on (front unknown)" }
    return "on front \(pid) \(processName(pid))"
}

/// 보안 입력이 켜진 채 활성화된 문서에서 TSM 은 secure 인 keyboard input source 만 고르고, 아닌 입력기에는 key 를 보내지 않는다.
/// HIToolbox 가 secure 로 보는 것은 keyboard layout, `/System/` 아래의 것, bundle 경로가 `/Library/Input Methods/` 로 시작하는 입력기다
/// (macOS 27.2 의 `islGetInputSourceIsSecureCandidate`, docs/macos-input.md) — `~/Library/Input Methods` 의 입력기는 아니다.
/// 공개 API 에는 이 값이 없어 HIToolbox 의 private symbol 로 읽기만 한다. symbol 이 없는 macOS 에서는 읽을 수 없다고 답한다.
func secureSources() {
    typealias Getter = @convention(c) (TISInputSource, CFString) -> UnsafeMutableRawPointer?
    guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "TSMGetInputSourceProperty") else {  // RTLD_DEFAULT
        FileHandle.standardError.write(Data("tis: TSMGetInputSourceProperty is not exported by this macOS\n".utf8))
        exit(1)
    }
    let get = unsafeBitCast(symbol, to: Getter.self)
    func value<T>(_ source: TISInputSource, _ key: String) -> T? {
        guard let raw = get(source, key as CFString) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue() as? T
    }
    for source in keyboardSources(all: false) {
        let secure: Bool? = value(source, "TSMInputSourcePropertyIsSecure")
        let bundle: URL? = value(source, "TSMInputSourcePropertyInputMethodURL")
        let flag = secure.map { $0 ? "secure" : "-" } ?? "?"
        print("\(pad(flag, 7)) \(pad(sourceID(source), 50)) \(bundle?.path ?? "")")
    }
}

/// 실험용: 앞 app 과 무관하게 보안 입력을 들고 있는 process 를 흉내 낸다 (다른 agent 의 headless Chromium 이 그랬다).
/// 켜진 동안 활성화한 다른 app 의 문서는 secure 가 아닌 입력기를 ABC 로 바꾸고, 꺼진 뒤에도 다시 활성화될 때까지 그대로다 (docs/macos-input.md).
/// 시간이 다 되거나 Ctrl-C 면 끈다. process 가 죽어도 system 이 거둔다.
func holdSecureInput(seconds: Double) {
    let status = EnableSecureEventInput()
    guard status == noErr else {
        FileHandle.standardError.write(Data("EnableSecureEventInput failed: \(status)\n".utf8))
        exit(1)
    }
    func finish(_ why: String) -> Never {
        DisableSecureEventInput()
        print("\(stamp())  secure    \(secureInputDescription()) (\(why))")
        AudioServicesPlayAlertSound(kSystemSoundID_UserPreferredAlert)
        usleep(400_000)  // 알림음이 나갈 시간
        exit(0)
    }
    signal(SIGINT, SIG_IGN)
    let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    interrupt.setEventHandler { finish("Ctrl-C") }
    interrupt.resume()
    print("\(stamp())  secure    \(secureInputDescription()) — \(seconds)초 동안 켜 둔다 (Ctrl-C 로 미리 끈다)")
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { finish("\(seconds)초 끝") }
    dispatchMain()
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
    print("\(pad("secure event input", 22)) \(secureInputDescription())")
}

/// TIS 가 보내는 distributed notification 을 받아 시간순으로 적고, 알림이 없는 보안 입력은 0.25초마다 읽어 바뀔 때만 적는다.
final class Watcher: NSObject {
    var lastSecure = IsSecureEventInputEnabled()

    @objc func selectedChanged(_ note: Notification) { report("selected") }
    @objc func enabledChanged(_ note: Notification) { report("enabled ") }

    @objc func pollSecure(_ timer: Timer) {
        let now = IsSecureEventInputEnabled()
        guard now != lastSecure else { return }
        lastSecure = now
        reportSecure()
    }

    func report(_ what: String) {
        let now = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        print("\(stamp())  \(what)  \(sourceID(now))  secure=\(secureInputDescription())")
    }

    func reportSecure() {
        print("\(stamp())  secure    \(secureInputDescription())")
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
    Timer.scheduledTimer(
        timeInterval: 0.25, target: watcher, selector: #selector(Watcher.pollSecure(_:)), userInfo: nil, repeats: true)
    watcher.report("start   ")
    RunLoop.main.run()
    exit(0)
}

// TIS 는 process 마다 따로 사는 Carbon framework 라, "지금 enabled·selected 가 무엇인가"를 pasteboard server 의
// named pasteboard 로 공유한다 (2026-11-03 관측: 전환을 실행한 앞 app 이 AppleKeyboardInputMethodsPasteboard 와
// AppleKeyboardLayoutOverridePasteboard 를 쓴다). 여기서는 읽기만 한다 — PasteboardCreate 는 이름으로 열 뿐이다.
let sharedPasteboards = [
    "AppleInputSourcesInUIOrderPasteboard", "AppleKeyboardInputMethodsPasteboard", "AppleInputSourceHistoryPasteboard",
    "AppleKeyboardLayoutOverridePasteboard", "DefaultAsciiKeyboardLayoutPasteboard", "AppleIntlFileCacheModificationDatePasteboard",
]

func pasteboards() {
    for name in sharedPasteboards {
        var pasteboard: Pasteboard?
        let status = PasteboardCreate(name as CFString, &pasteboard)
        guard status == noErr, let pasteboard else { print("\(name): PasteboardCreate failed \(status)"); continue }
        PasteboardSynchronize(pasteboard)
        var count = 0
        PasteboardGetItemCount(pasteboard, &count)
        print("\(name)  items \(count)")
        guard count > 0 else { continue }
        for index in 1...count {
            var itemID: PasteboardItemID?
            guard PasteboardGetItemIdentifier(pasteboard, index, &itemID) == noErr, let itemID else { continue }
            var flavors: CFArray?
            guard PasteboardCopyItemFlavors(pasteboard, itemID, &flavors) == noErr, let flavors = flavors as? [String] else { continue }
            for flavor in flavors {
                var flavorData: CFData?
                guard PasteboardCopyItemFlavorData(pasteboard, itemID, flavor as CFString, &flavorData) == noErr,
                      let data = flavorData as Data? else { print("  \(flavor): unreadable"); continue }
                if let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) {
                    let text = "\(object)".split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
                    print("  \(flavor): \(text)")
                } else {
                    print("  \(flavor): \(data.count) bytes (not a plist)")
                }
            }
        }
    }
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
case "snapshot":
    guard args.count == 1 else { fail("snapshot") }
    let result = collectSnapshot(liveSnapshotQueries())
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.keyEncodingStrategy = .convertToSnakeCase
    do {
        let data = try encoder.encode(result)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([10]))
        exit(result.partial ? 1 : 0)
    } catch { fail("snapshot JSON encoding failed") }
case "watch":
    watch()
case "pasteboards":
    pasteboards()
case "secure":
    if args.count == 1 { print(secureInputDescription()); break }
    if args.count == 2, args[1] == "sources" { secureSources(); break }
    guard args.count == 3, args[1] == "hold", let seconds = Double(args[2]), seconds > 0, seconds <= 300 else { fail("secure [sources | hold <초>]") }
    holdSecureInput(seconds: seconds)
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
