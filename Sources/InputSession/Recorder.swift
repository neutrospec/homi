import Foundation

/// 최근에 일어난 일의 기록 — memory 에만 둔다.
///
/// 간헐 결함은 사후에 재현하기 어렵다. 주인이 이상한 순간에 요청하면 그때만 file 로 쓴다 (AGENTS.md "구조").
/// key 가 들어 있으므로 상시 기록하지 않는다.
public struct Recorder: Sendable {
    public struct Entry: Sendable, Equatable {
        public let time: Date
        public let event: String
    }

    public let capacity: Int
    private var ring: [Entry] = []
    private var next = 0

    public init(capacity: Int = 1000) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    public mutating func record(_ event: String, at time: Date = Date()) {
        let entry = Entry(time: time, event: event)
        if ring.count < capacity {
            ring.append(entry)
        } else {
            ring[next] = entry
        }
        next = (next + 1) % capacity
    }

    /// 오래된 것부터.
    public var entries: [Entry] {
        ring.count < capacity ? ring : Array(ring[next...] + ring[..<next])
    }
}
