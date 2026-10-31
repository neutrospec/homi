import AppKit
import Carbon
import Darwin
import Foundation
import IOKit.hid
import IOKit.hidsystem

struct SnapshotProcess: Codable {
    let pid: SnapshotResult<Int32>
    let launchDate: SnapshotResult<String>
    let executableURL: SnapshotResult<String>
    let isTerminated: Bool
    var isPartial: Bool { pid.isPartial || launchDate.isPartial || executableURL.isPartial || isTerminated }
}

struct SnapshotMachUUID: Codable, Equatable {
    let architecture: String
    let uuid: String
}

struct SnapshotDiskIdentity: Codable {
    let bundlePath: String
    let executablePath: String
    let onDiskUUIDs: SnapshotResult<[SnapshotMachUUID]>
    let onDiskCDHash: SnapshotResult<String>
    /// codesign display 의 기본 architecture 는 실행 host 의 native architecture 다.
    let cdHashArchitecture: String
    let consistency: String

    // 자동 snake case 는 UUIDs 를 uui_ds 로 나눈다. 공개 JSON key 는 고정한다.
    private enum CodingKeys: String, CodingKey {
        case bundlePath, executablePath, onDiskCDHash, cdHashArchitecture, consistency
        case onDiskUUIDs = "on_disk_uuids"
    }
}

struct SnapshotEnvironment: Codable {
    var processLookup = "NSRunningApplication.runningApplications(withBundleIdentifier:)"
    var processScope = "candidates_only"
    let processes: Timed<[SnapshotProcess]>
    let loadedUUID: SnapshotResult<String>
    let installedUser: Timed<SnapshotDiskIdentity>
    let installedSystem: Timed<SnapshotDiskIdentity>
    let capsMapping: Timed<[String]>

    var isPartial: Bool {
        loadedUUID.isPartial || processes.result.isPartial || (processes.result.value?.contains(where: \.isPartial) ?? false)
            || installedUser.result.isPartial || installedSystem.result.isPartial || capsMapping.result.isPartial
            || [installedUser.result.value, installedSystem.result.value].compactMap { $0 }.contains {
                $0.onDiskUUIDs.isPartial || $0.onDiskCDHash.isPartial || $0.consistency != "unchanged_observed"
            }
    }
}

private func environmentTime() -> String {
    snapshotTimestamp(Date())
}

private func environmentTimed<T: Codable>(_ body: () -> SnapshotResult<T>) -> Timed<T> {
    let start = environmentTime()
    let result = body()
    return Timed(startedAt: start, finishedAt: environmentTime(), result: result)
}

/// 제한된 두 도구에만 쓰는 동기 child runner. stderr 는 결과에 내보내지 않는다.
struct EnvironmentCommandResult {
    let status: String
    let output: String?
}

private func environmentPreparePipe(_ fd: Int32) -> Bool {
    let flags = fcntl(fd, F_GETFL)
    return flags >= 0 && fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0
}

func environmentRunCommand(_ executable: String, arguments: [String], timeout: TimeInterval = 2,
                           outputLimit: Int = 65536, preparePipe: @MainActor (Int32) -> Bool = environmentPreparePipe) -> EnvironmentCommandResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardInput = FileHandle.nullDevice
    let output = Pipe(), errors = Pipe()
    process.standardOutput = output
    process.standardError = errors
    do { try process.run() } catch { return .init(status: "spawn_error", output: nil) }
    try? output.fileHandleForWriting.close()
    try? errors.fileHandleForWriting.close()
    let descriptors = [output.fileHandleForReading.fileDescriptor, errors.fileHandleForReading.fileDescriptor]
    defer { try? output.fileHandleForReading.close(); try? errors.fileHandleForReading.close() }
    for fd in descriptors {
        guard preparePipe(fd) else {
            if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            return .init(status: "pipe_setup_error", output: nil)
        }
    }
    let start = ProcessInfo.processInfo.systemUptime
    var streams = [Data(), Data()], total = 0
    var ended = [false, false]
    var stop: String?
    while true {
        for (index, fd) in descriptors.enumerated() where !ended[index] {
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = Darwin.read(fd, &buffer, buffer.count)
                if count > 0 {
                    total += count
                    if total > outputLimit { stop = "output_limit"; break }
                    streams[index].append(contentsOf: buffer.prefix(count))
                } else if count == 0 {
                    ended[index] = true
                    break
                } else if errno == EINTR {
                    continue
                } else if errno == EAGAIN || errno == EWOULDBLOCK {
                    break
                } else {
                    stop = "read_error"
                    break
                }
            }
            if stop != nil { break }
        }
        if stop != nil { break }
        if !process.isRunning && ended.allSatisfy({ $0 }) { break }
        if ProcessInfo.processInfo.systemUptime - start >= timeout { stop = "timeout"; break }
        usleep(10_000)
    }
    if stop != nil && process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
    process.waitUntilExit()
    if let stop { return .init(status: stop, output: nil) }
    guard process.terminationStatus == 0 else { return .init(status: "exit_failure", output: nil) }
    guard let stdout = String(data: streams[0], encoding: .utf8),
          let stderr = String(data: streams[1], encoding: .utf8) else {
        return .init(status: "encoding_error", output: nil)
    }
    // codesign display 는 stderr 에 결과를 쓴다. 파싱 결과만 외부에 내보낸다.
    return .init(status: "ok", output: stdout + "\n" + stderr)
}

