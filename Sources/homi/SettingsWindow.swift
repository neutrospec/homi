import AppKit
import InputSession
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// 설정 창 — input menu 의 "설정…" 이나 menu bar 의 한/A 에서 연다. 바꾸는 즉시 저장되고 다음 key 부터 쓰인다.
/// 주인이 고르는 것만 둔다: 한/영 전환 key, 한자 key 와 방식, app 목록(시작할 때 영문·ESC 로 영문·한/영 전환 없는 app).
final class SettingsWindow {
    static let shared = SettingsWindow()

    private var window: NSWindow?

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        if !window.isVisible { place(window) }
        // homi 는 background app 이라 활성화 요청(`activate`)이 받아들여지지 않을 수 있다 — 그러면 창이 다른 app 의 창 뒤에
        // 뜬다 (2026-09-25 주인). 그래서 창은 활성화와 상관없이 맨 앞으로 올린다. 누르면 그때 homi 가 활성화된다.
        window.orderFrontRegardless()
        window.makeKey()
        NSApp.activate()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
        window.title = "homi 설정"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        return window
    }

    /// mouse 가 있는 화면의 가운데 — 방금 menu 를 누른 화면이다.
    private func place(_ window: NSWindow) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else {
            window.center()
            return
        }
        let visible = screen.visibleFrame
        let size = window.frame.size
        window.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2))
    }
}

@Observable
private final class SettingsModel {
    var value = preferences.withLock { $0 } {
        didSet { if value != oldValue { PreferencesStore.update(value) } }
    }
}

private struct SettingsView: View {
    @State private var model = SettingsModel()

    var body: some View {
        Form {
            Section("한/영 전환") {
                toggleKey(.capsLock, "Caps Lock", "짧게 누르면 전환, 길게 누르면 대문자 고정")
                toggleKey(.rightCommand, "오른쪽 ⌘", "짧게 누르면 전환 — 다른 key 와 함께면 평소의 ⌘")
                toggleKey(.rightOption, "오른쪽 ⌥", "짧게 누르면 전환 — 다른 key 와 함께면 평소의 ⌥")
                toggleKey(.shiftSpace, "Shift+Space", "Ghostty·iTerm2 에서는 영문 → 한글 전환 때 space 가 들어간다")
            }

            Section("한자") {
                Picker("변환 key", selection: $model.value.hanjaKey) {
                    Text("⌥↩").tag(Preferences.HanjaKey.optionReturn)
                    Text("오른쪽 ⌥ 짧게").tag(Preferences.HanjaKey.rightOption)
                    Text("오른쪽 ⌘ 짧게").tag(Preferences.HanjaKey.rightCommand)
                }
                if model.value.effectiveHanjaKey != model.value.hanjaKey {
                    Text("그 key 는 한/영 전환에 쓰고 있어서 ⌥↩ 로 연다.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle(isOn: $model.value.hanjaRecentWord) {
                    Text("방금 친 단어도 바꾸기")
                    Text("Apple 방식 — 선택하지 않아도 커서 앞 단어를 바꾼다. macOS 기본 text 엔진을 쓰는 app 에서만 되고, 그 밖에는 조합 중인 글자나 선택한 한글을 바꾼다.")
                }
            }

            Section {
                AppList(apps: $model.value.englishStartApps)
            } header: {
                Text("시작할 때 영문")
            } footer: {
                Text("그 app 으로 올 때마다 영문으로 시작한다.")
            }

            Section {
                AppList(apps: $model.value.escapeApps)
            } header: {
                Text("ESC 로 영문")
            } footer: {
                Text("ESC 를 누르면 조합을 확정하고 영문으로 — ESC 는 app 에 그대로 간다.")
            }

            Section {
                AppList(apps: $model.value.passThroughApps)
            } header: {
                Text("한/영 전환 없는 app")
            } footer: {
                Text("한/영 전환도 조합도 하지 않고 key 를 그대로 넘긴다. Caps Lock 도 원래대로 — app 자체나 원격 컴퓨터의 입력기를 쓴다.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 720)
    }

    /// 한/영 전환 key 하나를 켜고 끈다 — 하나는 남긴다 (모두 끄면 한/영을 바꿀 수 없다).
    private func toggleKey(_ key: Preferences.ToggleKey, _ title: String, _ detail: String) -> some View {
        let isOn = Binding(
            get: { model.value.toggleKeys.contains(key) },
            set: { on in
                if on {
                    model.value.toggleKeys.insert(key)
                } else if model.value.toggleKeys.count > 1 {
                    model.value.toggleKeys.remove(key)
                }
            })
        return Toggle(isOn: isOn) {
            Text(title)
            Text(detail)
        }
    }
}

/// app 목록 — 이름·icon·bundle ID 로 보이고, 빼거나 /Applications 에서 골라 더한다.
private struct AppList: View {
    @Binding var apps: [String]

    var body: some View {
        ForEach(apps, id: \.self) { id in
            HStack {
                AppLabel(bundleID: id)
                Spacer()
                Button {
                    apps.removeAll { $0 == id }
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("빼기")
            }
        }
        Button("app 더하기…") {
            if let id = chooseApp(), !apps.contains(id) { apps.append(id) }
        }
    }

    private func chooseApp() -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.prompt = "더하기"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return Bundle(url: url)?.bundleIdentifier
    }
}

private struct AppLabel: View {
    let bundleID: String

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        HStack(spacing: 8) {
            if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "app.dashed")
                    .frame(width: 20, height: 20)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(url.map { FileManager.default.displayName(atPath: $0.path) } ?? bundleID)
                Text(url == nil ? "\(bundleID) — 이 Mac 에 없다" : bundleID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
