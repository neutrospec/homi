import Darwin
import Foundation

/// 완성·서명한 bundle 만 설치 위치에 놓는다. 같은 volume 의 directory 를 atomic 하게 바꾼다.
enum AtomicInstall {
    static func replace(staged: URL, installed: URL) throws {
        let exists = FileManager.default.fileExists(atPath: installed.path)
        let flags = exists ? RENAME_SWAP : RENAME_EXCL
        guard renamex_np(staged.path, installed.path, UInt32(flags)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}

@main
enum ReplaceApp {
    static func main() {
        let args = CommandLine.arguments
        guard args.count == 3 else {
            FileHandle.standardError.write(Data("usage: replace-app <staged.app> <installed.app>\n".utf8))
            exit(EXIT_FAILURE)
        }
        do {
            try AtomicInstall.replace(staged: URL(fileURLWithPath: args[1]), installed: URL(fileURLWithPath: args[2]))
        } catch {
            FileHandle.standardError.write(Data("app replacement failed: \(error)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }
}
