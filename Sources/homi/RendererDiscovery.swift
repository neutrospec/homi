import AppKit
import InputSession

/// app bundle 의 renderer 조사·cache. 조합 종료 방침은 InputSession 의 CommitPolicy 가 정한다.
final class RendererDiscovery {
    static let shared = RendererDiscovery()
    private var known: [String: RendererEvidence] = [:]
    private let locate: (String) -> URL?
    private let contents: (URL) throws -> [String]

    init(locate: @escaping (String) -> URL? = { bundleID in
        let workspace = NSWorkspace.shared
        return workspace.runningApplications.first(where: { $0.bundleIdentifier == bundleID })?.bundleURL
            ?? workspace.urlForApplication(withBundleIdentifier: bundleID)
    }, contents: @escaping (URL) throws -> [String] = {
        try FileManager.default.contentsOfDirectory(atPath: $0.path)
    }) {
        self.locate = locate
        self.contents = contents
    }

    func inspect(_ bundleID: String) -> RendererEvidence {
        if let answer = known[bundleID] { return answer }
        let answer = discover(bundleID)
        // 조회 실패는 부재가 아니다. 다음 callback 의 정상 조회를 막지 않는다 — timer·비동기 재시도는 없다.
        if answer != .unavailable { known[bundleID] = answer }
        return answer
    }

    private func discover(_ bundleID: String) -> RendererEvidence {
        guard let app = locate(bundleID) else { return .unavailable }
        let frameworks = app.appending(path: "Contents/Frameworks")
        let names: [String]
        switch directory(frameworks) {
        case .names(let entries): names = entries
        case .absent: return .notFound
        case .unavailable: return .unavailable
        }
        if names.contains(where: Self.isHelperRenderer) { return .helperRenderer } // Electron: 바로 아래
        var otherRenderer = names.contains(where: Self.isOtherRenderer)
        var incomplete = false
        // browser: <이름> Framework.framework/Helpers/ (Versions/Current/Helpers 의 symlink)
        for framework in names where framework.hasSuffix(".framework") {
            let helpers = frameworks.appending(path: framework).appending(path: "Helpers")
            switch directory(helpers) {
            case .names(let entries):
                if entries.contains(where: Self.isHelperRenderer) { return .helperRenderer }
                otherRenderer = otherRenderer || entries.contains(where: Self.isOtherRenderer)
            case .absent: break
            case .unavailable: incomplete = true
            }
        }
        // 다른 이름을 찾았어도 조사 못 한 경로에 기존 helper 가 있을 수 있다. 이 결과는 cache 하지 않는다.
        if incomplete { return .unavailable }
        return otherRenderer ? .otherRenderer : .notFound
    }

    private enum Directory {
        case names([String])
        case absent
        case unavailable
    }

    private func directory(_ url: URL) -> Directory {
        do { return .names(try contents(url)) }
        catch {
            // native app 에 Frameworks 나 Helpers 가 없는 것은 정상이다. 읽기 오류와 달리,
            // 부모 목록에서 실제 부재를 확인했을 때만 없는 directory 로 처리한다.
            guard let parent = try? contents(url.deletingLastPathComponent()),
                !parent.contains(url.lastPathComponent) else { return .unavailable }
            return .absent
        }
    }

    private static func isHelperRenderer(_ name: String) -> Bool {
        name.hasSuffix(" Helper (Renderer).app")
    }

    private static func isOtherRenderer(_ name: String) -> Bool {
        name.hasSuffix(" (Renderer).app") || name.hasSuffix(" Renderer).app")
    }
}
