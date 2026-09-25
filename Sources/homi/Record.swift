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
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let clock = DateFormatter()
    clock.locale = Locale(identifier: "en_US_POSIX")
    clock.dateFormat = "HH:mm:ss.SSS"  // 24시간제, 이 Mac 의 시각
    let lines = entries.map { "\(clock.string(from: $0.time))  \($0.event)" }
    let header = "# homi 최근 기록 — 친 key 와 조합 결과가 들어 있다. 주인이 요청해서 저장했다."

    clock.dateFormat = "yyyy-MM-dd'T'HHmmss"
    let file = directory.appending(path: "record-\(clock.string(from: Date())).txt")
    try ([header] + lines).joined(separator: "\n").appending("\n").write(to: file, atomically: true, encoding: .utf8)
    return file
}
