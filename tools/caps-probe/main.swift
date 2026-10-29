// Caps Lock 의 물리 HID 신호와 remap 뒤 Quartz modifier 신호를 비교한다.
// 읽기 전용: listenOnly·Caps Lock element matching 만 쓴다. 설정 변경·event 전송·문자 질의 없음.
// 수집 중에는 memory 에만 쌓는다. 출력·TIS·app·mapping 조회는 관찰 전후에만 한다.
import AppKit
import Carbon
import CoreGraphics
import Foundation
import IOKit.hid
import IOKit.hidsystem

private enum Sample {
    case hid(ticks: UInt64, down: Bool, device: IOHIDDevice)
    case quartz(nanoseconds: UInt64, sampledTicks: UInt64, key: Int64, flags: UInt64, activity: [UInt32], lastInput: UInt64?)
    case followingInput(gapMilliseconds: Double)
    case gap
}

/// 두 callback 을 main run loop 에 등록한다. actor 우회·lock·key event 중 I/O 는 쓰지 않는다.
private final class Timeline {
    private var samples: [Sample] = []
    private(set) var dropped = 0
    private(set) var lastInput: UInt64?
    var releasedAt: UInt64?

    /// 일반 key 의 code·문자는 읽지 않는다. 마지막 입력 시각 하나와 Caps Lock 직후 간격만 memory 에 둔다.
    func input(at time: UInt64) {
        precondition(Thread.isMainThread)
        lastInput = time
        if let releasedAt {
            append(.followingInput(gapMilliseconds: (Double(time) - Double(releasedAt)) / 1_000_000))
            self.releasedAt = nil
        }
    }

    func append(_ sample: Sample) {
        precondition(Thread.isMainThread)
        guard samples.count < 2048 else { dropped += 1; return }
        samples.append(sample)
    }

    func drain() -> [Sample] {
        precondition(Thread.isMainThread)
        defer { samples.removeAll(keepingCapacity: true) }
        return samples
    }
}

private func write(_ line: String) {
    FileHandle.standardOutput.write(Data((line + "\n").utf8))
}

private func sourceID() -> String {
    let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    return TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
        .map { Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String } ?? "unknown"
}

