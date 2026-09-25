import Testing

@testable import HangulCore

/// 자모와 ⌫ 를 차례로 친 화면 — `확정｜조합 중` (docs/spec.md 의 표기).
/// 조합 중인 것이 없을 때의 ⌫ 는 app 이 확정된 글자 하나를 지운다.
func screen(_ keys: String) -> String {
    var composer = Composer()
    var committed = ""
    for key in keys {
        if key == "⌫" {
            if !composer.backspace() { committed = String(committed.dropLast()) }
        } else {
            committed += composer.type(Jamo(key)!)
        }
    }
    return committed + "｜" + composer.composing
}

// docs/spec.md "조합" 표의 행 순서를 따른다.

@Test("초성·중성·받침", arguments: [
    "ㄱ": "｜ㄱ",
    "ㄱㅏ": "｜가",
    "ㄱㅏㄱ": "｜각",
    "ㅎㅏㄴㄱㅡㄹ": "한｜글",
    "ㄱㅏㄲ": "｜갂",
    "ㄱㅏㅆ": "｜갔",
])
func syllable(keys: String, expected: String) {
    #expect(screen(keys) == expected)
}

@Test("초성 뒤 자음은 합치지 않는다 — 같은 자음도", arguments: [
    "ㄱㄱ": "ㄱ｜ㄱ",
    "ㅅㅅ": "ㅅ｜ㅅ",
    "ㅈㅈ": "ㅈ｜ㅈ",
    "ㄷㄷ": "ㄷ｜ㄷ",
    "ㅂㅂ": "ㅂ｜ㅂ",
    "ㄱㅅ": "ㄱ｜ㅅ",
    "ㄹㄱ": "ㄹ｜ㄱ",
    "ㅅㅅㅏ": "ㅅ｜사",
    "ㅋㅋㅋ": "ㅋㅋ｜ㅋ",
])
func consonantAfterInitial(keys: String, expected: String) {
    #expect(screen(keys) == expected)
}

@Test("모음으로 시작", arguments: [
    "ㅏ": "｜ㅏ",
    "ㅗㅏ": "｜ㅘ",
    "ㅗㅣ": "｜ㅚ",
    "ㅏㅏ": "ㅏ｜ㅏ",
    "ㅗㅏㅏ": "ㅘ｜ㅏ",
    "ㅏㄱ": "ㅏ｜ㄱ",
    "ㅏㄱㅏ": "ㅏ｜가",
    "ㅠㅠ": "ㅠ｜ㅠ",
])
func vowelFirst(keys: String, expected: String) {
    #expect(screen(keys) == expected)
}

@Test("겹모음", arguments: [
    "ㄱㅗㅏ": "｜과",
    "ㄱㅗㅐ": "｜괘",
    "ㄱㅗㅣ": "｜괴",
    "ㄱㅜㅓ": "｜궈",
    "ㄱㅜㅔ": "｜궤",
    "ㄱㅜㅣ": "｜귀",
    "ㅇㅡㅣ": "｜의",
    "ㄱㅏㅏ": "가｜ㅏ",
    "ㄱㅗㅏㅏ": "과｜ㅏ",
    "ㄱㅓㅗ": "거｜ㅗ",
])
func compoundVowel(keys: String, expected: String) {
    #expect(screen(keys) == expected)
}

@Test("받침이 될 수 없는 자음", arguments: [
    "ㄱㅏㄸ": "가｜ㄸ",
    "ㄱㅏㅃ": "가｜ㅃ",
    "ㄱㅏㅉ": "가｜ㅉ",
    "ㄱㅏㅉㅏ": "가｜짜",
])
func notFinal(keys: String, expected: String) {
    #expect(screen(keys) == expected)
}

@Test("겹받침", arguments: [
    "ㄱㅏㄱㅅ": "｜갃",
    "ㅇㅏㄴㅈ": "｜앉",
    "ㅁㅏㄴㅎ": "｜많",
    "ㄷㅏㄹㄱ": "｜닭",
    "ㅅㅏㄹㅁ": "｜삶",
    "ㅇㅕㄹㅂ": "｜엷",
    "ㄱㅗㄹㅅ": "｜곬",
    "ㅎㅏㄹㅌ": "｜핥",
    "ㅇㅡㄹㅍ": "｜읊",
    "ㅇㅏㄹㅎ": "｜앓",
    "ㄱㅏㅂㅅ": "｜값",
    "ㄱㅏㄱㄴ": "각｜ㄴ",
    "ㄱㅏㄹㄹ": "갈｜ㄹ",
    "ㄱㅏㄱㄱ": "각｜ㄱ",
    "ㄷㅏㄹㄱㄱ": "닭｜ㄱ",
    "ㄱㅏㅆㅅ": "갔｜ㅅ",
])
func compoundFinal(keys: String, expected: String) {
    #expect(screen(keys) == expected)
}

@Test("도깨비불", arguments: [
    "ㄱㅏㄱㅏ": "가｜가",
    "ㅂㅓㅆㅡ": "버｜쓰",
    "ㄱㅏㄲㅏ": "가｜까",
    "ㅁㅏㄹㄱㅗ": "말｜고",
    "ㄱㅏㄱㅅㅏ": "각｜사",
    "ㄷㅏㄹㄱㅣ": "달｜기",
    "ㅇㅣㄹㅓㄴ": "이｜런",
    "ㅎㅏㄴㄱㅡㄹㅣ": "한그｜리",
    "ㅎㅏㄴㄱㅡㄹㅇㅣ": "한글｜이",
    "ㄱㅏㄱㅗㅏ": "가｜과",
])
func dokkaebibul(keys: String, expected: String) {
    #expect(screen(keys) == expected)
}

@Test("Backspace — 조합 중에는 마지막 key 하나", arguments: [
    "ㄷㅏㄹㄱ⌫": "｜달",
    "ㄷㅏㄹㄱ⌫⌫": "｜다",
    "ㄷㅏㄹㄱ⌫⌫⌫": "｜ㄷ",
    "ㄷㅏㄹㄱ⌫⌫⌫⌫": "｜",
    "ㄱㅜㅔ⌫": "｜구",
    "ㄱㅏㄹㄱ⌫": "｜갈",
    "ㄱㅏㅆ⌫": "｜가",
    "ㅗㅏ⌫": "｜ㅗ",
    "ㄷㅏㄹㄱㅣ⌫": "달｜ㄱ",
    "ㄷㅏㄹㄱㅣ⌫⌫": "달｜",
    "ㄱㅏㄴㅏ⌫⌫⌫": "｜",
    "ㄱㅏㄴㅏ⌫⌫ㄷㅏ": "가｜다",
    "⌫": "｜",
])
func backspace(keys: String, expected: String) {
    #expect(screen(keys) == expected)
}

@Test("flush 는 조합 중인 글자를 확정하고 비운다")
func flush() {
    var composer = Composer()
    for key in "ㄷㅏㄹㄱ" { _ = composer.type(Jamo(key)!) }
    let first = composer.flush()
    #expect(first == "닭")
    #expect(composer.composing.isEmpty)
    let second = composer.flush()
    #expect(second.isEmpty)
    let undone = composer.backspace()
    #expect(!undone)
}

@Test("출력 — 낱자모는 호환 자모, 음절은 완성형")
func codePoints() {
    #expect(screen("ㄱ").unicodeScalars.last?.value == 0x3131)
    #expect(screen("ㅏ").unicodeScalars.last?.value == 0x314F)
    #expect(screen("ㄱㅏ").unicodeScalars.last?.value == 0xAC00)
    #expect(screen("ㅎㅣㅎ").unicodeScalars.last?.value == 0xD7A3)
}
