import Carbon
import Testing

@testable import HangulCore

/// Apple 두벌식 keyboard layout(`com.apple.keylayout.2SetHangul`)이 이 key 에 내는 문자.
/// 우리 표를 추측이 아니라 system 의 표와 대조하려고 쓴다 (test 에서만 Carbon 을 쓴다).
/// TIS 는 main thread 에서만 부른다 — test 들이 병렬로 돌 때 다른 thread 에서 부르면 process 가 abort 한다.
@MainActor
func appleCharacter(keyCode: UInt16, shift: Bool) throws -> String {
    let filter = [kTISPropertyInputSourceID as String: "com.apple.keylayout.2SetHangul"] as CFDictionary
    let sources = TISCreateInputSourceList(filter, true).takeRetainedValue() as NSArray
    let source = try #require(sources.firstObject.map { $0 as! TISInputSource })
    let raw = try #require(TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData))
    let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data

    return data.withUnsafeBytes { bytes in
        let layout = bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress!
        let modifiers = shift ? UInt32(shiftKey >> 8) & 0xFF : 0
        var deadKeys: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        UCKeyTranslate(
            layout, keyCode, UInt16(kUCKeyActionDown), modifiers, UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, characters.count, &length, &characters)
        return String(utf16CodeUnits: characters, count: length)
    }
}

@Test("두벌식 표는 Apple 의 2SetHangul layout 과 같다", arguments: Dubeolsik.keyCodes, [false, true])
@MainActor
func matchesAppleLayout(keyCode: UInt16, shift: Bool) throws {
    let ours = try #require(Dubeolsik.jamo(keyCode: keyCode, shift: shift))
    #expect(String(ours.character) == (try appleCharacter(keyCode: keyCode, shift: shift)))
}

@Test("자모가 아닌 key 는 표에 없다", arguments: [
    18, 19, 29,  // 1 2 0
    50,  // `
    49, 36, 48, 51, 53,  // space return tab delete esc
    27, 24, 33, 30, 42, 41, 39, 43, 47, 44,  // - = [ ] \ ; ' , . /
] as [UInt16])
func notJamo(keyCode: UInt16) {
    #expect(Dubeolsik.jamo(keyCode: keyCode, shift: false) == nil)
    #expect(Dubeolsik.jamo(keyCode: keyCode, shift: true) == nil)
}

/// QWERTY 글자로 쓴 key 를 두벌식으로 친 화면. 대문자는 Shift.
func typed(_ qwerty: String) -> String {
    let ansi: [Character: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
        "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32, "i": 34, "p": 35,
        "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
    ]
    var composer = Composer()
    var committed = ""
    for key in qwerty {
        let jamo = Dubeolsik.jamo(keyCode: ansi[Character(key.lowercased())]!, shift: key.isUppercase)!
        committed += composer.type(jamo)
    }
    return committed + "｜" + composer.composing
}

@Test("QWERTY 자리로 치기", arguments: [
    "gksrmf": "한｜글",
    "dkssudgktpdy": "안녕하세｜요",
    "qjTm": "버｜쓰",
    "Rkcl": "까｜치",
    "dhk": "｜와",
    "Tkfkd": "싸｜랑",
    "rrr": "ㄱㄱ｜ㄱ",
])
func qwerty(keys: String, expected: String) {
    #expect(typed(keys) == expected)
}
