import AppKit
import HangulCore
import InputSession

/// 한자 후보 창 — 커서 줄 아래에 한 쪽(9개)씩: 번호 · 한자 · 뜻. 고른 줄은 강조한다.
///
/// 모양은 커서 옆 말풍선(`ModeHUD`)과 같은 계열이다. focus 를 뺏지 않고 mouse 를 막지 않는다 — 고르기는 key 로만 한다.
/// 위치(커서 줄)는 key 처리 도중에 client 에게 묻고, 그리는 일은 key 처리가 끝난 뒤에 한다 (결정 4).
final class CandidatePanel {
    static let shared = CandidatePanel()

    private let panel: NSPanel
    private let background = NSVisualEffectView()
    private let rows = NSStackView()

    private static let padding: CGFloat = 6

    private init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        background.layer?.masksToBounds = true

        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 1
        rows.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(rows)
        NSLayoutConstraint.activate([
            rows.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: Self.padding),
            rows.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -Self.padding),
            rows.topAnchor.constraint(equalTo: background.topAnchor, constant: Self.padding),
            rows.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -Self.padding),
        ])
        panel.contentView = background
    }

    func show(_ candidates: [Candidate], selected: Int, below line: NSRect) {
        let size = Session.page
        let start = selected / size * size
        let pages = (candidates.count + size - 1) / size

        rows.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (offset, candidate) in candidates[start..<min(start + size, candidates.count)].enumerated() {
            rows.addArrangedSubview(row(number: offset + 1, candidate, highlighted: start + offset == selected))
        }
        if pages > 1 {
            let footer = label("\(start / size + 1) / \(pages)", size: 11, color: .tertiaryLabelColor)
            footer.alignment = .right
            rows.addArrangedSubview(footer)
            footer.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        }
        for view in rows.arrangedSubviews where view is Row {
            view.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        }

        background.layoutSubtreeIfNeeded()
        let fitting = background.fittingSize
        var origin = NSPoint(x: line.minX - Self.padding, y: line.minY - fitting.height - 4)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(line.origin) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 2), visible.maxX - fitting.width - 2)
            if origin.y < visible.minY + 2 { origin.y = line.maxY + 4 }  // 화면 아래 끝이면 줄 위로
        }
        panel.setFrame(NSRect(origin: origin, size: fitting), display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    /// 후보 한 줄: 번호 · 한자 · 뜻
    private final class Row: NSView {}

    private func row(number: Int, _ candidate: Candidate, highlighted: Bool) -> NSView {
        let text: NSColor = highlighted ? .alternateSelectedControlTextColor : .labelColor
        let secondary: NSColor = highlighted ? .alternateSelectedControlTextColor : .secondaryLabelColor
        let line = NSStackView(views: [
            label("\(number)", size: 12, color: secondary, monospaced: true),
            label(candidate.hanja, size: 17, color: text),
            label(candidate.meaning, size: 12, color: secondary),
        ])
        line.spacing = 8
        line.edgeInsets = NSEdgeInsets(top: 2, left: 6, bottom: 2, right: 10)
        line.translatesAutoresizingMaskIntoConstraints = false

        let container = Row()
        container.wantsLayer = true
        container.layer?.cornerRadius = 5
        container.layer?.backgroundColor = highlighted ? NSColor.selectedContentBackgroundColor.cgColor : nil
        container.addSubview(line)
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            line.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            line.topAnchor.constraint(equalTo: container.topAnchor),
            line.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    private func label(_ string: String, size: CGFloat, color: NSColor, monospaced: Bool = false) -> NSTextField {
        let field = NSTextField(labelWithString: string)
        field.font = monospaced ? .monospacedDigitSystemFont(ofSize: size, weight: .regular) : .systemFont(ofSize: size)
        field.textColor = color
        return field
    }
}
