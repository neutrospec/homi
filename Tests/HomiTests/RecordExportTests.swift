import Darwin
import Foundation
import InputSession
import Testing
@testable import homi

private func withRecordDirectory(_ body: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("homi-기록-export-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory)
}

@Test("같은 초에 기록을 두 번 저장해도 두 파일이 남는다")
func recordExportsSameSecond() throws {
    try withRecordDirectory { directory in
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var recorder = Recorder()
        recorder.record("첫 기록", at: date)
        let first = try writeRecord(entries: recorder.entries, directory: directory, at: date, binaryUUID: "test-uuid", processID: "test")
        recorder.record("둘째 기록", at: date)
        let second = try writeRecord(entries: recorder.entries, directory: directory, at: date, binaryUUID: "test-uuid", processID: "test")
        let firstText = try String(contentsOf: first, encoding: .utf8)
        let secondText = try String(contentsOf: second, encoding: .utf8)
        #expect(first != second)
        #expect(firstText.contains("첫 기록") && !firstText.contains("둘째 기록"))
        #expect(secondText.contains("둘째 기록"))
    }
}

@Test("빈 기록에도 식별 정보와 privacy 설명을 넣는다")
func recordExportEmptyAndMetadata() throws {
    try withRecordDirectory { directory in
        let file = try writeRecord(entries: [], directory: directory, at: Date(timeIntervalSince1970: 0),
                                   binaryUUID: "TEST-UUID", processID: "123-TEST")
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains("친 key 와 조합 결과") && text.contains("주인이 요청"))
        #expect(text.contains("TEST-UUID") && text.contains("123-TEST") && text.hasSuffix("\n"))
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
        #expect(permissions.intValue & 0o777 == 0o600)
    }
}

@Test("기존 suffix 를 건너뛰고 충돌 상한에서는 기존 파일을 보존한다")
func recordExportCollisionLimit() throws {
    try withRecordDirectory { directory in
        let date = Date(timeIntervalSince1970: 0)
        let first = try writeRecord(entries: [], directory: directory, at: date, binaryUUID: "u", processID: "p")
        let stem = first.deletingPathExtension().lastPathComponent
        for index in 1..<100 {
            try "기존 \(index)".write(to: directory.appending(path: "\(stem)-\(index).txt"), atomically: false, encoding: .utf8)
        }
        let before = try Data(contentsOf: first)
        #expect(throws: POSIXError.self) {
            try writeRecord(entries: [], directory: directory, at: date, binaryUUID: "u", processID: "p")
        }
        #expect(try Data(contentsOf: first) == before)
        #expect(try String(contentsOf: directory.appending(path: "\(stem)-99.txt"), encoding: .utf8) == "기존 99")
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 100)
    }
}

@Test("쓰기·닫기·publish 실패 때 기존 파일을 보존하고 임시 파일을 지운다", arguments: ["write", "close", "publish"])
func recordExportFailure(stage: String) throws {
    try withRecordDirectory { directory in
        let date = Date(timeIntervalSince1970: 0)
        let first = try writeRecord(entries: [], directory: directory, at: date, binaryUUID: "u", processID: "p")
        let before = try Data(contentsOf: first)
        var operations = RecordFileOperations()
        var writes = 0
        var publishes = 0
        switch stage {
        case "write":
            operations.write = { fd, bytes in
                writes += 1
                if writes == 1 { return Darwin.write(fd, bytes.baseAddress, min(2, bytes.count)) }
                throw POSIXError(.ENOSPC)
            }
        case "close":
            operations.close = { fd in
                _ = Darwin.close(fd)
                throw POSIXError(.EIO)
            }
        default:
            operations.publish = { _, _ in
                publishes += 1
                throw POSIXError(.EACCES)
            }
        }
        #expect(throws: POSIXError.self) {
            try writeRecord(entries: [], directory: directory, at: date, binaryUUID: "u", processID: "p", operations: operations)
        }
        #expect(try Data(contentsOf: first) == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [first.lastPathComponent])
        if stage == "write" { #expect(writes == 2) }
        if stage == "publish" { #expect(publishes == 1) }
    }
}

@Test("동시 저장도 각 기록을 독립된 파일에 남긴다")
func recordExportConcurrent() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("homi-export-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let date = Date(timeIntervalSince1970: 0)
    let files = try await withThrowingTaskGroup(of: URL.self, returning: [URL].self) { group in
        for index in 0..<12 {
            group.addTask {
                var recorder = Recorder()
                recorder.record("합성 \(index)", at: date)
                return try writeRecord(entries: recorder.entries, directory: directory, at: date, binaryUUID: "u", processID: "p")
            }
        }
        var values: [URL] = []
        for try await value in group { values.append(value) }
        return values
    }
    #expect(Set(files).count == 12)
    let texts = try files.map { try String(contentsOf: $0, encoding: .utf8) }
    for index in 0..<12 { #expect(texts.contains { $0.contains("합성 \(index)\n") }) }
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 12)
}

@Test("기존 이름과 suffix 를 건너뛰어 다음 이름에 쓴다")
func recordExportSkipsExistingSuffixes() throws {
    try withRecordDirectory { directory in
        let date = Date(timeIntervalSince1970: 0)
        let first = try writeRecord(entries: [], directory: directory, at: date, binaryUUID: "u", processID: "p")
        let stem = first.deletingPathExtension().lastPathComponent
        let occupied = directory.appending(path: "\(stem)-1.txt")
        try "기존".write(to: occupied, atomically: false, encoding: .utf8)
        let next = try writeRecord(entries: [], directory: directory, at: date, binaryUUID: "u", processID: "p")
        #expect(next.lastPathComponent == "\(stem)-2.txt")
        #expect(try String(contentsOf: occupied, encoding: .utf8) == "기존")
    }
}

@Test("중단된 write 와 짧은 write 뒤 나머지를 모두 기록한다")
func recordExportInterruptedAndShortWrites() throws {
    try withRecordDirectory { directory in
        var calls = 0
        var operations = RecordFileOperations()
        operations.write = { fd, bytes in
            calls += 1
            if calls == 1 { throw POSIXError(.EINTR) }
            let result = Darwin.write(fd, bytes.baseAddress, min(7, bytes.count))
            if result < 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            return result
        }
        var recorder = Recorder()
        recorder.record("한글 기록", at: Date(timeIntervalSince1970: 0))
        let file = try writeRecord(entries: recorder.entries, directory: directory, at: Date(timeIntervalSince1970: 0),
                                   binaryUUID: "u", processID: "p", operations: operations)
        let contents = try String(contentsOf: file, encoding: .utf8)
        #expect(contents.contains("한글 기록\n"))
        #expect(calls > 2)
    }
}

@Test("directory 자리에 파일이 있으면 실패하고 기존 파일은 보존한다")
func recordExportDirectoryIsFile() throws {
    try withRecordDirectory { directory in
        let occupied = directory.appending(path: "occupied")
        try "기존 자료".write(to: occupied, atomically: false, encoding: .utf8)
        #expect(throws: (any Error).self) {
            try writeRecord(entries: [], directory: occupied, at: Date(timeIntervalSince1970: 0),
                            binaryUUID: "u", processID: "p")
        }
        #expect(try String(contentsOf: occupied, encoding: .utf8) == "기존 자료")
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["occupied"])
    }
}
