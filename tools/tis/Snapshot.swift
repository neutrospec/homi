import Foundation

/// nil·false·빈 목록을 혼동하지 않는 JSON 관측값.
struct SnapshotResult<Value: Codable>: Codable {
    let status: String
    let value: Value?
    let reason: String?
    init(status: String, value: Value? = nil, reason: String? = nil) {
        self.status = status; self.value = value; self.reason = reason
    }
    private enum CodingKeys: String, CodingKey { case status, value, reason }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encode(value, forKey: .value)
        try container.encode(reason, forKey: .reason)
    }
    static func ok(_ value: Value) -> Self { .init(status: "ok", value: value) }
    static func unavailable(_ reason: String) -> Self { .init(status: "unavailable", reason: reason) }
    var isPartial: Bool { !["ok", "not_found", "not_collected"].contains(status) }
}

struct Timed<Value: Codable>: Codable {
    let startedAt: String
    let finishedAt: String
    let result: SnapshotResult<Value>
}

struct SnapshotFrontApp: Codable {
    let bundleID: SnapshotResult<String>
    let pid: SnapshotResult<Int32>
    let launchDate: SnapshotResult<String>
    var isPartial: Bool { bundleID.isPartial || pid.isPartial || launchDate.isPartial }
}

struct SnapshotSource: Codable {
    let enabled: SnapshotResult<Bool>
    let selected: SnapshotResult<Bool>
    let selectCapableStatic: SnapshotResult<Bool>
    var isPartial: Bool { enabled.isPartial || selected.isPartial || selectCapableStatic.isPartial }
}

struct SnapshotBoundary: Codable {
    let frontApp: Timed<SnapshotFrontApp>
    let keyboardSource: Timed<String>
}

struct SnapshotCurrent: Codable {
    let keyboardLayout: Timed<String>
    let asciiSource: Timed<String>
    let asciiLayout: Timed<String>
    let secureEventInput: Timed<Bool>
}

struct SnapshotHomi: Codable {
    let parent: Timed<[SnapshotSource]>
    let mode: Timed<[SnapshotSource]>
}

struct SnapshotComparison: Codable {
    let frontApp: String
    let keyboardSource: String
}

struct AvailabilitySnapshot: Encodable {
    let schemaVersion = 1
    let atomic = false
    let startedAt: String
    let before: SnapshotBoundary
    let current: SnapshotCurrent
    let homi: SnapshotHomi
    let environment: SnapshotEnvironment
    let after: SnapshotBoundary
    let boundaryComparison: SnapshotComparison
    let finishedAt: String
    let partial: Bool
}

/// 모든 외부 조회는 동기 단발 호출이다. 실제 구현도 main thread 에서만 실행한다.
struct SnapshotQueries {
    var now: () -> Date
    var frontApp: () -> SnapshotResult<SnapshotFrontApp>
    var keyboardSource: () -> SnapshotResult<String>
    var keyboardLayout: () -> SnapshotResult<String>
    var asciiSource: () -> SnapshotResult<String>
    var asciiLayout: () -> SnapshotResult<String>
    var secureEventInput: () -> SnapshotResult<Bool>
    var sourceByID: (String) -> SnapshotResult<[SnapshotSource]>
    var environment: () -> SnapshotEnvironment
}

func snapshotTimestamp(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

func collectSnapshot(_ queries: SnapshotQueries) -> AvailabilitySnapshot {
    func timed<T: Codable>(_ read: () -> SnapshotResult<T>) -> Timed<T> {
        let start = snapshotTimestamp(queries.now())
        let value = read()
        return Timed(startedAt: start, finishedAt: snapshotTimestamp(queries.now()), result: value)
    }
    let start = snapshotTimestamp(queries.now())
    let before = SnapshotBoundary(frontApp: timed(queries.frontApp), keyboardSource: timed(queries.keyboardSource))
    let current = SnapshotCurrent(keyboardLayout: timed(queries.keyboardLayout), asciiSource: timed(queries.asciiSource),
        asciiLayout: timed(queries.asciiLayout), secureEventInput: timed(queries.secureEventInput))
    let homi = SnapshotHomi(parent: timed { queries.sourceByID("com.unocult.inputmethod.homi") },
        mode: timed { queries.sourceByID("com.unocult.inputmethod.homi.korean") })
    let environment = queries.environment()
    let afterSource = timed(queries.keyboardSource)
    let afterFront = timed(queries.frontApp)
    let after = SnapshotBoundary(frontApp: afterFront, keyboardSource: afterSource)
    let end = snapshotTimestamp(queries.now())
    func compare<T: Equatable & Codable>(_ a: SnapshotResult<T>, _ b: SnapshotResult<T>) -> String {
        guard a.status == "ok", b.status == "ok", let x = a.value, let y = b.value else { return "unknown" }
        return x == y ? "same_observed_values" : "changed"
    }
    func frontPartial(_ value: SnapshotResult<SnapshotFrontApp>) -> Bool { value.isPartial || (value.value?.isPartial ?? false) }
    func sourcesPartial(_ value: SnapshotResult<[SnapshotSource]>) -> Bool {
        value.isPartial || (value.value?.contains(where: \.isPartial) ?? false)
    }
    let frontCompare: String
    if let a = before.frontApp.result.value, let b = after.frontApp.result.value,
       before.frontApp.result.status == "ok", after.frontApp.result.status == "ok" {
        let comparisons = [compare(a.bundleID, b.bundleID), compare(a.pid, b.pid), compare(a.launchDate, b.launchDate)]
        frontCompare = comparisons.contains("changed") ? "changed" : comparisons.contains("unknown") ? "unknown" : "same_observed_values"
    } else { frontCompare = "unknown" }
    let partial = frontPartial(before.frontApp.result) || before.keyboardSource.result.isPartial
        || current.keyboardLayout.result.isPartial || current.asciiSource.result.isPartial
        || current.asciiLayout.result.isPartial || current.secureEventInput.result.isPartial
        || sourcesPartial(homi.parent.result) || sourcesPartial(homi.mode.result) || environment.isPartial
        || frontPartial(after.frontApp.result) || after.keyboardSource.result.isPartial
    return AvailabilitySnapshot(startedAt: start, before: before, current: current, homi: homi,
        environment: environment, after: after,
        boundaryComparison: SnapshotComparison(frontApp: frontCompare, keyboardSource: compare(before.keyboardSource.result, after.keyboardSource.result)),
        finishedAt: end, partial: partial)
}
