import Foundation
import MachO
import Testing

@testable import homi

private func identityFixture() -> Data {
    var data = Data(count: MemoryLayout<mach_header_64>.size + MemoryLayout<uuid_command>.size)
    func put(_ value: UInt32, at offset: Int) {
        var value = value
        withUnsafeBytes(of: &value) { data.replaceSubrange(offset..<(offset + 4), with: $0) }
    }
    put(UInt32(MH_MAGIC_64), at: 0)
    put(UInt32(MH_EXECUTE), at: 12)
    put(1, at: 16)
    put(UInt32(MemoryLayout<uuid_command>.size), at: 20)
    put(UInt32(LC_UUID), at: 32)
    put(UInt32(MemoryLayout<uuid_command>.size), at: 36)
    data.replaceSubrange(40..<56, with: UInt8(0)..<UInt8(16))
    return data
}

private func identityParse(_ data: Data) -> String? { data.withUnsafeBytes { BinaryIdentity.parse($0) } }

@Test("실행 identity: bounded Mach-O 에서 UUID 를 읽는다")
func binaryIdentityParsesUUID() {
    #expect(identityParse(identityFixture()) == "00010203-0405-0607-0809-0A0B0C0D0E0F")
    let current = BinaryIdentity.current
    #expect(current == "unknown" || UUID(uuidString: current)?.uuidString == current)
    #expect(BinaryIdentity.current == current)
}

@Test("실행 identity: 잘못된 header 와 command 는 읽지 않는다", arguments: ["short", "magic", "type", "truncated", "zero", "small", "large", "missing", "count"])
func binaryIdentityRejectsMalformed(scenario: String) {
    var data = identityFixture()
    func put(_ value: UInt32, at offset: Int) {
        var value = value
        withUnsafeBytes(of: &value) { data.replaceSubrange(offset..<(offset + 4), with: $0) }
    }
    switch scenario {
    case "short": data = Data(data.prefix(12))
    case "magic": put(0, at: 0)
    case "type": put(UInt32(MH_DYLIB), at: 12)
    case "truncated": data.removeLast()
    case "zero": put(0, at: 36)
    case "small": put(7, at: 36)
    case "large": put(0xffff_ffff, at: 36)
    case "missing": put(UInt32(LC_SEGMENT_64), at: 32)
    default: put(999, at: 16)
    }
    #expect(identityParse(data) == nil)
}
