import InputSession
import Testing
@testable import homi

private let press = ModifierCapture(keyCode: 62, time: 10, isDown: true, gesture: 1, activity: .events(epoch: 0, serial: 1))

@Test("IMK 가 읽을 때 다음 입력이 추가돼도 과거 release 의 snapshot 을 유지한다")
func storedEventDoesNotBecomeCurrentActivity() {
    let store = ModifierActivityStore(capacity: 2)
    store.publish(.init(keyCode: 62, time: 10, isDown: true, epoch: 0, serial: 1, gesture: 1), index: 0)
    store.publish(.init(keyCode: 62, time: 10.1, isDown: false, epoch: 0, serial: 1, gesture: 1), index: 1)
    store.publishHold(.init(keyCode: 62, time: 0, isDown: false, epoch: 0, serial: 3))
    #expect(store.release(for: press)?.activity == .events(epoch: 0, serial: 1))
    #expect(store.hold().pressedAt == nil)
    store.invalidate(epoch: 1)
    #expect(store.release(for: press) == nil)
    #expect(store.hold().activity == .missing)
}

@Test("buffer 에서 밀렸거나 중복된 release 를 다른 gesture 로 추측하지 않는다")
func boundedStoreDoesNotReuseAnotherGesture() {
    let store = ModifierActivityStore(capacity: 2)
    store.publish(.init(keyCode: 62, time: 10.1, isDown: false, epoch: 0, serial: 1, gesture: 1), index: 0)
    store.publish(.init(keyCode: 62, time: 20.1, isDown: false, epoch: 0, serial: 3, gesture: 3), index: 2)
    #expect(store.release(for: press) == nil)
    store.publish(.init(keyCode: 62, time: 10.1, isDown: false, epoch: 0, serial: 1, gesture: 1), index: 0)
    store.publish(.init(keyCode: 62, time: 10.2, isDown: false, epoch: 0, serial: 2, gesture: 1), index: 1)
    #expect(store.release(for: press) == nil)
}

@Test("관찰 thread 와 IMK 의 읽기가 겹쳐도 서로 다른 event 의 field 를 섞지 않는다")
func concurrentSnapshotFieldsStayTogether() async {
    let store = ModifierActivityStore(capacity: 1)
    let expectedPress = press
    await withTaskGroup(of: Void.self) { group in
        group.addTask {
            for serial in UInt64(1)...20_000 {
                store.publish(.init(keyCode: 62, time: Double(serial), isDown: false, epoch: 0,
                    serial: serial, gesture: 1), index: 0)
            }
        }
        group.addTask {
            for _ in 0..<20_000 {
                if let captured = store.release(for: expectedPress) {
                    #expect(captured.activity == .events(epoch: 0, serial: UInt64(captured.time)))
                    #expect(captured.keyCode == 62 && !captured.isDown && captured.gesture == 1)
                }
            }
        }
    }
    #expect(store.release(for: press)?.activity == .events(epoch: 0, serial: 20_000))
}

@Test("미처리 physical press 가 유일할 때만 연결하며 밀린 여러 gesture 를 하나로 합치지 않는다")
func uniquePendingGestureOnly() {
    let store = ModifierActivityStore(capacity: 4)
    store.publish(.init(keyCode: 62, time: 10, isDown: true, epoch: 0, serial: 1, gesture: 1), index: 0)
    let first = store.pending(keyCode: 62, after: nil)
    #expect(first.capture?.gesture == 1)
    store.publish(.init(keyCode: 62, time: 10.1, isDown: false, epoch: 0, serial: 1, gesture: 1), index: 1)
    #expect(store.release(for: first.capture!)?.time == 10.1)
    store.publish(.init(keyCode: 62, time: 11, isDown: true, epoch: 0, serial: 3, gesture: 3), index: 2)
    #expect(store.pending(keyCode: 62, after: nil).capture == nil)
    #expect(store.pending(keyCode: 62, after: first.latest).capture?.gesture == 3)
}

@Test("다른 수식키의 buffer 초과를 Caps Lock 의 미처리 press 로 세지 않는다")
func overflowIsPerModifier() {
    let store = ModifierActivityStore(capacity: 2)
    store.publish(.init(keyCode: 54, time: 10, isDown: true, epoch: 0, serial: 1, gesture: 1), index: 0)
    store.publish(.init(keyCode: 62, time: 11, isDown: true, epoch: 0, serial: 3, gesture: 3), index: 0)
    #expect(store.pending(keyCode: 62, after: nil).capture?.gesture == 3)
    store.publish(.init(keyCode: 62, time: 12, isDown: true, epoch: 0, serial: 5, gesture: 5), index: 0)
    let overflow = store.pending(keyCode: 62, after: nil)
    #expect(overflow.capture == nil)
    store.publish(.init(keyCode: 62, time: 13, isDown: true, epoch: 0, serial: 7, gesture: 7), index: 1)
    #expect(store.pending(keyCode: 62, after: overflow.latest).capture?.gesture == 7)
}

@Test("source·app context 가 바뀐 직후에는 관찰 thread 가 아직 따라오지 않아도 옛 기록을 쓰지 않는다")
func pendingContextChangeRejectsOldCapture() {
    let store = ModifierActivityStore()
    store.publish(.init(keyCode: 62, time: 10, isDown: true, epoch: 0, serial: 1, gesture: 1), index: 0)
    let press = store.pending(keyCode: 62, after: nil).capture!
    store.publish(.init(keyCode: 62, time: 10.1, isDown: false, epoch: 0, serial: 1, gesture: 1), index: 1)
    store.contextGeneration.store(1, ordering: .sequentiallyConsistent)
    #expect(store.pending(keyCode: 62, after: nil).capture == nil)
    #expect(store.release(for: press) == nil)
}
