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

@Test("보안 입력이 꺼져 있으면 친 key 와 글자가 기록 줄에 그대로 붙는다")
func recordLineCarriesTypedContent() {
    #expect(Recorder.line("key", typed: "kc=5 ⇧", secure: false) == "key kc=5 ⇧")
    #expect(Recorder.line("  mark", typed: "\"가\" over {3,1}", secure: false) == "  mark \"가\" over {3,1}")
    #expect(Recorder.line("  insert", typed: "\"가\"", secure: false) == "  insert \"가\"")
}

@Test("보안 입력 중에는 친 key 와 글자를 기록 줄에 담지 않고, 있었다는 것만 남긴다")
func recordLineWithholdsTypedContentUnderSecureInput() {
    var built = false
    func typed(_ content: String) -> String {
        built = true
        return content
    }
    let key = Recorder.line("key", typed: typed("kc=5 ⇧"), secure: true)
    let insert = Recorder.line("  insert", typed: typed("\"가\""), secure: true)
    #expect(key == "key (secure input)")
    #expect(insert == "  insert (secure input)")
    #expect(!built)  // 담지 않을 내용은 만들지도 않는다
}
