import Foundation
import Testing

@testable import InputSession

@Test("Recorder 는 최근 capacity 개만, 오래된 것부터 돌려준다")
func recorderKeepsRecent() {
    var recorder = Recorder(capacity: 3)
    for i in 1...5 { recorder.record("e\(i)", at: Date(timeIntervalSince1970: Double(i))) }
    #expect(recorder.entries.map(\.event) == ["e3", "e4", "e5"])
}

@Test("Recorder 가 다 차기 전")
func recorderBeforeFull() {
    var recorder = Recorder(capacity: 3)
    recorder.record("a")
    recorder.record("b")
    #expect(recorder.entries.map(\.event) == ["a", "b"])
}
