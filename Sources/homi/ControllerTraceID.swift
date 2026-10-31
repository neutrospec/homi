import Foundation
import Synchronization

/// 주소·hash 대신 process 식별값과 생성 번호를 쓴다. 일반 key 의 정보는 포함하지 않는다.
nonisolated enum ControllerTraceID {
    private static let process = "\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString)"
    private static let serial = Atomic<UInt64>(0)

    static func make() -> String {
        let number = serial.wrappingAdd(1, ordering: .relaxed).newValue
        return "\(process)/\(number)"
    }
}
