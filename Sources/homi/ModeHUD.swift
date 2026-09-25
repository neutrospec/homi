import AppKit
import InputSession

/// 모드가 바뀔 때 커서 옆에 잠깐 뜨는 한/A 말풍선 — Apple 입력기의 input source 표시처럼 (2026-09-25 주인 요청).
///
/// 위치(커서 줄의 사각형)는 key 처리 도중에 client 에게 묻고, 그리는 일은 key 처리가 끝난 뒤에 한다 (결정 4).
/// focus 를 뺏지 않고, mouse 를 막지 않으며, 전체 화면 app 위에도 뜬다.
final class ModeHUD {
    static let shared = ModeHUD()

    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "")
    private var hide: DispatchWorkItem?

    private static let size = NSSize(width: 32, height: 26)

    private init() {
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size), styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.size))
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 7
        background.layer?.masksToBounds = true

        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .labelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: background.centerYAnchor),
        ])
        panel.contentView = background
    }

    /// `line` 은 커서가 있는 줄의 사각형 (화면 좌표). 비어 있으면 보이지 않는다 — 위치를 모르는 client.
    func show(_ text: String, below line: NSRect) {
        guard !line.isEmpty || line.origin != .zero else { return }
        label.stringValue = text

        var origin = NSPoint(x: line.minX - 4, y: line.minY - Self.size.height - 4)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(line.origin) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 2), visible.maxX - Self.size.width - 2)
            if origin.y < visible.minY + 2 { origin.y = line.maxY + 4 }  // 화면 아래 끝이면 줄 위로
        }
        panel.setFrameOrigin(origin)

        hide?.cancel()
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        let work = DispatchWorkItem { [panel] in
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                panel.animator().alphaValue = 0
            }, completionHandler: {
                MainActor.assumeIsolated {
                    if panel.alphaValue == 0 { panel.orderOut(nil) }
                }
            })
        }
        hide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
    }
}

extension Mode {
    nonisolated var glyph: String { self == .korean ? "한" : "A" }
}
