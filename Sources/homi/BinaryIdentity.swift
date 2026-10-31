import Darwin
import Foundation
import MachO

/// main executable 안의 주소. dladdr 는 이 주소가 속한 load image 를 찾는다.
private nonisolated func binaryIdentityAnchor() {}

/// 현재 실행 중인 Mach-O slice 의 LC_UUID. bundle·서명·source commit 의 식별자는 아니다.
nonisolated enum BinaryIdentity {
    /// startup 에 한 번 준비하고 이후 log·주인이 요청한 기록에서 같은 값을 쓴다.
    static let current: String = loadedUUID() ?? "unknown"

    private static func loadedUUID() -> String? {
        let anchor: @convention(c) () -> Void = binaryIdentityAnchor
        var info = Dl_info()
        guard dladdr(unsafeBitCast(anchor, to: UnsafeRawPointer.self), &info) != 0,
              let base = info.dli_fbase else { return nil }
        let header = UnsafeRawPointer(base)
        let headerSize = MemoryLayout<mach_header_64>.size
        let size = header.loadUnaligned(fromByteOffset: 20, as: UInt32.self)
        // 이 경로는 dyld 가 load 한 자기 image 만 다룬다. 비정상 크기·형식은 입력을 멈추지 않고 버린다.
        guard size <= 16 * 1024 * 1024 else { return nil }
        let bytes = UnsafeRawBufferPointer(start: header, count: headerSize + Int(size))
        return parse(bytes)
    }

    /// 경계가 주어진 native-endian 64-bit 실행 image. 잘못된 명령이나 UUID 부재는 nil.
    static func parse(_ bytes: UnsafeRawBufferPointer) -> String? {
        let headerSize = MemoryLayout<mach_header_64>.size
        guard bytes.count >= headerSize,
              bytes.loadUnaligned(fromByteOffset: 0, as: UInt32.self) == MH_MAGIC_64,
              bytes.loadUnaligned(fromByteOffset: 12, as: UInt32.self) == MH_EXECUTE else { return nil }
        let count = Int(bytes.loadUnaligned(fromByteOffset: 16, as: UInt32.self))
        let size = Int(bytes.loadUnaligned(fromByteOffset: 20, as: UInt32.self))
        guard size <= bytes.count - headerSize, count <= size / 8 else { return nil }
        var offset = headerSize
        let end = headerSize + size
        var found: String?
        for _ in 0..<count {
            guard offset <= end - 8 else { return nil }
            let kind = bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
            let length = Int(bytes.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self))
            guard length >= 8, length <= end - offset else { return nil }
            if kind == LC_UUID {
                guard length == MemoryLayout<uuid_command>.size, found == nil else { return nil }
                let b = (0..<16).map { bytes.loadUnaligned(fromByteOffset: offset + 8 + $0, as: UInt8.self) }
                found = UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                                    b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15])).uuidString
            }
            offset += length
        }
        guard offset == end else { return nil }
        return found
    }
}
