/// 두벌식 조합기. 규칙은 docs/spec.md.
///
/// 조합 중인 음절을 **그 음절에 친 key 들**로 기억하고, 보이는 글자는 거기서 계산한다.
/// 그래서 Backspace 는 마지막 key 를 빼는 것이고, 도깨비불은 마지막 key 를 다음 음절로 옮기는 것이다.
/// `keys` 는 늘 온전한 음절 하나를 이룬다 — `type` 이 그렇게만 쌓는다.
public struct Composer: Sendable {
    private(set) var keys: [Jamo] = []

    public init() {}

    /// 조합 중인 글자 (marked text 로 보일 것). 없으면 빈 문자열.
    public var composing: String { Syllable(keys).text }

    /// 자모 하나를 친다. 이 key 때문에 확정된 글자를 돌려준다 (없으면 빈 문자열).
    public mutating func type(_ jamo: Jamo) -> String {
        guard !keys.isEmpty else {
            keys = [jamo]
            return ""
        }
        let current = Syllable(keys)

        switch jamo {
        case .vowel(let vowel):
            if current.finals.isEmpty {
                if current.vowels.isEmpty {  // 초성 + 모음
                    keys.append(jamo)
                    return ""
                }
                if current.vowels.count == 1, current.vowels[0].combined(with: vowel) != nil {  // 겹모음
                    keys.append(jamo)
                    return ""
                }
                return restart(with: jamo)
            }
            // 도깨비불: 받침을 이루던 마지막 key 가 다음 음절의 초성이 된다.
            let moved = keys.removeLast()
            let committed = composing
            keys = [moved, jamo]
            return committed

        case .consonant(let consonant):
            // 초성만 있거나 모음으로 시작한 음절에는 받침을 붙이지 않는다 — 같은 자음도 합치지 않는다.
            guard current.initial != nil, !current.vowels.isEmpty else { return restart(with: jamo) }
            switch current.finals.count {
            case 0 where consonant.canBeFinal:
                keys.append(jamo)
                return ""
            case 1 where compoundFinal(current.finals[0], consonant) != nil:
                keys.append(jamo)
                return ""
            default:
                return restart(with: jamo)
            }
        }
    }

    /// 마지막 key 하나를 되돌린다. 되돌릴 것이 없으면 false — 그때의 Backspace 는 app 몫이다.
    public mutating func backspace() -> Bool {
        guard !keys.isEmpty else { return false }
        keys.removeLast()
        return true
    }

    /// 조합 중인 글자를 확정해 돌려주고 비운다.
    public mutating func flush() -> String {
        defer { keys = [] }
        return composing
    }

    private mutating func restart(with jamo: Jamo) -> String {
        let committed = composing
        keys = [jamo]
        return committed
    }
}

/// key 들을 초성 · 중성 key · 받침 key 로 나눈 음절.
struct Syllable {
    var initial: Consonant?
    var vowels: [Vowel] = []
    var finals: [Consonant] = []

    init(_ keys: [Jamo]) {
        for key in keys {
            switch key {
            case .consonant(let consonant):
                if initial == nil, vowels.isEmpty { initial = consonant } else { finals.append(consonant) }
            case .vowel(let vowel):
                vowels.append(vowel)
            }
        }
    }

    var text: String {
        let medial = vowels.count == 2 ? vowels[0].combined(with: vowels[1]) : vowels.first
        switch (initial, medial) {
        case (nil, nil):
            return ""
        case (let initial?, nil):
            return String(initial.rawValue)
        case (nil, let medial?):
            return String(medial.rawValue)
        case (let initial?, let medial?):
            let final = finals.count == 2 ? compoundFinal(finals[0], finals[1]) : finals.first?.rawValue
            let choseong = Consonant.allCases.firstIndex(of: initial)!
            let jungseong = Vowel.allCases.firstIndex(of: medial)!
            let jongseong = final.map { finalOrder.firstIndex(of: $0)! + 1 } ?? 0
            let scalar = 0xAC00 + (choseong * 21 + jungseong) * 28 + jongseong
            return String(Unicode.Scalar(UInt32(scalar))!)
        }
    }
}
