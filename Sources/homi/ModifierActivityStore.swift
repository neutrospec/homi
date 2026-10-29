import InputSession
import Synchronization

/// writer 는 관찰 thread 하나다. reader 는 IMK 이며 서로 기다리지 않는다.
/// slot 의 모든 field 는 atomic 이고, 읽는 중 바뀐 slot 은 version 으로 거른다.
nonisolated final class ModifierActivityStore: Sendable {
    struct Entry: Sendable {
        var keyCode: UInt16
        var time: Double
        var isDown: Bool
        var epoch: UInt64
        var serial: UInt64
        var gesture: UInt64 = 0
        var activity: ModifierActivity { .events(epoch: epoch, serial: serial) }
        var capture: ModifierCapture { .init(keyCode: keyCode, time: time, isDown: isDown, gesture: gesture, activity: activity) }
    }

    private final class Slot: Sendable {
        private let version = Atomic<UInt64>(0)
        private let key = Atomic<UInt64>(0)
        private let time = Atomic<UInt64>(0)
        private let epoch = Atomic<UInt64>(0)
        private let serial = Atomic<UInt64>(0)
        private let gesture = Atomic<UInt64>(0)

        func write(_ entry: Entry) {
            let before = version.load(ordering: .sequentiallyConsistent)
            version.store(before &+ 1, ordering: .sequentiallyConsistent)
            key.store(UInt64(entry.keyCode) | (entry.isDown ? 1 << 16 : 0), ordering: .sequentiallyConsistent)
            time.store(entry.time.bitPattern, ordering: .sequentiallyConsistent)
            epoch.store(entry.epoch, ordering: .sequentiallyConsistent)
            serial.store(entry.serial, ordering: .sequentiallyConsistent)
            gesture.store(entry.gesture, ordering: .sequentiallyConsistent)
            version.store(before &+ 2, ordering: .sequentiallyConsistent)
        }

        func read() -> Entry? {
            let before = version.load(ordering: .sequentiallyConsistent)
            guard before != 0, before & 1 == 0 else { return nil }
            let key = key.load(ordering: .sequentiallyConsistent)
            let result = Entry(keyCode: UInt16(truncatingIfNeeded: key),
                time: Double(bitPattern: time.load(ordering: .sequentiallyConsistent)), isDown: key & (1 << 16) != 0,
                epoch: epoch.load(ordering: .sequentiallyConsistent), serial: serial.load(ordering: .sequentiallyConsistent),
                gesture: gesture.load(ordering: .sequentiallyConsistent))
            return version.load(ordering: .sequentiallyConsistent) == before ? result : nil
        }
    }

    private let slots: [Slot]
    private let holdSlot = Slot()
    private let epoch = Atomic<UInt64>(0)
    private final class LostPress: Sendable { let value = Atomic<UInt64>(0) }
    private let overwrittenPress = [LostPress(), LostPress(), LostPress()]
    /// slot 하나뿐 아니라 검색 전체도 같은 쓰기 세대 안에서 읽는다.
    private let revision = Atomic<UInt64>(0)
    private let appliedContext = Atomic<UInt64>(0)
    let available = Atomic<Bool>(false)
    let contextGeneration = Atomic<UInt64>(0)

    init(capacity: Int = 256) {
        precondition(capacity > 0)
        slots = (0..<capacity).map { _ in Slot() }
    }

    func publish(_ entry: Entry, index: Int) {
        let before = revision.load(ordering: .sequentiallyConsistent)
        revision.store(before &+ 1, ordering: .sequentiallyConsistent)
        defer { revision.store(before &+ 2, ordering: .sequentiallyConsistent) }
        let slot = slots[index % slots.count]
        if let old = slot.read(), old.epoch == entry.epoch, old.isDown, let lost = loss(for: old.keyCode) {
            let previous = lost.value.load(ordering: .sequentiallyConsistent)
            lost.value.store(max(previous, old.gesture), ordering: .sequentiallyConsistent)
        }
        slot.write(entry)
    }
    func publishHold(_ entry: Entry) { holdSlot.write(entry) }
    func invalidate(epoch: UInt64, context: UInt64 = 0) {
        let before = revision.load(ordering: .sequentiallyConsistent)
        revision.store(before &+ 1, ordering: .sequentiallyConsistent)
        defer { revision.store(before &+ 2, ordering: .sequentiallyConsistent) }
        for lost in overwrittenPress { lost.value.store(0, ordering: .sequentiallyConsistent) }
        self.epoch.store(epoch, ordering: .sequentiallyConsistent)
        appliedContext.store(context, ordering: .sequentiallyConsistent)
    }

    /// 미처리 press 가 둘 이상이거나 이미 buffer 에서 밀렸다면 어떤 gesture 인지 추측하지 않는다.
    func pending(keyCode: UInt16, after previous: (epoch: UInt64, gesture: UInt64)?)
        -> (capture: ModifierCapture?, latest: (epoch: UInt64, gesture: UInt64)?) {
        guard let frame = frame(), let lostPress = loss(for: keyCode) else { return (nil, nil) }
        let current = frame.epoch
        let after = previous?.epoch == current ? previous!.gesture : 0
        let lost = lostPress.value.load(ordering: .sequentiallyConsistent)
        let pending = slots.compactMap { $0.read() }.filter {
            $0.epoch == current && $0.keyCode == keyCode && $0.isDown && $0.gesture > after
        }
        let latest = (current, max(after, pending.map(\.gesture).max() ?? 0, lost))
        guard isCurrent(frame) else { return (nil, nil) }
        guard lost <= after, pending.count == 1 else { return (nil, latest) }
        return (pending[0].capture, latest)
    }

    func release(for press: ModifierCapture) -> ModifierCapture? {
        guard case .events(let expectedEpoch, _) = press.activity else { return nil }
        guard let frame = frame() else { return nil }
        let current = frame.epoch
        guard expectedEpoch == current else { return nil }
        let matching = slots.compactMap { $0.read() }.filter {
            $0.epoch == current && $0.keyCode == press.keyCode && !$0.isDown && $0.gesture == press.gesture
        }
        guard isCurrent(frame), matching.count == 1 else { return nil }
        return matching[0].capture
    }

    func hold() -> (pressedAt: Double?, activity: ModifierActivity) {
        guard let frame = frame(), let entry = holdSlot.read(), entry.epoch == frame.epoch,
            isCurrent(frame) else { return (nil, .missing) }
        return (entry.isDown ? entry.time : nil, entry.activity)
    }

    private func loss(for keyCode: UInt16) -> LostPress? {
        switch keyCode {
        case 54: overwrittenPress[0]
        case 61: overwrittenPress[1]
        case 62: overwrittenPress[2]
        default: nil
        }
    }

    private typealias Frame = (revision: UInt64, epoch: UInt64, context: UInt64)
    private func frame() -> Frame? {
        let sequence = revision.load(ordering: .sequentiallyConsistent)
        let requested = contextGeneration.load(ordering: .sequentiallyConsistent)
        guard sequence & 1 == 0, appliedContext.load(ordering: .sequentiallyConsistent) == requested else { return nil }
        return (sequence, epoch.load(ordering: .sequentiallyConsistent), requested)
    }

    private func isCurrent(_ frame: Frame) -> Bool {
        revision.load(ordering: .sequentiallyConsistent) == frame.revision
            && contextGeneration.load(ordering: .sequentiallyConsistent) == frame.context
    }

}
