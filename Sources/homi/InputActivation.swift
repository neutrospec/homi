import InputSession

/// activation 순서: 시작 준비 → 필요한 layout 반영 → 표시. client 질의나 비동기 재시도는 없다.
nonisolated enum InputActivation {
    static func run(coordinator: InputCoordinator, client: () -> Client?,
                    didActivate: (InputCoordinator.Activation) -> Void) {
        let activation = coordinator.activate()
        // 넘긴 key 의 layout 은 기본 ABC, 원격 화면의 한글 모드만 두벌식이다. 같은 event 의 재활성화는 기존 layout 을 잇는다.
        if !activation.resuming, let client = client() {
            client.apply([.layout(activation.layout)])
        }
        didActivate(activation)
    }
}
