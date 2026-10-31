/// client 가 돌려준 비어 있지 않은 app ID. 입력칸의 identity 나 확정 대상의 증거는 아니다.
public struct ClientAppID: Sendable, Equatable {
    public let bundleID: String

    public init?(_ value: String?) {
        guard let value, !value.isEmpty else { return nil }
        bundleID = value
    }
}

/// 입력 판단에 쓸 app 과 그 근거를 함께 보존한다. 문자열이 같아도 fallback 은 client ID 가 아니다.
public enum InputApp: Sendable, Equatable {
    case client(ClientAppID)
    case fallback(String)

    /// mode 저장소·app 규칙·표시가 사용하는 key. 시작 규칙의 신뢰 여부는 이 문자열로 판단하지 않는다.
    public var bundleID: String {
        switch self {
        case .client(let id): id.bundleID
        case .fallback(let id): id
        }
    }
}
