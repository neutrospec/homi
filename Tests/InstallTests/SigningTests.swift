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
        // 설치 위치(installed)·옛 user 위치(user — staging 도 여기에 생긴다)·소유자를 fixture 의 것으로 바꾼다.
        // 치환에 실패하면 실제 위치에 접근하기 전에 test 준비를 중단한다. HOME 은 바꾸지 않는다.
        var script = source
        for (original, replacement) in [
            (#"readonly dest="/Library/Input Methods/homi.app""#, #"readonly dest="$HOMI_TEST_ROOT/installed/homi.app""#),
            (#"readonly user_dest="$HOME/Library/Input Methods/homi.app""#, #"readonly user_dest="$HOMI_TEST_ROOT/user/homi.app""#),
            ("chown -R root:wheel", "chown -R \(getuid()):\(getgid())"),
            ("readonly lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
             #"readonly lsregister="$HOMI_TEST_ROOT/bin/lsregister""#),
        ] {
            try #require(script.components(separatedBy: original).count == 2)
            script = script.replacingOccurrences(of: original, with: replacement)
        }
        try write("scripts/install.sh", script, executable: true)
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
        try write("bin/xcrun", #"""
        #!/bin/zsh
        print uuid >> "$HOMI_TEST_ROOT/trace"
        [[ "$1" == dwarfdump && "$2" == --uuid && "$3" == "$HOMI_TEST_ROOT"/user/.homi-install.*/homi.app/Contents/MacOS/homi ]] || exit 91
        case "$HOMI_TEST_UUID" in
          error) exit 1 ;;
          empty) exit 0 ;;
          malformed) print 'not a UUID' ;;
          mixed) print 'UUID: 01234567-89AB-CDEF-0123-456789ABCDEF (arm64) fixture'; print invalid ;;
          *) print 'UUID: 01234567-89ab-cdef-0123-456789abcdef (arm64) fixture'; print 'UUID: FEDCBA98-7654-3210-FEDC-BA9876543210 (x86_64) fixture' ;;
        esac
        """#, executable: true)
        try write("bin/replace-app", #"""
        #!/bin/zsh
        set -eu
        [[ "$2" == "$HOMI_TEST_ROOT/installed/homi.app" ]] || exit 90
        print replace >> "$HOMI_TEST_ROOT/trace"
        [[ "$HOMI_TEST_FAILURE" != replace ]] || exit 1
        /bin/rm -rf "$2"
        /bin/mv "$1" "$2"
        """#, executable: true)
        // install.sh 는 terminal 이 아니면 stdin 의 암호를 sudo -S 로 넘긴다. 암호가 맞을 때만 명령을 그대로 실행한다.
        // 앞선 명령이 stdin 을 읽어 버렸으면 여기서 읽을 것이 없어 실패한다.
        try write("bin/sudo", #"""
        #!/bin/zsh
        print sudo >> "$HOMI_TEST_ROOT/trace"
        [[ "$1" == -S && "$2" == -p && -z "$3" ]] || exit 92
        read -r password || exit 93
        [[ "$password" == fixture-password ]] || { print 'Sorry, try again.' >&2; exit 1 }
        shift 3
        exec "$@"
        """#, executable: true)
        try write("bin/lsregister", #"""
        #!/bin/zsh
        case "$1" in
          -u) [[ "$2" == "$HOMI_TEST_ROOT/user/homi.app" ]] || exit 94; print unregister >> "$HOMI_TEST_ROOT/trace" ;;
          -f) [[ "$2" == "$HOMI_TEST_ROOT/installed/homi.app" ]] || exit 95; print register >> "$HOMI_TEST_ROOT/trace" ;;
          *) exit 96 ;;
        esac
        """#, executable: true)
        try write("bin/tis", #"""
        #!/bin/zsh
        print -r -- "tis:$1" >> "$HOMI_TEST_ROOT/trace"
        if [[ "$1" == register ]]; then [[ "$2" == "$HOMI_TEST_ROOT/installed/homi.app" ]] || exit 97; fi
        if [[ "$1" == list ]]; then print com.unocult.inputmethod.homi; fi
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

    func run(_ script: String = "scripts/install.sh", arguments: [String] = [], input: String = "fixture-password\n",
             identity: String = "present", failure: String = "none", uuid: String = "valid") throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [root.appending(path: script).path] + arguments
        process.currentDirectoryURL = root
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = root.appending(path: "bin").path + ":/usr/bin:/bin:/usr/sbin:/sbin"
        environment["HOMI_TEST_ROOT"] = root.path
        environment["HOMI_TEST_IDENTITY"] = identity
        environment["HOMI_TEST_FAILURE"] = failure
        environment["HOMI_TEST_UUID"] = uuid
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let stdin = Pipe()
        process.standardInput = stdin
        try process.run()
        stdin.fileHandleForWriting.write(Data(input.utf8))
        try stdin.fileHandleForWriting.close()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    func read(_ path: String) throws -> String { try String(contentsOf: root.appending(path: path), encoding: .utf8) }
    func trace() throws -> [String] { try read("trace").split(separator: "\n").map(String.init) }
    func clean() { try? FileManager.default.removeItem(at: root) }
    /// staging 과 옛 user 위치의 directory 에 남은 것. script 가 거기까지 가지 않았으면 directory 도 없다.
    var leftovers: [String] { (try? FileManager.default.contentsOfDirectory(atPath: root.appending(path: "user").path)) ?? [] }

    func expectPreserved() throws {
        #expect(try read("installed/homi.app/Contents/MacOS/homi") == "old")
        #expect(try read("process-state") == "running")
        let calls = try trace()
        #expect(!calls.contains("replace") && !calls.contains("stop"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: installed.deletingLastPathComponent().path) == ["homi.app"])
        #expect(leftovers.isEmpty)
    }
}

