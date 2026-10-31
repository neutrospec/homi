import AppKit
import Carbon
import Foundation

/// TIS Get 은 소유권을 넘기지 않는다. NULL 과 잘못된 CF 타입을 false·빈 문자열에 합치지 않는다.
private func snapshotProperty(_ source: TISInputSource, _ key: CFString) -> CFTypeRef? {
    guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
    return Unmanaged<CFTypeRef>.fromOpaque(raw).takeUnretainedValue()
}

func snapshotStringValue(_ value: CFTypeRef?) -> SnapshotResult<String> {
    guard let value else { return .unavailable("property_missing_or_invalid") }
    guard CFGetTypeID(value) == CFStringGetTypeID(), let text = value as? String else { return .unavailable("type_mismatch") }
    return .ok(text)
}

func snapshotBooleanValue(_ value: CFTypeRef?) -> SnapshotResult<Bool> {
    guard let value else { return .unavailable("property_missing_or_invalid") }
    guard CFGetTypeID(value) == CFBooleanGetTypeID(), let flag = value as? Bool else { return .unavailable("type_mismatch") }
    return .ok(flag)
}

private func snapshotStringProperty(_ source: TISInputSource, _ key: CFString) -> SnapshotResult<String> {
    snapshotStringValue(snapshotProperty(source, key))
}
private func snapshotBooleanProperty(_ source: TISInputSource, _ key: CFString) -> SnapshotResult<Bool> {
    snapshotBooleanValue(snapshotProperty(source, key))
}

private func snapshotSourceID(_ source: Unmanaged<TISInputSource>?) -> SnapshotResult<String> {
    guard let source else { return .unavailable("copy_returned_nil") }
    return snapshotStringProperty(source.takeRetainedValue(), kTISPropertyInputSourceID)
}

private func snapshotSources(_ id: String) -> SnapshotResult<[SnapshotSource]> {
    let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
    guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() else { return snapshotSourceResults(nil) }
    var matches: [SnapshotSource] = []
    for value in list as NSArray {
        let item = value as CFTypeRef
        guard CFGetTypeID(item) == TISInputSourceGetTypeID() else { return .unavailable("list_item_type_mismatch") }
        // CFTypeID 를 확인한 뒤 Get 규칙으로 빌려 쓴다. Swift class cast 를 가정하지 않는다.
        let raw = Unmanaged.passUnretained(item).toOpaque()
        let source = Unmanaged<TISInputSource>.fromOpaque(raw).takeUnretainedValue()
        matches.append(SnapshotSource(enabled: snapshotBooleanProperty(source, kTISPropertyInputSourceIsEnabled),
            selected: snapshotBooleanProperty(source, kTISPropertyInputSourceIsSelected),
            selectCapableStatic: snapshotBooleanProperty(source, kTISPropertyInputSourceIsSelectCapable)))
    }
    return snapshotSourceResults(matches)
}

func snapshotSourceResults(_ matches: [SnapshotSource]?) -> SnapshotResult<[SnapshotSource]> {
    guard let matches else { return .unavailable("list_returned_nil") }
    if matches.isEmpty { return .init(status: "not_found", value: []) }
    return .init(status: matches.count == 1 ? "ok" : "ambiguous", value: matches,
        reason: matches.count == 1 ? nil : "multiple_matches")
}

private func snapshotFrontmost() -> SnapshotResult<SnapshotFrontApp> {
    guard let app = NSWorkspace.shared.frontmostApplication else { return .unavailable("frontmost_application_nil") }
    let bundle: SnapshotResult<String> = app.bundleIdentifier.map { .ok($0) } ?? .unavailable("bundle_id_missing")
    let pid: SnapshotResult<Int32> = app.processIdentifier > 0 ? .ok(app.processIdentifier) : .unavailable("pid_missing")
    let launch: SnapshotResult<String> = app.launchDate.map { .ok(snapshotTimestamp($0)) } ?? .unavailable("launch_date_missing")
    return .ok(SnapshotFrontApp(bundleID: bundle, pid: pid, launchDate: launch))
}

func liveSnapshotQueries() -> SnapshotQueries {
    SnapshotQueries(now: Date.init, frontApp: snapshotFrontmost,
        keyboardSource: { snapshotSourceID(TISCopyCurrentKeyboardInputSource()) },
        keyboardLayout: { snapshotSourceID(TISCopyCurrentKeyboardLayoutInputSource()) },
        asciiSource: { snapshotSourceID(TISCopyCurrentASCIICapableKeyboardInputSource()) },
        asciiLayout: { snapshotSourceID(TISCopyCurrentASCIICapableKeyboardLayoutInputSource()) },
        secureEventInput: { .ok(IsSecureEventInputEnabled()) },
        sourceByID: snapshotSources, environment: { collectSnapshotEnvironment() })
}