func environmentParseUUIDs(_ text: String) -> [SnapshotMachUUID]? {
    let expression = try! NSRegularExpression(pattern: #"^UUID: ([0-9A-Fa-f-]{36}) \(([^)]+)\)(?:\s|$)"#)
    var result: [SnapshotMachUUID] = []
    for line in text.split(whereSeparator: \.isNewline) {
        let string = String(line), range = NSRange(string.startIndex..., in: string)
        guard let match = expression.firstMatch(in: string, range: range),
              let idRange = Range(match.range(at: 1), in: string),
              let archRange = Range(match.range(at: 2), in: string),
              let uuid = UUID(uuidString: String(string[idRange])) else { return nil }
        let architecture = String(string[archRange])
        guard !result.contains(where: { $0.architecture == architecture || $0.uuid == uuid.uuidString }) else { return nil }
        result.append(.init(architecture: architecture, uuid: uuid.uuidString))
    }
    return result.isEmpty ? nil : result
}

func environmentParseCDHash(_ text: String) -> String? {
    let expression = try! NSRegularExpression(pattern: #"^CDHash=([0-9a-fA-F]{40})$"#)
    let matches = text.split(whereSeparator: \.isNewline).compactMap { line -> String? in
        let string = String(line)
        guard let m = expression.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)),
              let range = Range(m.range(at: 1), in: string) else { return nil }
        return String(string[range]).lowercased()
    }
    return matches.count == 1 ? matches[0] : nil
}

/// nil·형식 오류와 정상적인 빈 mapping 은 구분한다.
func environmentCapsMapping(_ raw: Any?) -> SnapshotResult<[String]> {
    guard let raw else { return .init(status: "unavailable", reason: "property_null") }
    guard let entries = raw as? [[String: Any]] else { return .init(status: "error", reason: "mapping_format") }
    func integer(_ value: Any?) -> NSNumber? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              !["f", "d"].contains(String(cString: number.objCType)),
              number.compare(NSNumber(value: 0)) != .orderedAscending else { return nil }
        return number
    }
    var values: [String] = []
    for entry in entries {
        guard let source = integer(entry["HIDKeyboardModifierMappingSrc"]) else {
            return .init(status: "error", reason: "mapping_format")
        }
        if source.uint64Value == 0x700000039 {
            guard let destination = integer(entry["HIDKeyboardModifierMappingDst"]) else {
                return .init(status: "error", reason: "mapping_format")
            }
            values.append(String(format: "0x%llx", destination.uint64Value))
        }
    }
    return .init(status: "ok", value: values)
}

private struct EnvironmentFileStamp: Equatable {
    let device: NSNumber
    let inode: NSNumber
    let size: NSNumber
    let modified: Date
}
private func environmentStamp(_ url: URL) throws -> EnvironmentFileStamp {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    guard let device = attributes[.systemNumber] as? NSNumber,
          let inode = attributes[.systemFileNumber] as? NSNumber,
          let size = attributes[.size] as? NSNumber,
          let modified = attributes[.modificationDate] as? Date else { throw CocoaError(.fileReadUnknown) }
    return .init(device: device, inode: inode, size: size, modified: modified)
}

