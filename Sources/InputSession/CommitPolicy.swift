/// bundle 에서 찾은 renderer 이름의 근거. app 의 실제 입력 동작이나 조합 확정을 증명하지 않는다.
public enum RendererEvidence: String, Sendable, Equatable {
    /// 기존 판별식의 `… Helper (Renderer).app`.
    case helperRenderer
    /// 그 밖의 renderer 이름. 발견만으로 기존 Chromium 우회를 적용하지 않는다.
    case otherRenderer
    /// 확인한 경로에는 renderer 이름이 없다.
    case notFound
    /// app 위치 또는 directory 내용을 확인하지 못했다.
    case unavailable
}

/// IMK commitComposition 의 기존 호환 정책. bundle 조사·cache 와 글자 반영은 이 판단 밖에 둔다.
public enum CommitPolicy {
    public struct Decision: Sendable, Equatable {
        public let renderer: RendererEvidence
        /// nil 은 질의하지 않음; unknown 은 질의했으나 판단할 수 없는 경우다.
        public let sourceSelection: SourceSelection?
        public let ending: CompositionEnd
    }

    /// 실제 client ID 가 없으면 조사하지 않는다. 기존 helper 가 확인된 경우에만 그 callback 안에서 source 를 읽는다.
    public static func decide(app: ClientAppID?, inspect: (ClientAppID) -> RendererEvidence,
        sourceSelection: () -> SourceSelection) -> Decision {
        let renderer = app.map(inspect) ?? .unavailable
        guard renderer == .helperRenderer else {
            return Decision(renderer: renderer, sourceSelection: nil, ending: .commitToClient)
        }
        // source 전환 중에도 TIS 가 homi 를 가리킬 수 있다. 기존 우회의 한계를 그대로 남긴다.
        let selection = sourceSelection()
        return Decision(renderer: renderer, sourceSelection: selection,
            ending: selection.compatibilitySelected ? .alreadyCommittedByClient : .commitToClient)
    }
}
