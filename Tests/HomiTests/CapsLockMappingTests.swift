import Foundation
import Testing
import InputSession
@testable import homi

private final class HID {
    var mapping: CapsLockMapping.Map = []
    var succeeds = true
    var writes = 0
    var forwardedOriginal: CapsLockMapping.Map?
    init(forwardedOriginal: CapsLockMapping.Map? = nil) { self.forwardedOriginal = forwardedOriginal }
    lazy var caps = CapsLockMapping(read: { [unowned self] in self.mapping }, write: { [unowned self] in
        self.writes += 1
        guard self.succeeds else { return false }
        self.mapping = $0
        return true
    }, forwardedOriginal: forwardedOriginal, saveForwardedOriginal: { [unowned self] in self.forwardedOriginal = $0 })

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

@Test("homi 와 Windows App 사이의 전환은 최초 Caps Lock mapping 과 다른 key 를 보존한다")
func windowsDestinationPreservesOriginal() {
    let hid = HID()
    hid.set(CapsLockMapping.capsLock, to: 123)
    hid.set(7, to: 9)
    hid.caps.apply(.homi)
    hid.caps.apply(.windows(.hangul))
    #expect(hid.destination(CapsLockMapping.capsLock) == CapsLockMapping.language1)
    hid.caps.apply(.homi)
    #expect(hid.destination(CapsLockMapping.capsLock) == CapsLockMapping.rightControl)
    hid.caps.apply(.system)
    #expect(hid.destination(CapsLockMapping.capsLock) == 123)
    #expect(hid.destination(7) == 9)
}

@Test("Windows mapping 실패 뒤 재시도·wake·다른 도구의 변경을 보존한다")
func windowsDestinationFailureAndReplacement() {
    let hid = HID()
    hid.caps.apply(.homi)
    hid.succeeds = false
    let failed = hid.caps.apply(.windows(.hangul))
    #expect(!failed)
    #expect(hid.destination(CapsLockMapping.capsLock) == CapsLockMapping.rightControl)
    hid.succeeds = true
    hid.caps.apply(.windows(.hangul))
    #expect(hid.destination(CapsLockMapping.capsLock) == CapsLockMapping.language1)
    hid.caps.invalidate()
    hid.caps.apply(.windows(.hangul))
    hid.set(CapsLockMapping.capsLock, to: 456)
    hid.caps.apply(.system)
    #expect(hid.destination(CapsLockMapping.capsLock) == 456)
}

@Test("새 process 는 남은 Windows mapping 을 원래 값으로 저장하지 않는다")
func windowsMappingFromPreviousProcess() {
    let hid = HID(forwardedOriginal: [])
    hid.set(CapsLockMapping.capsLock, to: CapsLockMapping.language1)
    hid.caps.apply(.homi)
    hid.caps.apply(.system)
    #expect(hid.destination(CapsLockMapping.capsLock) == nil)
    #expect(hid.forwardedOriginal == nil)
}

@Test("소유 기록 없는 LANG1 mapping 은 다른 도구의 값으로 보존한다")
func externalLanguageMappingSurvives() {
    let hid = HID()
    hid.set(CapsLockMapping.capsLock, to: CapsLockMapping.language1)
    hid.caps.apply(.system)
    #expect(hid.destination(CapsLockMapping.capsLock) == CapsLockMapping.language1)
    hid.caps.apply(.windows(.hangul))
    hid.caps.apply(.homi)
    hid.caps.apply(.system)
    #expect(hid.destination(CapsLockMapping.capsLock) == CapsLockMapping.language1)
}

@Test("Windows mapping 의 복원값은 다음 process 가 쓰며, HID 실패 뒤 해제하면 기록도 정리한다")
func windowsOwnershipRecoveryAndFailure() {
    let first = HID()
    first.set(CapsLockMapping.capsLock, to: 123)
    first.caps.apply(.windows(.hangul))
    let next = HID(forwardedOriginal: first.forwardedOriginal)
    next.mapping = first.mapping
    next.caps.apply(.system)
    #expect(next.destination(CapsLockMapping.capsLock) == 123)
    #expect(next.forwardedOriginal == nil)

    let failed = HID()
    failed.succeeds = false
    let applied = failed.caps.apply(.windows(.hangul))
    #expect(!applied)
    failed.succeeds = true
    failed.caps.apply(.system)
    #expect(failed.destination(CapsLockMapping.capsLock) == nil)
    #expect(failed.forwardedOriginal == nil)
}

@Test("Windows 목적지를 바꾸면 Caps Lock 은 오른쪽 Alt 에 해당하는 HID key 를 보낸다")
func windowsRightAltDestination() {
    let hid = HID()
    hid.set(CapsLockMapping.capsLock, to: 123)
    hid.set(7, to: 9)
    hid.caps.apply(.homi)
    hid.caps.apply(.windows(.hangul))
    #expect(hid.destination(CapsLockMapping.capsLock) == 0x7_0000_0090)
    hid.caps.apply(.windows(.rightAlt))
    #expect(hid.destination(CapsLockMapping.capsLock) == 0x7_0000_00E6)
    hid.caps.apply(.windows(.hangul))
    #expect(hid.destination(CapsLockMapping.capsLock) == 0x7_0000_0090)
    hid.caps.apply(.windows(.rightAlt))
    hid.caps.apply(.system)
    #expect(hid.destination(CapsLockMapping.capsLock) == 123)
    #expect(hid.destination(7) == 9)
}

@Test("오른쪽 Alt 목적지의 쓰기 실패·wake·homi 복귀에도 최초 mapping 을 보존한다")
func windowsRightAltFailureAndWake() {
    let hid = HID()
    hid.set(CapsLockMapping.capsLock, to: 123)
    hid.caps.apply(.windows(.hangul))
    hid.succeeds = false
    let failed = hid.caps.apply(.windows(.rightAlt))
    #expect(!failed)
    #expect(hid.destination(CapsLockMapping.capsLock) == 0x7_0000_0090)
    hid.succeeds = true
    hid.caps.apply(.windows(.rightAlt))
    #expect(hid.destination(CapsLockMapping.capsLock) == 0x7_0000_00E6)
    hid.mapping = []
    hid.caps.invalidate()
    hid.caps.apply(.windows(.rightAlt))
    #expect(hid.destination(CapsLockMapping.capsLock) == 0x7_0000_00E6)
    hid.caps.apply(.homi)
    #expect(hid.destination(CapsLockMapping.capsLock) == CapsLockMapping.rightControl)
    hid.caps.apply(.system)
    #expect(hid.destination(CapsLockMapping.capsLock) == 123)
}

@Test("새 process 는 소유한 오른쪽 Alt mapping 을 복원한다")
func windowsRightAltRestartRestoresOriginal() {
    let first = HID()
    first.set(CapsLockMapping.capsLock, to: 123)
    first.caps.apply(.windows(.rightAlt))
    let next = HID(forwardedOriginal: first.forwardedOriginal)
    next.mapping = first.mapping
    next.caps.apply(.system)
    #expect(next.destination(CapsLockMapping.capsLock) == 123)
    #expect(next.forwardedOriginal == nil)
}

@Test("소유 기록 없는 오른쪽 Alt mapping 과 외부의 새 mapping 은 보존한다")
func externalRightAltMappingSurvives() {
    let external = HID()
    external.set(CapsLockMapping.capsLock, to: 0x7_0000_00E6)
    external.caps.apply(.system)
    #expect(external.destination(CapsLockMapping.capsLock) == 0x7_0000_00E6)
    external.caps.apply(.windows(.hangul))
    external.caps.apply(.windows(.rightAlt))
    external.caps.apply(.system)
    #expect(external.destination(CapsLockMapping.capsLock) == 0x7_0000_00E6)

    let replaced = HID()
    replaced.caps.apply(.windows(.rightAlt))
    replaced.set(CapsLockMapping.capsLock, to: 456)
    replaced.caps.apply(.system)
    #expect(replaced.destination(CapsLockMapping.capsLock) == 456)
}

@Test("Emacs 에서는 Caps Lock 을 F18 로 보내며 Windows·homi·원래 mapping 을 복원한다")
func emacsCapsMappingRoundTrip() {
    let hid = HID()
    hid.set(CapsLockMapping.capsLock, to: 123)
    hid.set(7, to: 9)
    hid.caps.apply(.homi)
    hid.caps.apply(.emacs)
    #expect(hid.destination(CapsLockMapping.capsLock) == 0x7_0000_006D)
    hid.caps.apply(.windows(.rightAlt))
    #expect(hid.destination(CapsLockMapping.capsLock) == 0x7_0000_00E6)
    hid.caps.apply(.emacs)
    #expect(hid.destination(CapsLockMapping.capsLock) == 0x7_0000_006D)
    hid.caps.apply(.homi)
    #expect(hid.destination(CapsLockMapping.capsLock) == CapsLockMapping.rightControl)
    hid.caps.apply(.system)
    #expect(hid.destination(CapsLockMapping.capsLock) == 123)
    #expect(hid.destination(7) == 9)
}

@Test("Emacs mapping 의 실패 재시도·wake·새 process 복원은 최초 값을 보존한다")
func emacsCapsMappingRecovery() {
    let hid = HID()
    hid.set(CapsLockMapping.capsLock, to: 123)
    hid.succeeds = false
    let failed = hid.caps.apply(.emacs)
    #expect(!failed)
    #expect(hid.destination(CapsLockMapping.capsLock) == 123)
    hid.succeeds = true
    hid.caps.apply(.emacs)
    hid.mapping = []
    hid.caps.invalidate()
    hid.caps.apply(.emacs)
    #expect(hid.destination(CapsLockMapping.capsLock) == 0x7_0000_006D)
    let next = HID(forwardedOriginal: hid.forwardedOriginal)
    next.mapping = hid.mapping
    next.caps.apply(.system)
    #expect(next.destination(CapsLockMapping.capsLock) == 123)
    #expect(next.forwardedOriginal == nil)
}

@Test("다른 도구의 F18 mapping 은 Emacs 왕복 뒤에도 보존한다")
func externalF18MappingSurvivesEmacs() {
    let hid = HID()
    hid.set(CapsLockMapping.capsLock, to: 0x7_0000_006D)
    hid.caps.apply(.emacs)
    hid.caps.apply(.system)
    #expect(hid.destination(CapsLockMapping.capsLock) == 0x7_0000_006D)
}