@Test("설치 서명: 인증서 부재·조회 실패·다른 이름이면 기존 설치본과 process 를 보존한다",
    arguments: ["absent", "error", "similar"])
func installerSigningRequiresIdentity(identity: String) throws {
    let fixture = try SigningFixture()
    defer { fixture.clean() }
    let result = try fixture.run(identity: identity)
    #expect(result.status != 0)
    #expect(!result.output.contains("executable UUID"))
    try fixture.expectPreserved()
    #expect(try fixture.trace() == ["identity"])
}

@Test("설치 서명: 서명·검증 실패 뒤 교환하거나 process 를 종료하지 않는다", arguments: ["sign", "verify"])
func installerSigningFailurePreservesInstallation(failure: String) throws {
    let fixture = try SigningFixture()
    defer { fixture.clean() }
    let result = try fixture.run(failure: failure)
    #expect(result.status != 0)
    #expect(!result.output.contains("executable UUID"))
    try fixture.expectPreserved()
    let calls = try fixture.trace()
    #expect(calls.contains("sign:homi code signing"))
    #expect(!calls.contains("sign:-"))
}

@Test("설치 서명: 정상 서명·검증 뒤에만 sudo 로 교환하고 process 를 종료한다 — stdin 의 암호는 sudo 만 읽는다")
func installerSigningSucceedsBeforeReplacement() throws {
    let fixture = try SigningFixture()
    defer { fixture.clean() }
    let result = try fixture.run()
    #expect(result.status == 0, "\(result.output)")
    #expect(try fixture.read("installed/homi.app/Contents/MacOS/homi") == "new")
    #expect(try fixture.read("process-state") == "stopped")
    #expect(try fixture.trace() == ["identity", "sign:homi code signing", "verify", "uuid", "sudo", "replace", "stop"])
    #expect(result.output.contains("executable UUID (arm64): 01234567-89AB-CDEF-0123-456789ABCDEF"))
    #expect(result.output.contains("executable UUID (x86_64): FEDCBA98-7654-3210-FEDC-BA9876543210"))
    #expect(fixture.leftovers.isEmpty)
    #expect(!result.output.contains("logout"))  // 위치가 그대로면 logout 을 요구하지 않는다
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

@Test("설치 identity: UUID 조회 실패·빈 답·잘못된 답은 설치를 막지 않는다", arguments: ["error", "empty", "malformed", "mixed"])
func installerUUIDFailureDoesNotBlockInstall(uuid: String) throws {
    let fixture = try SigningFixture()
    defer { fixture.clean() }
    let result = try fixture.run(uuid: uuid)
    #expect(result.status == 0, "\(result.output)")
    #expect(try fixture.trace() == ["identity", "sign:homi code signing", "verify", "uuid", "sudo", "replace", "stop"])
    #expect(try fixture.read("installed/homi.app/Contents/MacOS/homi") == "new")
    #expect(result.output.contains("warning: executable UUID unavailable"))
    #expect(result.output.contains("executable UUID: unknown"))
    #expect(!result.output.contains("executable UUID (arm64)"))
}

@Test("설치 identity: 교환 실패 시 조회한 UUID 를 성공 결과로 출력하지 않는다")
func installerUUIDNotPrintedWhenReplacementFails() throws {
    let fixture = try SigningFixture()
    defer { fixture.clean() }
    let result = try fixture.run(failure: "replace")
    #expect(result.status != 0)
    #expect(!result.output.contains("executable UUID"))
    #expect(try fixture.read("installed/homi.app/Contents/MacOS/homi") == "old")
    #expect(try fixture.read("process-state") == "running")
    #expect(try fixture.trace() == ["identity", "sign:homi code signing", "verify", "uuid", "sudo", "replace"])
    #expect(fixture.leftovers.isEmpty)
}

@Test("설치 위치 이동: user 위치에 옛 설치본이 있으면 교환 뒤 그 사본과 등록을 지우고 새 위치를 등록하며 logout 이 필요하다고 알린다")
func installMovesFromUserLocation() throws {
    let fixture = try SigningFixture()
    defer { fixture.clean() }
    try FileManager.default.removeItem(at: fixture.installed)
    try fixture.write("user/homi.app/Contents/MacOS/homi", "user-old")
    let result = try fixture.run()
    #expect(result.status == 0, "\(result.output)")
    #expect(try fixture.trace() == ["identity", "sign:homi code signing", "verify", "uuid", "sudo", "replace",
        "unregister", "register", "stop", "tis:register", "tis:enable", "tis:enable", "tis:list"])
    #expect(result.output.contains("logout"))  // sandbox 된 app 은 logout 전까지 새 위치를 모른다
    #expect(try fixture.read("installed/homi.app/Contents/MacOS/homi") == "new")
    #expect(try fixture.read("process-state") == "stopped")
    #expect(fixture.leftovers.isEmpty)
}