private func capsMapping() -> String {
    let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
    let map = IOHIDEventSystemClientCopyProperty(client, kIOHIDUserKeyUsageMapKey as CFString) as? [[String: Any]] ?? []
    let entries = map.filter { ($0["HIDKeyboardModifierMappingSrc"] as? UInt64) == 0x700000039 }
    return entries.map { entry in
        (entry["HIDKeyboardModifierMappingDst"] as? UInt64).map { String(format: "0x%llx", $0) } ?? "unknown"
    }.joined(separator: ",").nilIfEmpty ?? "none"
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

@main
private struct CapsProbe {
    @MainActor
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        let seconds: Int
        if args.isEmpty { seconds = 90 }
        else if args.count == 2, args[0] == "--seconds", let value = Int(args[1]), (1...600).contains(value) { seconds = value }
        else { write("usage: caps-probe [--seconds 1...600]"); exit(64) }

        write("Read-only Caps Lock probe. Ordinary key codes and text are not collected. No settings are changed.")
        write("Only anonymous activity timing adjacent to Caps Lock is reported.")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        write("Started: \(formatter.string(from: Date())) duration=\(seconds)s")
        write("source=\(sourceID()) capsMapping=\(capsMapping())")
        write("appAtStart=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown")")
        guard CGPreflightListenEventAccess() else {
            write("BLOCKED: input-listening access is unavailable. No permission request was made.")
            exit(2)
        }

        let timeline = Timeline()
        defer { withExtendedLifetime(timeline) {} }
        let context = Unmanaged.passUnretained(timeline).toOpaque()
        let inputTypes: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        let mask = (inputTypes + [.flagsChanged]).reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let timeline = Unmanaged<Timeline>.fromOpaque(context).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { timeline.append(.gap) }
                else if type == .flagsChanged {
                    let key = event.getIntegerValueField(.keyboardEventKeycode)
                    // Caps Lock・remap 뒤 오른쪽 Control・Windows 전달 때의 오른쪽 Option 만 본다.
                    if key == 57 || key == 62 || key == 61 {
                        let activity = [CGEventType.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
                            .map { CGEventSource.counterForEventType(.hidSystemState, eventType: $0) }
                        timeline.append(.quartz(nanoseconds: event.timestamp, sampledTicks: mach_absolute_time(), key: key, flags: event.flags.rawValue,
                            activity: activity, lastInput: timeline.lastInput))
                        let flag: CGEventFlags = key == 57 ? .maskAlphaShift : key == 62 ? .maskControl : .maskAlternate
                        if !event.flags.contains(flag) { timeline.releasedAt = event.timestamp }
                    }
                } else {
                    // keyCode·Unicode field 는 조회하지 않는다. 출력도 Caps Lock 에 인접한 간격뿐이다.
                    timeline.input(at: event.timestamp)
                }
                // listenOnly 이며 원본을 그대로 돌려준다.
                return Unmanaged.passUnretained(event)
            }, userInfo: context), let runSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            write("BLOCKED: passive Quartz observer could not be created."); exit(2)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), runSource, .defaultMode)
        defer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runSource, .defaultMode)
            CFMachPortInvalidate(tap)
        }

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDDeviceUsagePageKey: 1, kIOHIDDeviceUsageKey: 6] as CFDictionary)
        IOHIDManagerSetInputValueMatching(manager, [kIOHIDElementUsagePageKey: 7, kIOHIDElementUsageKey: 0x39] as CFDictionary)
        IOHIDManagerRegisterInputValueCallback(manager, { context, result, _, value in
            guard result == kIOReturnSuccess, let context else { return }
            let element = IOHIDValueGetElement(value)
            guard IOHIDElementGetUsagePage(element) == 7, IOHIDElementGetUsage(element) == 0x39 else { return }
            let device = IOHIDElementGetDevice(element)
            Unmanaged<Timeline>.fromOpaque(context).takeUnretainedValue().append(
                .hid(ticks: IOHIDValueGetTimeStamp(value), down: IOHIDValueGetIntegerValue(value) != 0, device: device))
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let opened = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        write("physicalHID=\(opened == kIOReturnSuccess ? "available" : "BLOCKED(\(opened))") quartz=listenOnly location=session")
        defer {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            if opened == kIOReturnSuccess { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }
        }

        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let secondsPerTick = Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
        let began = Double(mach_absolute_time()) * secondsPerTick
        var physical = 0
        var quartz = 0
        var previousActivity: [UInt32]?
        var pressedAt: [Int64: UInt64] = [:]
        var gaps = 0
        write("Time origin: \(formatter.string(from: Date())) (event times below are seconds from this origin)")
        write("READY: press/release Caps Lock in your usual app. Missing samples alone do not prove a keyboard fault.")
        write("Results will be printed after collection ends; no output or context queries run during collection.")
        while Double(mach_absolute_time()) * secondsPerTick - began < Double(seconds) {
            CFRunLoopRunInMode(.defaultMode, 0.1, true)
        }
        // callback 과 같은 run loop 를 외부 질의나 stdout 으로 막지 않는다. 관찰을 멈춘 뒤 출력한다.
        CGEvent.tapEnable(tap: tap, enable: false)
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        write("appAtEnd=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown") source=\(sourceID()) capsMapping=\(capsMapping())")
        // app 은 시작·종료 때의 snapshot 이다. 각 event 의 client 를 단정하지 않는다.
        for sample in timeline.drain() {
            switch sample {
            case .hid(let ticks, let down, let device):
                guard Double(ticks) * secondsPerTick >= began else { continue }
                physical += 1
                let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString).map(String.init(describing:)) ?? "unknown"
                write(String(format: "%.6f HID CapsLock %@ device=%@", Double(ticks) * secondsPerTick - began,
                    down ? "down" : "up", product))
            case .quartz(let nanoseconds, let sampledTicks, let key, let flags, let activity, let lastInput):
                quartz += 1
                let name = key == 57 ? "CapsLock" : key == 62 ? "RightControl" : "RightOption"
                let changed = previousActivity.map { $0 != activity }.map(String.init) ?? "unknown"
                let names = ["keyDown", "leftMouseDown", "rightMouseDown", "otherMouseDown", "scrollWheel"]
                let changes = previousActivity.map { before in
                    zip(before, activity).enumerated().compactMap { index, pair in
                        pair.0 == pair.1 ? nil : "\(names[index]):\(pair.1 &- pair.0)"
                    }.joined(separator: ",")
                } ?? "unknown"
                previousActivity = activity
                let flag: CGEventFlags = key == 57 ? .maskAlphaShift : key == 62 ? .maskControl : .maskAlternate
                let down = CGEventFlags(rawValue: flags).contains(flag)
                var detail = ""
                if down { pressedAt[key] = nanoseconds }
                else if let beganPress = pressedAt.removeValue(forKey: key) {
                    let during = lastInput.map { $0 >= beganPress && $0 <= nanoseconds } ?? false
                    detail = " observedInputDuringPress=\(during)"
                }
                let lag = (Double(sampledTicks) * secondsPerTick - Double(nanoseconds) / 1_000_000_000) * 1000
                write(String(format: "%.6f Quartz %@ flags=0x%llx activityChanged=%@ changes=%@%@ counterSampleLagMs=%.3f",
                    Double(nanoseconds) / 1_000_000_000 - began, name, flags, changed, changes, detail, lag))
            case .followingInput(let gap):
                write(String(format: "nextInputAfterReleaseMs=%.3f", gap))
            case .gap:
                gaps += 1
                write("GAP: Quartz observer disabled; this interval cannot diagnose missing events.")
            }
        }
        write("Finished: physicalSamples=\(physical) quartzSamples=\(quartz) dropped=\(timeline.dropped) gaps=\(gaps)")
        if physical == 0 || quartz == 0 || timeline.dropped > 0 || gaps > 0 {
            write("INCOMPLETE: a channel has no samples or observation was interrupted; do not infer a keyboard fault or a passing test.")
        }
    }
}
