import Darwin
import Foundation
import InputSession
import Synchronization
import os

/// os log 에는 입력 내용을 남기지 않는다 — 상태 전이와 bundle ID 까지만.
nonisolated let log = Logger(subsystem: "com.unocult.inputmethod.homi", category: "lifecycle")

/// 최근 일의 기록 — memory 에만. input menu 의 "최근 key 기록 저장" 으로만 file 이 된다.
nonisolated let recorder = Mutex(Recorder())

nonisolated func record(_ event: String) {
    recorder.withLock { $0.record(event) }
}

/// 기록을 ~/Library/Logs/homi/ 에 쓰고 그 경로를 돌려준다.
nonisolated func saveRecord() throws -> URL {
    let entries = recorder.withLock { $0.entries }
    let directory = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/homi")
    return try writeRecord(entries: entries, directory: directory, at: Date(),
                           binaryUUID: BinaryIdentity.current, processID: ControllerTraceID.process)
}

/// 파일 처리 실패를 test 에서 주입한다. 각 closure 는 호출한 syscall 의 오류를 그대로 던진다.
nonisolated struct RecordFileOperations {
    var write: (Int32, UnsafeRawBufferPointer) throws -> Int = { fd, bytes in
        let count = Darwin.write(fd, bytes.baseAddress, bytes.count)
        if count < 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        return count
    }
    var close: (Int32) throws -> Void = { fd in
        if Darwin.close(fd) != 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
    var publish: (String, String) throws -> Void = { source, destination in
        if renamex_np(source, destination, UInt32(RENAME_EXCL)) != 0 {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}

/// 완성한 파일만 이름에 공개한다. 기존 파일은 절대 덮어쓰지 않는다.
nonisolated func writeRecord(entries: [Recorder.Entry], directory: URL, at date: Date,
                             binaryUUID: String, processID: String,
                             operations: RecordFileOperations = RecordFileOperations()) throws -> URL {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let clock = DateFormatter()
    clock.locale = Locale(identifier: "en_US_POSIX")
    clock.dateFormat = "HH:mm:ss.SSS"
    let lines = entries.map { "\(clock.string(from: $0.time))  \($0.event)" }
    let header = "# homi 최근 기록 — 친 key 와 조합 결과가 들어 있다. 주인이 요청해서 저장했다."
    let metadata = "# executable UUID: \(binaryUUID) · process: \(processID)"
    let data = Data(([header, metadata] + lines).joined(separator: "\n").appending("\n").utf8)
    clock.dateFormat = "yyyy-MM-dd'T'HHmmss"
    let stem = "record-\(clock.string(from: date))"
    var template = Array(directory.appending(path: ".homi-record-XXXXXX").path.utf8CString)
    var descriptor = mkstemp(&template)
    guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    let temporary = String(decoding: template.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    defer {
        if descriptor >= 0 { _ = Darwin.close(descriptor) }
        _ = unlink(temporary)
    }
    try data.withUnsafeBytes { bytes in
        var offset = 0
        while offset < bytes.count {
            do {
                let written = try operations.write(descriptor, UnsafeRawBufferPointer(rebasing: bytes[offset...]))
                guard written > 0 && written <= bytes.count - offset else { throw POSIXError(.EIO) }
                offset += written
            } catch let error as POSIXError where error.code == .EINTR {
                continue
            }
        }
    }
    let closing = descriptor
    descriptor = -1 // close 실패에도 동일 descriptor 를 다시 닫지 않는다.
    try operations.close(closing)
    for index in 0..<100 {
        let suffix = index == 0 ? "" : "-\(index)"
        let destination = directory.appending(path: "\(stem)\(suffix).txt")
        do {
            try operations.publish(temporary, destination.path)
            return destination
        } catch let error as POSIXError where error.code == .EEXIST {
            continue
        }
    }
    throw POSIXError(.EEXIST)
}
