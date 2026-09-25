import Testing

@testable import HangulCore

/// seed 가 같으면 늘 같은 수열 — 실패를 다시 볼 수 있어야 한다.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// 조합 결과로 나올 수 있는 문자: 완성형 음절과 호환 자모뿐.
func isHangul(_ scalar: Unicode.Scalar) -> Bool {
    (0xAC00...0xD7A3).contains(scalar.value) || (0x3131...0x3163).contains(scalar.value)
}

@Test("아무렇게나 쳐도 규칙이 지켜진다", arguments: 0..<200 as Range<UInt64>)
func randomTyping(seed: UInt64) {
    var random = SplitMix64(state: seed)
    let keys = Dubeolsik.keyCodes.flatMap { code in
        [false, true].compactMap { Dubeolsik.jamo(keyCode: code, shift: $0) }
    }
    var composer = Composer()
    var committed = ""
    for _ in 0..<60 {
        if Int.random(in: 0..<8, using: &random) == 0 {
            if !composer.backspace() { committed = String(committed.dropLast()) }
        } else {
            committed += composer.type(keys.randomElement(using: &random)!)
        }
        // 조합 중인 것은 많아야 한 글자다.
        #expect(composer.composing.count <= 1)
        #expect(composer.composing.unicodeScalars.allSatisfy(isHangul))
    }
    committed += composer.flush()
    #expect(committed.unicodeScalars.allSatisfy(isHangul))
    #expect(composer.composing.isEmpty)
}

@Test("친 key 를 모두 Backspace 하면 조합이 빈다 — 확정이 없었다면", arguments: [
    "ㄷㅏㄹㄱ", "ㄱㅜㅔ", "ㅗㅏ", "ㄱㅏㅆ", "ㅂㅓㄹㅂ",
])
func backspaceUndoesEverything(keys: String) {
    var composer = Composer()
    for key in keys {
        let committed = composer.type(Jamo(key)!)
        #expect(committed.isEmpty)
    }
    for _ in keys {
        let undone = composer.backspace()
        #expect(undone)
    }
    #expect(composer.composing.isEmpty)
    let undoneMore = composer.backspace()
    #expect(!undoneMore)
}