private func environmentMissingFile(_ error: NSError) -> Bool {
    if error.domain == NSPOSIXErrorDomain && (error.code == Int(ENOENT) || error.code == Int(ENOTDIR)) { return true }
    if error.domain == NSCocoaErrorDomain && (error.code == NSFileReadNoSuchFileError || error.code == NSFileNoSuchFileError) { return true }
    if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError { return environmentMissingFile(underlying) }
    return false
}

func environmentDiskIdentity(bundle: URL,
                             runner: (String, [String]) -> EnvironmentCommandResult = { environmentRunCommand($0, arguments: $1) }) -> SnapshotResult<SnapshotDiskIdentity> {
    let executable = bundle.appending(path: "Contents/MacOS/homi")
    let bundleBefore: EnvironmentFileStamp
    let before: EnvironmentFileStamp
    do {
        bundleBefore = try environmentStamp(bundle)
        before = try environmentStamp(executable)
        let handle = try FileHandle(forReadingFrom: executable)
        try handle.close()
    } catch {
        if environmentMissingFile(error as NSError) {
            return .init(status: "not_found", reason: "bundle_or_executable_missing")
        }
        return .init(status: "error", reason: "bundle_or_executable_unreadable")
    }
    let uuidCommand = runner("/usr/bin/dwarfdump", ["--uuid", executable.path])
    let hashCommand = runner("/usr/bin/codesign", ["--display", "--verbose=4", executable.path])
    let uuids: SnapshotResult<[SnapshotMachUUID]>
    if uuidCommand.status != "ok" { uuids = .init(status: uuidCommand.status == "timeout" ? "timeout" : "error", reason: uuidCommand.status) }
    else if let output = uuidCommand.output, let parsed = environmentParseUUIDs(output) { uuids = .init(status: "ok", value: parsed) }
    else { uuids = .init(status: "error", reason: "uuid_format") }
    let hash: SnapshotResult<String>
    if hashCommand.status != "ok" { hash = .init(status: hashCommand.status == "timeout" ? "timeout" : "error", reason: hashCommand.status) }
    else if let output = hashCommand.output, let parsed = environmentParseCDHash(output) { hash = .init(status: "ok", value: parsed) }
    else { hash = .init(status: "error", reason: "cdhash_format") }
    let consistency: String
    do { consistency = try environmentStamp(bundle) == bundleBefore && environmentStamp(executable) == before ? "unchanged_observed" : "changed_during_collection" }
    catch { consistency = "unknown" }
    let status = consistency == "unchanged_observed" ? "ok" : (consistency == "unknown" ? "unavailable" : "changed")
    return .init(status: status, value: .init(
        bundlePath: bundle.path, executablePath: executable.path, onDiskUUIDs: uuids, onDiskCDHash: hash,
        cdHashArchitecture: "host_native", consistency: consistency))
}

@MainActor func collectSnapshotEnvironment() -> SnapshotEnvironment {
    let processes: Timed<[SnapshotProcess]> = environmentTimed {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.unocult.inputmethod.homi")
        return .init(status: "ok", value: apps.map { app in
            let pid: SnapshotResult<Int32> = app.processIdentifier > 0
                ? .init(status: "ok", value: app.processIdentifier) : .init(status: "unavailable", reason: "invalid_pid")
            let launch: SnapshotResult<String>
            if let date = app.launchDate {
                launch = .ok(snapshotTimestamp(date))
            } else { launch = .init(status: "unavailable", reason: "launch_date_unavailable") }
            let executable: SnapshotResult<String>
            if let url = app.executableURL { executable = .init(status: "ok", value: url.absoluteString) }
            else { executable = .init(status: "unavailable", reason: "executable_url_unavailable") }
            return .init(pid: pid, launchDate: launch, executableURL: executable, isTerminated: app.isTerminated)
        })
    }
    let user = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Input Methods/homi.app")
    let system = URL(fileURLWithPath: "/Library/Input Methods/homi.app")
    let userDisk = environmentTimed { environmentDiskIdentity(bundle: user) }
    let systemDisk = environmentTimed { environmentDiskIdentity(bundle: system) }
    let mapping: Timed<[String]> = environmentTimed {
        let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        return environmentCapsMapping(IOHIDEventSystemClientCopyProperty(client, kIOHIDUserKeyUsageMapKey as CFString))
    }
    return .init(processes: processes, loadedUUID: .init(status: "not_collected", reason: "loaded_image_not_inspected"),
                 installedUser: userDisk, installedSystem: systemDisk, capsMapping: mapping)
}
