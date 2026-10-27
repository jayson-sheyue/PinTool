import AppKit

final class StatusHUD {
    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "")
    private var hideDuringCapture = false

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 36),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.sharingType = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none

        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        let background = HUDBackground()
        background.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = background
        background.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -14),
            label.topAnchor.constraint(equalTo: background.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -8)
        ])
    }

    func show(_ text: String, avoiding rect: CGRect? = nil, on screen: NSScreen? = nil) {
        label.stringValue = text
        let size = label.intrinsicContentSize
        let width = min(560, max(160, size.width + 28))
        let height: CGFloat = 36
        let host = screen
            ?? NSScreen.screens.first(where: { rect.map($0.frame.intersects) ?? false })
            ?? NSScreen.main
        guard let host else { return }
        let visible = host.visibleFrame
        var frame = NSRect(x: visible.midX - width / 2, y: visible.maxY - height - 16, width: width, height: height)
        if let rect, frame.intersects(rect.insetBy(dx: -8, dy: -8)) {
            frame.origin.y = visible.minY + 16
        }
        hideDuringCapture = rect.map { frame.intersects($0.insetBy(dx: -8, dy: -8)) } ?? false
        panel.setFrame(frame, display: true)
        if !hideDuringCapture {
            panel.orderFrontRegardless()
        }
    }

    func update(_ text: String) {
        label.stringValue = text
        let width = min(560, max(160, label.intrinsicContentSize.width + 28))
        var frame = panel.frame
        let midX = frame.midX
        frame.size.width = width
        frame.origin.x = midX - width / 2
        panel.setFrame(frame, display: true)
        if !hideDuringCapture {
            panel.orderFrontRegardless()
        }
    }

    func hideForCapture() {
        panel.orderOut(nil)
    }

    func restoreAfterCapture() {
        if !hideDuringCapture, !label.stringValue.isEmpty {
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        label.stringValue = ""
        panel.orderOut(nil)
    }
}

private final class HUDBackground: NSView {
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
    }
}
