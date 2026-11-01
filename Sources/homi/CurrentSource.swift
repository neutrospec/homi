import Carbon
import Foundation
import InputSession

/// TIS 결과를 한 번 읽는다. unknown 은 비homi 선택이나 client 확정의 증거가 아니다.
nonisolated enum CurrentSource {
    @MainActor
    static func read() -> SourceSelection {
        read(copy: { TISCopyCurrentKeyboardInputSource() })
    }

    @MainActor
    static func read(copy: () -> Unmanaged<TISInputSource>?) -> SourceSelection {
        guard let copied = copy() else { return .unknown(.sourceCopyNil) }
        let source = copied.takeRetainedValue()
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return .unknown(.propertyNil) }
        return fromProperty(Unmanaged<CFTypeRef>.fromOpaque(raw).takeUnretainedValue())
    }

    /// TIS Get 값은 소유하지 않는다. 실제와 synthetic CF 값이 같은 검사를 거친다.
    static func fromProperty(_ property: CFTypeRef?) -> SourceSelection {
        guard let property else { return .unknown(.propertyNil) }
        guard CFGetTypeID(property) == CFStringGetTypeID(), let id = property as? String else { return .unknown(.typeMismatch) }
        return .fromID(id)
    }
}
