import Foundation
import Testing
@testable import tis

private func withEnvironmentFixture(_ body: (URL) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "homi-snapshot-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    try body(root)
}

@Test("HID mapping 은 Caps 항목만 남기고 nil 과 잘못된 형식을 구분한다")
func environmentMapping() {
    let raw: [[String: Any]] = [
        ["HIDKeyboardModifierMappingSrc": NSNumber(value: UInt64(0x700000004)), "HIDKeyboardModifierMappingDst": NSNumber(value: 3)],
        ["HIDKeyboardModifierMappingSrc": NSNumber(value: UInt64(0x700000039)), "HIDKeyboardModifierMappingDst": NSNumber(value: UInt64(0x7000000e4))],
    ]
    let result = environmentCapsMapping(raw)
    #expect(result.status == "ok" && result.value == ["0x7000000e4"])
    #expect(environmentCapsMapping([]).value == [])
    #expect(environmentCapsMapping(nil).status == "unavailable")
    #expect(environmentCapsMapping("bad").status == "error")
    #expect(environmentCapsMapping([["HIDKeyboardModifierMappingSrc": true]]).status == "error")
    #expect(environmentCapsMapping([["HIDKeyboardModifierMappingSrc": NSNumber(value: UInt64(0x700000039)), "HIDKeyboardModifierMappingDst": 3.5]]).status == "error")
    #expect(environmentCapsMapping([["HIDKeyboardModifierMappingSrc": NSNumber(value: UInt64(0x700000039))]]).status == "error")
}

@Test("disk UUID 와 CDHash parser 는 형식 오류를 거부한다")
func environmentParsers() {
    let valid = "UUID: 12345678-1234-1234-1234-123456789ABC (arm64) /synthetic/homi\n"
    #expect(environmentParseUUIDs(valid) == [SnapshotMachUUID(architecture: "arm64", uuid: "12345678-1234-1234-1234-123456789ABC")])
    #expect(environmentParseUUIDs("UUID: invalid (arm64)") == nil)
    #expect(environmentParseUUIDs("") == nil)
    #expect(environmentParseUUIDs(valid + valid) == nil)
    #expect(environmentParseUUIDs(valid + valid.replacingOccurrences(of: "(arm64)", with: "(x86_64)")) == nil)
    let hash = String(repeating: "a", count: 40)
    #expect(environmentParseCDHash("info\nCDHash=\(hash)\n") == hash)
    #expect(environmentParseCDHash("CDHash=bad") == nil)
    #expect(environmentParseCDHash("CDHash=\(hash)\nCDHash=\(hash)") == nil)
}

@Test("없는 설치본과 도구 오류는 별도로 표시한다")
func environmentDiskErrors() throws {
    try withEnvironmentFixture { root in
        let bundle = root.appending(path: "homi.app")
        #expect(environmentDiskIdentity(bundle: bundle).status == "not_found")
        let executable = bundle.appending(path: "Contents/MacOS/homi")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("synthetic".utf8).write(to: executable)
        let result = environmentDiskIdentity(bundle: bundle) { tool, _ in
            tool.hasSuffix("dwarfdump") ? .init(status: "timeout", output: nil) : .init(status: "exit_failure", output: nil)
        }
        #expect(result.status == "ok")
        #expect(result.value?.onDiskUUIDs.status == "timeout")
        #expect(result.value?.onDiskCDHash.status == "error")
        #expect(result.value?.onDiskCDHash.reason == "exit_failure")
    }
}

@Test("disk 결과의 교체와 출력 오류를 구분한다")
func environmentDiskChangeAndFormat() throws {
    try withEnvironmentFixture { root in
        let bundle = root.appending(path: "homi.app")
        let executable = bundle.appending(path: "Contents/MacOS/homi")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("synthetic".utf8).write(to: executable)
        let result = environmentDiskIdentity(bundle: bundle) { _, _ in
            try! Data("changed size".utf8).write(to: executable)
            return .init(status: "ok", output: "invalid")
        }
        #expect(result.status == "changed")
        #expect(result.value?.onDiskUUIDs.reason == "uuid_format")
        #expect(result.value?.onDiskCDHash.reason == "cdhash_format")
    }
}

@Test("child timeout 과 출력 상한 및 실행 실패를 구분한다")
func environmentCommandFailures() {
    #expect(environmentRunCommand("/bin/sleep", arguments: ["3"], timeout: 0.05).status == "timeout")
    #expect(environmentRunCommand("/usr/bin/yes", arguments: [], timeout: 2, outputLimit: 1024).status == "output_limit")
    #expect(environmentRunCommand("/bin/sh", arguments: ["-c", "while :; do printf abc; printf def >&2; done"], timeout: 2, outputLimit: 1024).status == "output_limit")
    #expect(environmentRunCommand("/no/such/snapshot-tool", arguments: []).status == "spawn_error")
    #expect(environmentRunCommand("/usr/bin/false", arguments: []).status == "exit_failure")
    #expect(environmentRunCommand("/bin/sleep", arguments: ["3"], preparePipe: { _ in false }).status == "pipe_setup_error")
}

@Test("실행 image 미수집과 disk identity 는 구분하고 부재는 부분 실패가 아니다")
func environmentLoadedIdentitySeparate() throws {
    let hash = String(repeating: "a", count: 40)
    let disk = SnapshotDiskIdentity(bundlePath: "/synthetic/homi.app", executablePath: "/synthetic/homi",
        onDiskUUIDs: .init(status: "ok", value: [.init(architecture: "arm64", uuid: "12345678-1234-1234-1234-123456789ABC")]),
        onDiskCDHash: .init(status: "ok", value: hash), cdHashArchitecture: "host_native", consistency: "unchanged_observed")
    let environment = SnapshotEnvironment(
        processes: .init(startedAt: "a", finishedAt: "b", result: .init(status: "ok", value: [])),
        loadedUUID: .init(status: "not_collected", reason: "loaded_image_not_inspected"),
        installedUser: .init(startedAt: "a", finishedAt: "b", result: .init(status: "ok", value: disk)),
        installedSystem: .init(startedAt: "a", finishedAt: "b", result: .init(status: "not_found")),
        capsMapping: .init(startedAt: "a", finishedAt: "b", result: .init(status: "ok", value: [])))
    #expect(!environment.isPartial)
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let json = try encoder.encode(environment)
    let object = try #require(try JSONSerialization.jsonObject(with: json) as? [String: Any])
    let loaded = try #require(object["loaded_uuid"] as? [String: Any])
    #expect(loaded["status"] as? String == "not_collected")
    let user = try #require(object["installed_user"] as? [String: Any])
    let result = try #require(user["result"] as? [String: Any])
    let value = try #require(result["value"] as? [String: Any])
    #expect(value["on_disk_uuids"] != nil)
    #expect(value["on_disk_cd_hash"] != nil)
}
