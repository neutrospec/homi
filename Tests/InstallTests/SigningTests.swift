import Foundation
import Testing

/// 실제 script 를 임시 repository 에서 실행한다. 설치 위치만 fixture 로 바꾸고 외부 명령을 대신한다.
/// 인증서·실제 설치본·실행 중인 homi 를 건드리지 않는다. atomic 교환 자체는 AtomicInstallTests 가 검사한다.
private struct SigningFixture {
    let root = FileManager.default.temporaryDirectory.appending(path: "homi-signing-test-\(UUID())")
    var installed: URL { root.appending(path: "installed/homi.app") }

    init() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "scripts/install.sh"), encoding: .utf8)
        let destination = #"readonly dest="$HOME/Library/Input Methods/homi.app""#
        // 경로 치환에 실패하면 실제 위치에 접근하기 전에 test 준비를 중단한다. HOME 은 바꾸지 않는다.
        try #require(source.components(separatedBy: destination).count == 2)
        try write("scripts/install.sh", source.replacingOccurrences(of: destination,
            with: #"readonly dest="$HOMI_TEST_ROOT/installed/homi.app""#), executable: true)
        try write("scripts/app.sh", String(contentsOf: repository.appending(path: "scripts/app.sh"), encoding: .utf8), executable: true)
        try write("Sources/homi/Bundle/Info.plist",
            String(contentsOf: repository.appending(path: "Sources/homi/Bundle/Info.plist"), encoding: .utf8))
        try write("Sources/homi/Bundle/Resources/version", "new")
        try write("bin/homi", "new")
        try write("installed/homi.app/Contents/MacOS/homi", "old")
        try write("process-state", "running")
        try write("trace", "")
        try write("bin/swift", #"""
        #!/bin/zsh
        if [[ "$*" == *--show-bin-path* ]]; then
          print -r -- "$HOMI_TEST_ROOT/bin"
        fi
        """#, executable: true)
        try write("bin/security", #"""
        #!/bin/zsh
        print identity >> "$HOMI_TEST_ROOT/trace"
        case "$HOMI_TEST_IDENTITY" in
          present) print '1) 0123456789 "homi code signing"' ;;
          absent) print '0 valid identities found' ;;
          similar) print '1) 0123456789 "homi code signing other"' ;;
          error) print 'identity lookup failed' >&2; exit 1 ;;
        esac
        """#, executable: true)
        try write("bin/codesign", #"""
        #!/bin/zsh
        if [[ "$1" == --verify ]]; then
          print verify >> "$HOMI_TEST_ROOT/trace"
          [[ "$HOMI_TEST_FAILURE" != verify ]]
        else
          print -r -- "sign:$3" >> "$HOMI_TEST_ROOT/trace"
          [[ "$HOMI_TEST_FAILURE" != sign ]]
        fi
        """#, executable: true)
        try write("bin/replace-app", #"""
        #!/bin/zsh
        set -eu
        [[ "$2" == "$HOMI_TEST_ROOT/installed/homi.app" ]] || exit 90
        print replace >> "$HOMI_TEST_ROOT/trace"
        /bin/rm -rf "$2"
        /bin/mv "$1" "$2"
        """#, executable: true)
        try write("bin/pkill", #"""
        #!/bin/zsh
        print stop >> "$HOMI_TEST_ROOT/trace"
        print -n stopped > "$HOMI_TEST_ROOT/process-state"
        """#, executable: true)
    }

    func write(_ path: String, _ contents: String, executable: Bool = false) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        if executable { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) }
    }

    func run(_ script: String = "scripts/install.sh", arguments: [String] = [],
             identity: String = "present", failure: String = "none") throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [root.appending(path: script).path] + arguments
        process.currentDirectoryURL = root
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = root.appending(path: "bin").path + ":/usr/bin:/bin:/usr/sbin:/sbin"
        environment["HOMI_TEST_ROOT"] = root.path
        environment["HOMI_TEST_IDENTITY"] = identity
        environment["HOMI_TEST_FAILURE"] = failure
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    func read(_ path: String) throws -> String { try String(contentsOf: root.appending(path: path), encoding: .utf8) }
    func trace() throws -> [String] { try read("trace").split(separator: "\n").map(String.init) }
    func clean() { try? FileManager.default.removeItem(at: root) }

    func expectPreserved() throws {
        #expect(try read("installed/homi.app/Contents/MacOS/homi") == "old")
        #expect(try read("process-state") == "running")
        let calls = try trace()
        #expect(!calls.contains("replace") && !calls.contains("stop"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: installed.deletingLastPathComponent().path) == ["homi.app"])
    }
}

@Test("설치 서명: 인증서 부재·조회 실패·다른 이름이면 기존 설치본과 process 를 보존한다",
    arguments: ["absent", "error", "similar"])
func installerSigningRequiresIdentity(identity: String) throws {
    let fixture = try SigningFixture()
    defer { fixture.clean() }
    let result = try fixture.run(identity: identity)
    #expect(result.status != 0)
    try fixture.expectPreserved()
    #expect(try fixture.trace() == ["identity"])
}

@Test("설치 서명: 서명·검증 실패 뒤 교환하거나 process 를 종료하지 않는다", arguments: ["sign", "verify"])
func installerSigningFailurePreservesInstallation(failure: String) throws {
    let fixture = try SigningFixture()
    defer { fixture.clean() }
    let result = try fixture.run(failure: failure)
    #expect(result.status != 0)
    try fixture.expectPreserved()
    let calls = try fixture.trace()
    #expect(calls.contains("sign:homi code signing"))
    #expect(!calls.contains("sign:-"))
}

@Test("설치 서명: 정상 서명·검증 뒤에만 교환하고 process 를 종료한다")
func installerSigningSucceedsBeforeReplacement() throws {
    let fixture = try SigningFixture()
    defer { fixture.clean() }
    let result = try fixture.run()
    #expect(result.status == 0, "\(result.output)")
    #expect(try fixture.read("installed/homi.app/Contents/MacOS/homi") == "new")
    #expect(try fixture.read("process-state") == "stopped")
    #expect(try fixture.trace() == ["identity", "sign:homi code signing", "verify", "replace", "stop"])
}

@Test("개발 도구: 명시한 경우에만 인증서 없는 ad-hoc bundle 을 만든다")
func developmentBundleAllowsExplicitAdHoc() throws {
    let fixture = try SigningFixture()
    defer { fixture.clean() }
    let result = try fixture.run("scripts/app.sh", arguments: ["--allow-ad-hoc", "bin/homi",
        "Sources/homi/Bundle/Info.plist", "tool.app"], identity: "absent")
    #expect(result.status == 0, "\(result.output)")
    #expect(try fixture.trace() == ["identity", "sign:-"])
    #expect(try fixture.read("tool.app/Contents/MacOS/homi") == "new")
    try fixture.expectPreserved()
}
