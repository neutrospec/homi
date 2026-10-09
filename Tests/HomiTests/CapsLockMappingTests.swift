import Foundation
import Testing
@testable import homi

private final class HID {
    var mapping: CapsLockMapping.Map = []
    var succeeds = true
    var writes = 0
    lazy var caps = CapsLockMapping(read: { [unowned self] in self.mapping }, write: { [unowned self] in
        self.writes += 1
        guard self.succeeds else { return false }
        self.mapping = $0
        return true
    })

    func destination(_ source: UInt64) -> UInt64? {
        mapping.first { ($0[CapsLockMapping.source] as? UInt64) == source }?[CapsLockMapping.destination] as? UInt64
    }
    func set(_ source: UInt64, to destination: UInt64) {
        mapping = mapping.filter { ($0[CapsLockMapping.source] as? UInt64) != source }
            + [[CapsLockMapping.source: source, CapsLockMapping.destination: destination]]
    }
}

@Test("mapping 설정 실패를 성공으로 cache 하지 않는다")
func mappingFailureCanRetry() {
    let hid = HID()
    hid.succeeds = false
    let failed = hid.caps.apply(true)
    #expect(!failed)
    hid.succeeds = true
    let done = hid.caps.apply(true)
    #expect(done)
    #expect(hid.destination(CapsLockMapping.capsLock) == CapsLockMapping.rightControl)
    #expect(hid.writes == 2)
}

@Test("homi 밖에서는 다른 도구의 Caps Lock mapping 을 지우지 않는다")
func unrelatedCapsMappingSurvives() {
    let hid = HID()
    hid.set(CapsLockMapping.capsLock, to: 0x7_0000_006D)
    hid.caps.apply(false)
    #expect(hid.destination(CapsLockMapping.capsLock) == 0x7_0000_006D)
}

@Test("Caps Lock remap 을 풀면 원래 mapping 을 복원하고 다른 key 를 보존한다")
func originalCapsMappingRestored() {
    let hid = HID()
    hid.set(CapsLockMapping.capsLock, to: 0x7_0000_006D)
    hid.mapping.append([CapsLockMapping.source: UInt64(7), CapsLockMapping.destination: UInt64(9)])
    hid.caps.apply(true)
    #expect(hid.destination(CapsLockMapping.capsLock) == CapsLockMapping.rightControl)
    hid.caps.apply(false)
    #expect(hid.destination(CapsLockMapping.capsLock) == 0x7_0000_006D)
    #expect(hid.destination(7) == 9)
}

@Test("다른 도구가 homi mapping 을 바꿨으면 해제 때 그 변경을 보존한다")
func replacementByOtherToolSurvives() {
    let hid = HID()
    hid.caps.apply(true)
    hid.set(CapsLockMapping.capsLock, to: 123)
    hid.caps.apply(false)
    #expect(hid.destination(CapsLockMapping.capsLock) == 123)
}

@Test("wake 뒤 재적용해도 최초의 Caps Lock mapping 을 잊지 않는다")
func wakePreservesOriginalMapping() {
    let hid = HID()
    hid.set(CapsLockMapping.capsLock, to: 123)
    hid.caps.apply(true)
    hid.mapping = []
    hid.caps.invalidate()
    hid.caps.apply(true)
    hid.caps.apply(false)
    #expect(hid.destination(CapsLockMapping.capsLock) == 123)
}
