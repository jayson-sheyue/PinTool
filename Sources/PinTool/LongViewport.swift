import AppKit

/// The baseline rectangle stays on top of the page and does not take clicks or scrolling.
final class LongViewport {
    private var panel: NSPanel?

    func show(rect: CGRect) {
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.setFrame(rect, display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.sharingType = .none
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.contentView = LongViewportView()
        return panel
    }
}

private final class LongViewportView: NSView {
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width > 2, bounds.height > 2 else { return }
        NSColor.white.setStroke()
        let outer = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
        outer.lineWidth = 2
        outer.stroke()
        NSColor.black.withAlphaComponent(0.55).setStroke()
        let inner = NSBezierPath(rect: bounds.insetBy(dx: 3, dy: 3))
        inner.lineWidth = 1
        inner.stroke()
    }
}
