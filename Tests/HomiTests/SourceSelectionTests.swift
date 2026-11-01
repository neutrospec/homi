import Carbon
import Foundation
import InputSession
import Testing
@testable import homi

@Test("TIS source 관측: nil·CF 타입·빈 ID 와 알려진 ID 를 구분한다")
func currentSourceSyntheticProperty() {
    #expect(CurrentSource.read(copy: { nil }) == .unknown(.sourceCopyNil))
    #expect(CurrentSource.fromProperty(nil) == .unknown(.propertyNil))
    #expect(CurrentSource.fromProperty(kCFBooleanTrue) == .unknown(.typeMismatch))
    #expect(CurrentSource.fromProperty("" as CFString) == .unknown(.emptyID))
    #expect(CurrentSource.fromProperty(SourceSelection.parentID as CFString) == .selected)
    #expect(CurrentSource.fromProperty(SourceSelection.modeID as CFString) == .selected)
    #expect(CurrentSource.fromProperty("com.unocult.inputmethod.homily" as CFString) == .other)
}

@Test("TIS source 관측: 정확한 source ID 는 bundle Info.plist 와 일치한다")
func sourceSelectionMatchesInfoPlist() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let data = try Data(contentsOf: root.appending(path: "Sources/homi/Bundle/Info.plist"))
    let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    #expect(plist["TISInputSourceID"] as? String == SourceSelection.parentID)
    let modes = try #require(plist["ComponentInputModeDict"] as? [String: Any])
    let list = try #require(modes["tsInputModeListKey"] as? [String: Any])
    #expect(Set(list.keys) == Set([SourceSelection.modeID]))
    let entry = try #require(list[SourceSelection.modeID] as? [String: Any])
    #expect(entry["TISInputSourceID"] as? String == SourceSelection.modeID)
}
