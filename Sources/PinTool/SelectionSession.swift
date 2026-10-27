import AppKit

enum SelectionMode {
    case region
    case longCapture

    var hint: String {
        switch self {
        case .region:
            return "拖出范围，松开后钉住 · Esc 取消"
        case .longCapture:
            return "框住基准区域。松开后向下滚，点绿勾结束 · Esc 取消"
        }
    }
}

final class SelectionSession: NSObject {
    var onComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    private(set) var previousApplication: NSRunningApplication?
    private(set) var mode: SelectionMode = .region
    private var rect: CGRect = .zero
    private var anchor: CGPoint?
    private var anchorScreen: NSScreen?
    private var windows: [SelectionWindow] = []
    private var keyMonitor: Any?
    private var active = false
    private var cursorPushed = false

    func begin(mode: SelectionMode) {
        end()
        self.mode = mode
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != NSRunningApplication.current.processIdentifier {
            previousApplication = front
        } else {
            previousApplication = nil
        }
        active = true
        windows = NSScreen.screens.map { screen in
            let window = SelectionWindow(screen: screen, session: self)
            window.orderFrontRegardless()
            return window
        }
        NSApp.activate()
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }),
           let window = windows.first(where: { $0.screenFrame == screen.frame }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            windows.first?.makeKeyAndOrderFront(nil)
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.active else { return event }
            if event.keyCode == 53 {
                self.cancel()
                return nil
            }
            return event
        }
        NSCursor.crosshair.push()
        cursorPushed = true
    }

    func end() {
        guard active || !windows.isEmpty else { return }
        active = false
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        anchor = nil
        rect = .zero
        if cursorPushed {
            NSCursor.pop()
            cursorPushed = false
        }
    }

    func cancel() {
        guard active else { return }
        end()
        onCancel?()
    }

    func mouseDown(at point: CGPoint) {
        guard active else { return }
        anchor = point
        anchorScreen = NSScreen.screens.first { $0.frame.contains(point) }
        rect = CGRect(origin: point, size: .zero)
        refresh()
    }

    func mouseDragged(to point: CGPoint) {
        guard active, let anchor else { return }
        rect = normalized(anchor, point)
        refresh()
    }

    func mouseUp(at point: CGPoint) {
        guard active, let anchor else { return }
        let selection = normalized(anchor, point)
        guard selection.width >= 8, selection.height >= 8 else {
            cancel()
            return
        }
        end()
        onComplete?(selection)
    }

    fileprivate func draw(in view: SelectionView, screen: NSScreen) {
        let bounds = view.bounds
        let shade = NSBezierPath(rect: bounds)
        let global = rect
        var localHole: CGRect?
        if global.width > 1, global.height > 1, let window = view.window {
            let local = window.convertFromScreen(global)
            if local.intersects(bounds), local.width > 1, local.height > 1 {
                shade.append(NSBezierPath(rect: local))
                shade.windingRule = .evenOdd
                localHole = local
            }
        }
        NSColor.black.withAlphaComponent(0.32).setFill()
        shade.fill()

        if let local = localHole {
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: local.insetBy(dx: 0.75, dy: 0.75))
            border.lineWidth = 1.5
            border.stroke()
            let label = "\(Int(global.width.rounded())) × \(Int(global.height.rounded()))"
            drawBadge(label, near: local, in: bounds)
        }

        if screen.frame == anchorScreen?.frame || (anchorScreen == nil && screen.frame.contains(NSEvent.mouseLocation)) {
            drawHint(in: bounds)
        }
    }

    private func drawBadge(_ text: String, near rect: CGRect, in bounds: CGRect) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        var origin = NSPoint(x: rect.minX, y: rect.maxY + 8)
        if origin.y + size.height + 8 > bounds.maxY {
            origin.y = rect.minY + 8
        }
        origin.x = min(max(8, origin.x), bounds.maxX - size.width - 16)
        let background = NSRect(x: origin.x - 6, y: origin.y - 3, width: size.width + 12, height: size.height + 6)
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: background, xRadius: 5, yRadius: 5).fill()
        (text as NSString).draw(at: origin, withAttributes: attributes)
    }

    private func drawHint(in bounds: CGRect) {
        let text = mode.hint
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let width = min(bounds.width - 32, size.width + 24)
        let height = size.height + 12
        let background = NSRect(x: (bounds.width - width) / 2, y: bounds.maxY - height - 28, width: width, height: height)
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: background, xRadius: 8, yRadius: 8).fill()
        let origin = NSPoint(x: background.midX - size.width / 2, y: background.minY + 6)
        (text as NSString).draw(at: origin, withAttributes: attributes)
    }

    private func refresh() {
        windows.forEach { $0.contentView?.needsDisplay = true }
    }

    private func normalized(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        var rect = CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(a.x - b.x),
            height: abs(a.y - b.y)
        )
        if let screen = anchorScreen {
            rect = rect.intersection(screen.frame)
        }
        if rect.isNull { return .zero }
        return rect
    }
}

private final class SelectionWindow: NSWindow {
    let screenFrame: CGRect
    private weak var session: SelectionSession?

    init(screen: NSScreen, session: SelectionSession) {
        screenFrame = screen.frame
        self.session = session
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        sharingType = .none
        isReleasedWhenClosed = false
        let view = SelectionView(session: session, screen: screen)
        contentView = view
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            session?.cancel()
            return
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        session?.cancel()
    }
}

private final class SelectionView: NSView {
    private weak var session: SelectionSession?
    private let screen: NSScreen

    init(session: SelectionSession, screen: NSScreen) {
        self.session = session
        self.screen = screen
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        session?.draw(in: self, screen: screen)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        if event.buttonNumber == 1 {
            session?.cancel()
            return
        }
        session?.mouseDown(at: NSEvent.mouseLocation)
    }

    override func mouseDragged(with event: NSEvent) {
        session?.mouseDragged(to: NSEvent.mouseLocation)
    }

    override func mouseUp(with event: NSEvent) {
        session?.mouseUp(at: NSEvent.mouseLocation)
    }

    override func rightMouseDown(with event: NSEvent) {
        session?.cancel()
    }
}
