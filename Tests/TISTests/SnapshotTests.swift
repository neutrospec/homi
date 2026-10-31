import CoreFoundation
import Foundation
import Testing

@testable import tis

private func emptyEnvironment() -> SnapshotEnvironment {
    let processes = Timed<[SnapshotProcess]>(startedAt: "s", finishedAt: "e", result: .ok([]))
    let disk = Timed<SnapshotDiskIdentity>(startedAt: "s", finishedAt: "e", result: .init(status: "not_found"))
    let caps = Timed<[String]>(startedAt: "s", finishedAt: "e", result: .ok([]))
    return SnapshotEnvironment(processes: processes, loadedUUID: .init(status: "not_collected"),
        installedUser: disk, installedSystem: disk, capsMapping: caps)
}

private final class FakeSnapshot {
    var ticks = 0
    var calls: [String] = []
    var sourceAnswers: [SnapshotResult<String>] = [.ok("abc"), .ok("abc")]
    var frontAnswers: [SnapshotResult<SnapshotFrontApp>] = []
    var parent: SnapshotResult<[SnapshotSource]> = .init(status: "not_found", value: [])
    var mode: SnapshotResult<[SnapshotSource]> = .ok([SnapshotSource(enabled: .ok(true), selected: .ok(false), selectCapableStatic: .ok(true))])
    var keyboardLayout: SnapshotResult<String> = .ok("abc")
    var secure: SnapshotResult<Bool> = .ok(false)
    var environmentValue = emptyEnvironment()
    init() {
        let app = SnapshotFrontApp(bundleID: .ok("example.app"), pid: .ok(42), launchDate: .ok("launch"))
        frontAnswers = [.ok(app), .ok(app)]
    }
    func query(_ name: String) {
        #expect(Thread.isMainThread)
        calls.append(name)
    }
    func inputs() -> SnapshotQueries {
        SnapshotQueries(now: { self.ticks += 1; return Date(timeIntervalSince1970: TimeInterval(self.ticks)) },
            frontApp: { self.query("front"); return self.frontAnswers.removeFirst() },
            keyboardSource: { self.query("source"); return self.sourceAnswers.removeFirst() },
            keyboardLayout: { self.query("layout"); return self.keyboardLayout },
            asciiSource: { self.query("ascii-source"); return .ok("abc") },
            asciiLayout: { self.query("ascii-layout"); return .ok("abc") },
            secureEventInput: { self.query("secure"); return self.secure },
            sourceByID: { id in
                self.query(id.hasSuffix(".korean") ? "mode" : "parent")
                return id.hasSuffix(".korean") ? self.mode : self.parent
            }, environment: { self.query("environment"); return self.environmentValue })
    }
}

@Test("snapshot: main thread 에서 수집 순서·각 관측 시각·비원자성을 보존한다")
func snapshotQueryOrderAndTimes() throws {
    let fake = FakeSnapshot()
    let result = collectSnapshot(fake.inputs())
    #expect(fake.calls == ["front", "source", "layout", "ascii-source", "ascii-layout", "secure", "parent", "mode", "environment", "source", "front"])
    #expect(!result.atomic && !result.partial)
    #expect(result.startedAt < result.before.frontApp.startedAt)
    #expect(result.before.frontApp.startedAt < result.before.frontApp.finishedAt)
    #expect(result.after.frontApp.finishedAt < result.finishedAt)
    #expect(result.boundaryComparison.frontApp == "same_observed_values")
    #expect(result.boundaryComparison.keyboardSource == "same_observed_values")
    let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
    let json = String(decoding: try encoder.encode(result), as: UTF8.self)
    #expect(json.contains("\"schema_version\":1"))
    #expect(json.contains("\"atomic\":false"))
    #expect(json.contains("\"not_collected\""))
    #expect(!json.contains("window_title") && !json.contains("typed_text"))
}

