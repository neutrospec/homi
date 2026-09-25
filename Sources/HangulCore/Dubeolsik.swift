/// 두벌식 자판 — 물리 key 위치(`keyCode`, ANSI)에서 자모로.
/// 아래 깔린 keyboard layout 과 무관하게 자리로 읽는다. Shift 는 ㅃㅉㄸㄲㅆㅒㅖ 만 바꾼다.
/// Apple 의 `com.apple.keylayout.2SetHangul` 과 같은 표다 (test 가 대조한다).
public enum Dubeolsik {
    /// 이 key 가 내는 자모. 자모 key 가 아니면 nil.
    public static func jamo(keyCode: UInt16, shift: Bool) -> Jamo? {
        guard let key = table[keyCode] else { return nil }
        return shift ? (key.shifted ?? key.plain) : key.plain
    }

    /// 자모를 내는 key 들.
    public static let keyCodes: [UInt16] = table.keys.sorted()

    private struct Key: Sendable {
        let plain: Jamo
        let shifted: Jamo?
    }

    private static func c(_ plain: Consonant, _ shifted: Consonant? = nil) -> Key {
        Key(plain: .consonant(plain), shifted: shifted.map { .consonant($0) })
    }

    private static func v(_ plain: Vowel, _ shifted: Vowel? = nil) -> Key {
        Key(plain: .vowel(plain), shifted: shifted.map { .vowel($0) })
    }

    private static let table: [UInt16: Key] = [
        12: c(.ㅂ, .ㅃ), 13: c(.ㅈ, .ㅉ), 14: c(.ㄷ, .ㄸ), 15: c(.ㄱ, .ㄲ), 17: c(.ㅅ, .ㅆ),  // Q W E R T
        16: v(.ㅛ), 32: v(.ㅕ), 34: v(.ㅑ), 31: v(.ㅐ, .ㅒ), 35: v(.ㅔ, .ㅖ),  // Y U I O P
        0: c(.ㅁ), 1: c(.ㄴ), 2: c(.ㅇ), 3: c(.ㄹ), 5: c(.ㅎ),  // A S D F G
        4: v(.ㅗ), 38: v(.ㅓ), 40: v(.ㅏ), 37: v(.ㅣ),  // H J K L
        6: c(.ㅋ), 7: c(.ㅌ), 8: c(.ㅊ), 9: c(.ㅍ),  // Z X C V
        11: v(.ㅠ), 45: v(.ㅜ), 46: v(.ㅡ),  // B N M
    ]
}
