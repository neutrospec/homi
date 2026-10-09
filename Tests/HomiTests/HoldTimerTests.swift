import Testing
@testable import homi

private nonisolated final class Owner {
    lazy var timer = HoldTimer(owner: self)
}

@Test("취소한 Caps Lock timer 는 controller 를 붙잡지 않는다")
func cancelledHoldReleasesOwner() {
    weak var retained: Owner?
    do {
        let owner = Owner()
        retained = owner
        owner.timer.schedule(after: 60) { _ in Issue.record("취소한 timer 가 실행됐다") }
        owner.timer.cancel()
    }
    #expect(retained == nil)
}

@Test("실행을 마친 Caps Lock timer 는 controller 를 붙잡지 않는다")
func completedHoldReleasesOwner() async {
    weak var retained: Owner?
    var owner: Owner? = Owner()
    retained = owner
    await withCheckedContinuation { continuation in
        owner?.timer.schedule(after: 0) { _ in continuation.resume() }
    }
    owner = nil
    // callback 의 stack 이 끝난 뒤 owner 의 수명을 본다.
    await Task.yield()
    #expect(retained == nil)
}

@Test("controller 가 사라지면 대기 중인 hold 는 실행되지 않는다")
func pendingHoldReleasesOwner() {
    weak var retained: Owner?
    do {
        let owner = Owner()
        retained = owner
        owner.timer.schedule(after: 60) { _ in Issue.record("없는 controller 의 timer 가 실행됐다") }
    }
    #expect(retained == nil)
}