@Test("snapshot: 실패와 정상 빈 목록 및 일부 속성 실패를 구분한다")
func snapshotPartialAndAbsence() {
    let fake = FakeSnapshot()
    fake.parent = .unavailable("list_returned_nil")
    fake.mode = .ok([SnapshotSource(enabled: .unavailable("type_mismatch"), selected: .ok(false), selectCapableStatic: .ok(true))])
    fake.keyboardLayout = .unavailable("copy_returned_nil")
    fake.sourceAnswers = [.ok("abc"), .unavailable("copy_returned_nil")]
    let result = collectSnapshot(fake.inputs())
    #expect(result.partial)
    #expect(result.homi.parent.result.status == "unavailable")
    #expect(result.homi.mode.result.value?.first?.enabled.reason == "type_mismatch")
    #expect(result.homi.mode.result.value?.first?.selected.value == false)
    #expect(result.current.keyboardLayout.result.reason == "copy_returned_nil")
    #expect(result.boundaryComparison.keyboardSource == "unknown")
    #expect(result.environment.loadedUUID.status == "not_collected")
    #expect(snapshotSourceResults(nil).status == "unavailable")
    #expect(snapshotSourceResults([]).status == "not_found")
    let row = SnapshotSource(enabled: .ok(true), selected: .ok(false), selectCapableStatic: .ok(true))
    let ambiguous = snapshotSourceResults([row, row])
    #expect(ambiguous.status == "ambiguous" && ambiguous.value?.count == 2 && ambiguous.isPartial)
}

@Test("snapshot: 전후 값이 바뀌면 표시하고 알 수 없는 값은 동일하다고 하지 않는다")
func snapshotBoundaryChangeAndUnknown() {
    let fake = FakeSnapshot()
    let missing = SnapshotFrontApp(bundleID: .unavailable("bundle_id_missing"), pid: .unavailable("pid_missing"), launchDate: .unavailable("launch_date_missing"))
    fake.frontAnswers = [.ok(missing), .ok(missing)]
    fake.sourceAnswers = [.ok("first"), .ok("second")]
    let result = collectSnapshot(fake.inputs())
    #expect(result.partial)
    #expect(result.boundaryComparison.frontApp == "unknown")
    #expect(result.boundaryComparison.keyboardSource == "changed")
}

@Test("snapshot: CF 속성은 nil·CFBoolean·NSNumber·문자열을 구분한다")
func snapshotCFPropertyTypes() {
    #expect(snapshotBooleanValue(nil).reason == "property_missing_or_invalid")
    #expect(snapshotBooleanValue(kCFBooleanFalse).value == false)
    #expect(snapshotBooleanValue(kCFBooleanTrue).value == true)
    #expect(snapshotBooleanValue(NSNumber(value: 1)).reason == "type_mismatch")
    #expect(snapshotBooleanValue("true" as CFString).reason == "type_mismatch")
    #expect(snapshotStringValue(nil).reason == "property_missing_or_invalid")
    #expect(snapshotStringValue("abc" as CFString).value == "abc")
    #expect(snapshotStringValue(kCFBooleanTrue).reason == "type_mismatch")
}

@Test("snapshot: 여러 homi process 후보는 모두 보존하고 개수만으로 실패라 하지 않는다")
func snapshotMultipleProcesses() {
    let fake = FakeSnapshot()
    let original = fake.environmentValue
    let processes = [
        SnapshotProcess(pid: .ok(101), launchDate: .ok("start-a"), executableURL: .ok("file:///homi-a"), isTerminated: false),
        SnapshotProcess(pid: .ok(202), launchDate: .ok("start-b"), executableURL: .ok("file:///homi-b"), isTerminated: false),
    ]
    fake.environmentValue = SnapshotEnvironment(
        processes: Timed(startedAt: "s", finishedAt: "e", result: .ok(processes)),
        loadedUUID: .init(status: "not_collected"), installedUser: original.installedUser,
        installedSystem: original.installedSystem, capsMapping: original.capsMapping)
    let result = collectSnapshot(fake.inputs())
    #expect(!result.partial)
    #expect(result.environment.processes.result.value?.count == 2)
    #expect(result.environment.processes.result.value?.map { $0.pid.value } == [101, 202])
}
