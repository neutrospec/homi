/// 자음. 원시값은 호환 자모(U+3131…) 문자이고, case 순서가 곧 초성 index 다.
public enum Consonant: Character, CaseIterable, Sendable {
    case ㄱ = "ㄱ", ㄲ = "ㄲ", ㄴ = "ㄴ", ㄷ = "ㄷ", ㄸ = "ㄸ", ㄹ = "ㄹ", ㅁ = "ㅁ", ㅂ = "ㅂ", ㅃ = "ㅃ", ㅅ = "ㅅ"
    case ㅆ = "ㅆ", ㅇ = "ㅇ", ㅈ = "ㅈ", ㅉ = "ㅉ", ㅊ = "ㅊ", ㅋ = "ㅋ", ㅌ = "ㅌ", ㅍ = "ㅍ", ㅎ = "ㅎ"

    /// ㄸ·ㅃ·ㅉ 는 받침이 될 수 없다.
    var canBeFinal: Bool { self != .ㄸ && self != .ㅃ && self != .ㅉ }
}

/// 모음. 원시값은 호환 자모 문자이고, case 순서가 곧 중성 index 다.
/// 겹모음(ㅘ ㅙ ㅚ ㅝ ㅞ ㅟ ㅢ)은 key 가 아니라 두 key 의 조합으로만 생긴다.
public enum Vowel: Character, CaseIterable, Sendable {
    case ㅏ = "ㅏ", ㅐ = "ㅐ", ㅑ = "ㅑ", ㅒ = "ㅒ", ㅓ = "ㅓ", ㅔ = "ㅔ", ㅕ = "ㅕ", ㅖ = "ㅖ", ㅗ = "ㅗ", ㅘ = "ㅘ", ㅙ = "ㅙ"
    case ㅚ = "ㅚ", ㅛ = "ㅛ", ㅜ = "ㅜ", ㅝ = "ㅝ", ㅞ = "ㅞ", ㅟ = "ㅟ", ㅠ = "ㅠ", ㅡ = "ㅡ", ㅢ = "ㅢ", ㅣ = "ㅣ"

    /// 이 모음 뒤에 `next` 를 쳐서 만드는 겹모음.
    func combined(with next: Vowel) -> Vowel? {
        switch (self, next) {
        case (.ㅗ, .ㅏ): .ㅘ
        case (.ㅗ, .ㅐ): .ㅙ
        case (.ㅗ, .ㅣ): .ㅚ
        case (.ㅜ, .ㅓ): .ㅝ
        case (.ㅜ, .ㅔ): .ㅞ
        case (.ㅜ, .ㅣ): .ㅟ
        case (.ㅡ, .ㅣ): .ㅢ
        default: nil
        }
    }
}

/// key 하나가 내는 자모.
public enum Jamo: Hashable, Sendable {
    case consonant(Consonant)
    case vowel(Vowel)

    init?(_ character: Character) {
        if let consonant = Consonant(rawValue: character) {
            self = .consonant(consonant)
        } else if let vowel = Vowel(rawValue: character) {
            self = .vowel(vowel)
        } else {
            return nil
        }
    }

    var character: Character {
        switch self {
        case .consonant(let consonant): consonant.rawValue
        case .vowel(let vowel): vowel.rawValue
        }
    }
}

/// 받침. 순서가 곧 종성 index - 1 이다 (0 은 받침 없음).
let finalOrder: [Character] = [
    "ㄱ", "ㄲ", "ㄳ", "ㄴ", "ㄵ", "ㄶ", "ㄷ", "ㄹ", "ㄺ", "ㄻ", "ㄼ", "ㄽ", "ㄾ", "ㄿ",
    "ㅀ", "ㅁ", "ㅂ", "ㅄ", "ㅅ", "ㅆ", "ㅇ", "ㅈ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ",
]

/// 받침 `first` 뒤에 `next` 를 쳐서 만드는 겹받침.
func compoundFinal(_ first: Consonant, _ next: Consonant) -> Character? {
    switch (first, next) {
    case (.ㄱ, .ㅅ): "ㄳ"
    case (.ㄴ, .ㅈ): "ㄵ"
    case (.ㄴ, .ㅎ): "ㄶ"
    case (.ㄹ, .ㄱ): "ㄺ"
    case (.ㄹ, .ㅁ): "ㄻ"
    case (.ㄹ, .ㅂ): "ㄼ"
    case (.ㄹ, .ㅅ): "ㄽ"
    case (.ㄹ, .ㅌ): "ㄾ"
    case (.ㄹ, .ㅍ): "ㄿ"
    case (.ㄹ, .ㅎ): "ㅀ"
    case (.ㅂ, .ㅅ): "ㅄ"
    default: nil
    }
}
