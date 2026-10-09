import Foundation
import Testing
@testable import replace_app

private struct Bundles {
    let root = FileManager.default.temporaryDirectory.appending(path: "homi-install-test-\(UUID())")
    var staged: URL { root.appending(path: "staged.app") }
    var installed: URL { root.appending(path: "homi.app") }
    func make(_ url: URL, version: String) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try version.write(to: url.appending(path: "version"), atomically: true, encoding: .utf8)
    }
    func version(_ url: URL) throws -> String {
        try String(contentsOf: url.appending(path: "version"), encoding: .utf8)
    }
    func clean() { try? FileManager.default.removeItem(at: root) }
}

@Test("완성된 app 교환 뒤 설치 위치는 새 app 이고 기존 app 은 stage 에 남는다")
func appReplacedAtomically() throws {
    let bundles = Bundles()
    defer { bundles.clean() }
    try bundles.make(bundles.installed, version: "old")
    try bundles.make(bundles.staged, version: "new")
    try AtomicInstall.replace(staged: bundles.staged, installed: bundles.installed)
    #expect(try bundles.version(bundles.installed) == "new")
    #expect(try bundles.version(bundles.staged) == "old")
}

@Test("새 app 이 없어서 교환이 실패해도 설치본은 그대로 남는다")
func failedReplacementPreservesInstallation() throws {
    let bundles = Bundles()
    defer { bundles.clean() }
    try bundles.make(bundles.installed, version: "old")
    #expect(throws: POSIXError.self) {
        try AtomicInstall.replace(staged: bundles.staged, installed: bundles.installed)
    }
    #expect(try bundles.version(bundles.installed) == "old")
}

@Test("첫 설치도 완성된 app 의 이름을 바꾸어 놓는다")
func firstInstallation() throws {
    let bundles = Bundles()
    defer { bundles.clean() }
    try bundles.make(bundles.staged, version: "new")
    try AtomicInstall.replace(staged: bundles.staged, installed: bundles.installed)
    #expect(try bundles.version(bundles.installed) == "new")
    #expect(!FileManager.default.fileExists(atPath: bundles.staged.path))
}
