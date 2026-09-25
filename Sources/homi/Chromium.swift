import AppKit

/// Chromium 계열 app 인가 — Chrome·Edge 같은 browser 와 Electron app(VS Code·Obsidian…).
/// app bundle 안에 renderer helper(`… Helper (Renderer).app`)가 있는 것으로 가린다 (ongeul 과 같은 판별).
///
/// 이 app 들은 조합을 page(renderer)가 가지고 있어서, click·blur 때 page 가 조합을 스스로 확정한 뒤
/// 입력기에 `commitComposition` 을 부른다 — 그때 입력기가 또 넣으면 두 번 들어간다 (AGENTS.md 함정 3).
enum Chromium {
    private static var known: [String: Bool] = [:]

    /// app 마다 한 번만 bundle 을 들여다본다.
    static func hosts(_ bundleID: String) -> Bool {
        if let answer = known[bundleID] { return answer }
        let answer = hasRenderer(bundleID)
        known[bundleID] = answer
        return answer
    }

    private static func hasRenderer(_ bundleID: String) -> Bool {
        let workspace = NSWorkspace.shared
        guard
            let app = workspace.runningApplications.first(where: { $0.bundleIdentifier == bundleID })?.bundleURL
                ?? workspace.urlForApplication(withBundleIdentifier: bundleID)
        else { return false }
        let files = FileManager.default
        let frameworks = app.appending(path: "Contents/Frameworks")
        let isRenderer = { (name: String) in name.hasSuffix(" Helper (Renderer).app") }
        guard let names = try? files.contentsOfDirectory(atPath: frameworks.path) else { return false }
        if names.contains(where: isRenderer) { return true }  // Electron: Frameworks/ 바로 아래
        // browser: <이름> Framework.framework/Helpers/ (Versions/Current/Helpers 의 symlink)
        return names.filter { $0.hasSuffix(".framework") }.contains { framework in
            let helpers = frameworks.appending(path: framework).appending(path: "Helpers")
            return (try? files.contentsOfDirectory(atPath: helpers.path))?.contains(where: isRenderer) ?? false
        }
    }
}
