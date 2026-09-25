import Foundation

/// 한자 후보 하나.
public struct Candidate: Sendable, Equatable {
    public let hanja: String
    /// 글자는 "나라 이름 한" 같은 뜻, 단어는 대개 빈 문자열.
    public let meaning: String

    public init(hanja: String, meaning: String) {
        self.hanja = hanja
        self.meaning = meaning
    }
}

/// 한자 사전 — libhangul 의 `hanja.txt` (BSD 3-clause, Copyright (c) 2005,2006 Choe Hwanjin; libhangul 717409c).
///
/// `한글:한자:뜻` 줄이 한글의 UTF-8 byte 순으로 정렬돼 있고 같은 한글의 줄은 붙어 있다 (확인: 2026-09-25).
/// homi 는 늘 떠 있는 process 라 file 을 memory 에 올리지 않고 map 해서 이진 탐색한다.
/// 후보는 file 의 순서 그대로 — 자주 쓰는 것이 앞에 있다 (한 → 韓 漢 寒 限 …).
public struct HanjaDictionary: Sendable {
    private let data: Data
    /// 머리의 주석(`#`) 줄 다음, 첫 항목이 시작하는 곳.
    private let body: Int

    public init(contentsOf url: URL) throws {
        self.init(data: try Data(contentsOf: url, options: .alwaysMapped))
    }

    init(data: Data) {
        self.data = data
        body = data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count, bytes[offset] == UInt8(ascii: "#") || bytes[offset] == UInt8(ascii: "\n") {
                while offset < bytes.count, bytes[offset] != UInt8(ascii: "\n") { offset += 1 }
                offset += 1
            }
            return min(offset, bytes.count)
        }
    }

    /// `key`(한글 한 글자 또는 단어)와 정확히 같은 항목들.
    public func candidates(for key: String) -> [Candidate] {
        let target = Array(key.utf8)
        guard !target.isEmpty else { return [] }
        return data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> [Candidate] in
            let end = bytes.count
            func lineStart(_ at: Int) -> Int {
                var position = at
                while position > body, bytes[position - 1] != UInt8(ascii: "\n") { position -= 1 }
                return position
            }
            func nextLine(_ start: Int) -> Int {
                var position = start
                while position < end, bytes[position] != UInt8(ascii: "\n") { position += 1 }
                return min(position + 1, end)
            }
            /// 줄의 key 와 target 비교 — UTF-8 byte 사전순 (file 의 정렬과 같다).
            func compare(_ start: Int) -> Int {
                var index = 0
                while true {
                    let position = start + index
                    let byte: UInt8? = position < end && bytes[position] != UInt8(ascii: ":") ? bytes[position] : nil
                    let want: UInt8? = index < target.count ? target[index] : nil
                    switch (byte, want) {
                    case (nil, nil): return 0
                    case (nil, _): return -1
                    case (_, nil): return 1
                    case (let byte?, let want?):
                        if byte != want { return byte < want ? -1 : 1 }
                    }
                    index += 1
                }
            }

            // key 가 target 이상인 첫 줄
            var low = body
            var high = end
            while low < high {
                let start = lineStart((low + high) / 2)
                if compare(start) < 0 { low = nextLine(start) } else { high = start }
            }

            var found: [Candidate] = []
            var start = low
            while start < end, compare(start) == 0 {
                let line = String(decoding: bytes[start..<nextLine(start)], as: UTF8.self)
                    .trimmingCharacters(in: .newlines)
                let fields = line.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
                if fields.count == 3 {
                    found.append(Candidate(hanja: String(fields[1]), meaning: String(fields[2])))
                }
                start = nextLine(start)
            }
            return found
        }
    }
}