@Test("첫 설치: 설치 위치에 아무것도 없으면 놓고 등록한 뒤 logout 이 필요하다고 알린다")
func firstInstallAsksForLogout() throws {
    let fixture = try SigningFixture()
    defer { fixture.clean() }
    try FileManager.default.removeItem(at: fixture.installed)
    let result = try fixture.run(arguments: ["--register"])
    #expect(result.status == 0, "\(result.output)")
    #expect(try fixture.trace() == ["identity", "sign:homi code signing", "verify", "uuid", "sudo", "replace",
        "stop", "tis:register", "tis:enable", "tis:enable", "tis:list"])
    #expect(result.output.contains("logout"))  // 처음 놓은 위치도 sandbox 된 app 은 logout 전까지 모른다
    #expect(try fixture.read("installed/homi.app/Contents/MacOS/homi") == "new")
    #expect(fixture.leftovers.isEmpty)
}

@Test("설치 위치 이동: 교환이 실패하면 user 위치의 옛 설치본과 등록, process 를 그대로 둔다")
func installKeepsUserCopyWhenReplacementFails() throws {
    let fixture = try SigningFixture()
    defer { fixture.clean() }
    try fixture.write("user/homi.app/Contents/MacOS/homi", "user-old")
    let result = try fixture.run(failure: "replace")
    #expect(result.status != 0)
    #expect(try fixture.read("user/homi.app/Contents/MacOS/homi") == "user-old")
    #expect(try fixture.read("installed/homi.app/Contents/MacOS/homi") == "old")
    #expect(try fixture.read("process-state") == "running")
    #expect(try fixture.trace() == ["identity", "sign:homi code signing", "verify", "uuid", "sudo", "replace"])
    #expect(fixture.leftovers == ["homi.app"])
}

@Test("설치: sudo 가 암호를 거부하면 교환하거나 process 를 종료하지 않는다", arguments: ["wrong\n", ""])
func installRefusedBySudoPreservesInstallation(input: String) throws {
    let fixture = try SigningFixture()
    defer { fixture.clean() }
    let result = try fixture.run(input: input)
    #expect(result.status != 0)
    #expect(!result.output.contains("executable UUID"))
    #expect(try fixture.trace() == ["identity", "sign:homi code signing", "verify", "uuid", "sudo"])
    try fixture.expectPreserved()
}

@Test("설치 option: 모르는 option 은 아무것도 하지 않고 거부한다 — 없앤 --system 도 그렇다", arguments: ["--sytem", "--system"])
func installerRejectsUnknownOption(option: String) throws {
    let fixture = try SigningFixture()
    defer { fixture.clean() }
    let result = try fixture.run(arguments: [option])
    #expect(result.status == 2)
    #expect(try fixture.trace().isEmpty)
    try fixture.expectPreserved()
}
