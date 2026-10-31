import Foundation
import HangulCore
import InputSession
import Synchronization

/// app 별 한/영 기억 — key 처리 안에서 동기적으로 읽고 쓴다. 바뀔 때마다 UserDefaults 에 남겨 재시작해도 유지한다.
nonisolated let memory = Mutex(Memory.load())

/// coordinator 도 기존 shared memory 하나를 쓴다. 저장은 memory lock 밖에서 한다.
nonisolated struct StoredModes: ModeStore {
    func withMemory<Result: Sendable>(_ operation: (inout ModeMemory) -> Result) -> Result {
        memory.withLock { operation(&$0) }
    }

    func save(_ snapshot: ModeMemory) { Memory.save(snapshot) }
}

nonisolated enum Memory {
    private static let key = "modes"

    static func load() -> ModeMemory {
        let stored = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        return ModeMemory(modes: stored.compactMapValues { $0 == "korean" ? .korean : $0 == "english" ? .english : nil })
    }

    static func save(_ memory: ModeMemory) {
        UserDefaults.standard.set(memory.modes.mapValues { $0 == .korean ? "korean" : "english" }, forKey: key)
    }
}

/// 한자 사전 — 번들의 hanja.txt 를 map 한다 (memory 에 올리지 않는다). 없으면 한자 변환만 꺼진다.
nonisolated let hanjaDictionary: HanjaDictionary? = {
    guard let url = Bundle.main.url(forResource: "hanja", withExtension: "txt") else {
        log.error("hanja.txt missing from bundle")
        return nil
    }
    return try? HanjaDictionary(contentsOf: url)
}()
