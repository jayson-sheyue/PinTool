import AppKit

/// A clickable check beside the long-capture box. Clicking it finishes the capture.
final class FinishMark: NSObject {
    private var panel: NSPanel?
    var onConfirm: (() -> Void)?

    func show(near rect: CGRect, on screen: NSScreen?) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setFrame(Self.frame(near: rect, on: screen), display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 46, height: 46),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.sharingType = .none
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        let mark = CheckMarkView(frame: NSRect(x: 0, y: 0, width: 46, height: 46))
        mark.onConfirm = { [weak self] in
            self?.onConfirm?()
        }
        panel.contentView = mark
        return panel
    }

    private static func frame(near rect: CGRect, on screen: NSScreen?) -> CGRect {
        let side: CGFloat = 46
        let visible = screen?.visibleFrame ?? rect
        var frame = CGRect(x: rect.maxX + 8, y: rect.midY - side / 2, width: side, height: side)
        if frame.maxX > visible.maxX - 4 {
            frame.origin.x = min(rect.maxX, visible.maxX - 4) - side - 6
        }
        if frame.minX < visible.minX + 4 {
            frame.origin.x = visible.minX + 4
        }
        if frame.minY < visible.minY + 4 {
            frame.origin.y = visible.minY + 4
        }
        if frame.maxY > visible.maxY - 4 {
            frame.origin.y = visible.maxY - side - 4
        }
        return frame
    }
}

private final class CheckMarkView: NSView {
    var onConfirm: (() -> Void)?
    private var pressed = false

    override var isOpaque: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        pressed = true
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        pressed = false
        needsDisplay = true
        if inside {
            onConfirm?()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let circle = bounds.insetBy(dx: 3, dy: 3)
        NSColor.black.withAlphaComponent(0.28).setFill()
        NSBezierPath(ovalIn: circle.offsetBy(dx: 0, dy: -1)).fill()
        let fill = pressed ? NSColor.systemGreen.blended(withFraction: 0.22, of: .black) ?? .systemGreen : .systemGreen
        fill.setFill()
        NSBezierPath(ovalIn: circle).fill()
        NSColor.white.withAlphaComponent(0.9).setStroke()
        let ring = NSBezierPath(ovalIn: circle.insetBy(dx: 1.2, dy: 1.2))
        ring.lineWidth = 1.5
        ring.stroke()

        let path = NSBezierPath()
        let width = bounds.width
        let height = bounds.height
        path.move(to: NSPoint(x: width * 0.30, y: height * 0.52))
        path.line(to: NSPoint(x: width * 0.44, y: height * 0.34))
        path.line(to: NSPoint(x: width * 0.72, y: height * 0.66))
        path.lineWidth = 3.4
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        NSColor.white.setStroke()
        path.stroke()
    }
}
