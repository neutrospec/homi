import Foundation
import Testing

@testable import HangulCore

/// libhangul 과 같은 모양의 작은 사전 — 머리 주석, 정렬된 줄.
let sample = HanjaDictionary(
    data: Data(
        """
        # comment
        # another
        가:家:집 가
        가:加:더할 가
        한:韓:나라 이름 한
        한:漢:한수 한
        한자:漢字:
        한자:漢子:
        힣:X:끝
        """.utf8))

@Test("한 글자와 단어를 정확히 찾는다 — 앞부분이 같은 다른 key 는 섞이지 않는다")
func sampleLookup() {
    #expect(sample.candidates(for: "한").map(\.hanja) == ["韓", "漢"])
    #expect(sample.candidates(for: "한자").map(\.hanja) == ["漢字", "漢子"])
    #expect(sample.candidates(for: "가") == [Candidate(hanja: "家", meaning: "집 가"), Candidate(hanja: "加", meaning: "더할 가")])
    #expect(sample.candidates(for: "힣").map(\.hanja) == ["X"])
}

@Test("없는 key", arguments: ["", "각", "한자어", "하", "#"])
func sampleMissing(key: String) {
    #expect(sample.candidates(for: key).isEmpty)
}

/// 번들에 들어가는 실제 사전.
let bundled: HanjaDictionary = {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Sources/homi/Bundle/Resources/hanja.txt")
    return try! HanjaDictionary(contentsOf: url)
}()

@Test("실제 사전 — 자주 쓰는 것이 앞")
func bundledLookup() {
    #expect(bundled.candidates(for: "한").first == Candidate(hanja: "韓", meaning: "나라 이름 한, 한나라 한"))
    #expect(bundled.candidates(for: "한자").map(\.hanja).contains("漢字"))
    #expect(bundled.candidates(for: "대한민국").map(\.hanja) == ["大韓民國"])
    #expect(bundled.candidates(for: "학교").first?.hanja == "學校")
    #expect(bundled.candidates(for: "홙").isEmpty)
}
