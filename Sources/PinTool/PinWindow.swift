import AppKit

final class PinBoard {
    private var pins: [PinPanel] = []
    var onNotice: ((String) -> Void)?

    var isEmpty: Bool { pins.isEmpty }

    @discardableResult
    func add(image: CGImage, scale: CGFloat, aligningTopLeftTo selection: CGRect, avoiding: CGRect? = nil) -> PinPanel? {
        guard Thread.isMainThread else {
            var made: PinPanel?
            DispatchQueue.main.sync {
                made = self.add(image: image, scale: scale, aligningTopLeftTo: selection, avoiding: avoiding)
            }
            return made
        }
        guard image.width >= 1, image.height >= 1, scale.isFinite, scale > 0 else { return nil }
        let pin = PinPanel(image: image, scale: scale, aligningTopLeftTo: selection)
        pin.onClose = { [weak self, weak pin] in
            guard let self, let pin else { return }
            self.close(pin)
        }
        pin.onCopied = { [weak self] in
            self?.onNotice?("已拷贝到剪贴板")
        }
        pins.append(pin)
        if let avoiding {
            pin.park(beside: avoiding)
        }
        pin.orderFrontRegardless()
        return pin
    }

    func coversPointer() -> Bool {
        let point = NSEvent.mouseLocation
        return pins.contains { $0.frame.contains(point) }
    }

    func stillHas(_ pin: PinPanel) -> Bool {
        pins.contains { $0 === pin }
    }

    func closeAll() {
        let existing = pins
        pins.removeAll()
        existing.forEach { $0.close() }
    }

    func suspendIntersecting(_ rect: CGRect) -> [PinPanel] {
        let hidden = pins.filter { $0.frame.intersects(rect) }
        hidden.forEach { $0.orderOut(nil) }
        return hidden
    }

    func resume(_ panels: [PinPanel]) {
        let live = panels.filter { pins.contains($0) }
        live.forEach { $0.orderFrontRegardless() }
    }

    private func close(_ pin: PinPanel) {
        pins.removeAll { $0 === pin }
        pin.close()
    }
}

final class PinPanel: NSPanel, NSWindowDelegate {
    var onClose: (() -> Void)?
    var onCopied: (() -> Void)?
    private var imagePointSize: NSSize
    private var zoom: CGFloat
    private var minimumZoom: CGFloat
    private let maximumZoom: CGFloat = 8
    private var adjustingFrame = false

    init(image: CGImage, scale: CGFloat, aligningTopLeftTo selection: CGRect) {
        let safeScale = max(scale, 1)
        imagePointSize = NSSize(
            width: CGFloat(image.width) / safeScale,
            height: CGFloat(image.height) / safeScale
        )
        let screen = NSScreen.screens.first(where: { $0.visibleFrame.contains(CGPoint(x: selection.midX, y: selection.midY)) })
            ?? NSScreen.main
        let visible = (screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600)).insetBy(dx: 24, dy: 24)
        let fit = min(1, visible.width * 0.86 / imagePointSize.width, visible.height * 0.86 / imagePointSize.height)
        zoom = max(0.15, fit.isFinite ? fit : 1)
        minimumZoom = zoom

        let size = NSSize(
            width: max(1, imagePointSize.width * zoom),
            height: max(1, imagePointSize.height * zoom)
        )
        var frame = NSRect(
            x: selection.minX,
            y: selection.maxY - size.height,
            width: size.width,
            height: size.height
        )
        frame = PinPanel.clamped(frame, into: screen?.visibleFrame ?? visible)

        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        sharingType = .readOnly
        animationBehavior = .none
        isReleasedWhenClosed = false
        delegate = self

        let nsImage = NSImage(cgImage: image, size: imagePointSize)
        let view = PinContentView(image: nsImage)
        view.onClose = { [weak self] in self?.onClose?() }
        view.onCopied = { [weak self] in self?.onCopied?() }
        view.onZoom = { [weak self] factor, point in
            self?.zoom(by: factor, around: point)
        }
        contentView = view
        view.apply(zoom: zoom, origin: .zero, imagePointSize: imagePointSize)
        invalidateShadow()
    }

    func replace(image: CGImage, scale: CGFloat) {
        let safeScale = max(scale, 1)
        imagePointSize = NSSize(
            width: CGFloat(image.width) / safeScale,
            height: CGFloat(image.height) / safeScale
        )
        (contentView as? PinContentView)?.update(image: NSImage(cgImage: image, size: imagePointSize))
    }

    func setPassThrough(_ pass: Bool) {
        ignoresMouseEvents = pass
        sharingType = pass ? .none : .readOnly
        hasShadow = !pass
        isOpaque = pass
        backgroundColor = pass ? .white : .clear
    }

    /// Live long-capture preview: glued to the left of the baseline, top-aligned with it.
    /// As the image gets taller, the frame lengthens downward, then scales down so it gets thinner and still fits.
    func layoutLeft(of selection: CGRect) {
        let screen = NSScreen.screens.first { $0.frame.intersects(selection) } ?? self.screen
        let visible = screen?.visibleFrame ?? frame
        let gap: CGFloat = 8
        let leftRoom = selection.minX - visible.minX - gap - 8
        let maxHeight = max(48, visible.height - 12)
        let maxWidth = leftRoom >= 48 ? leftRoom : max(48, min(imagePointSize.width, visible.width - 16))
        let fit = min(
            1,
            maxWidth / max(imagePointSize.width, 1),
            maxHeight / max(imagePointSize.height, 1)
        )
        zoom = max(0.05, fit.isFinite ? fit : 1)
        let size = NSSize(
            width: max(1, imagePointSize.width * zoom),
            height: max(1, imagePointSize.height * zoom)
        )
        var origin: NSPoint
        if leftRoom >= 48 {
            origin = NSPoint(x: selection.minX - gap - size.width, y: selection.maxY - size.height)
        } else {
            origin = NSPoint(x: max(visible.minX + 4, selection.minX), y: selection.minY - gap - size.height)
        }
        if origin.x < visible.minX + 4 {
            origin.x = visible.minX + 4
        }
        if origin.x + size.width > visible.maxX - 4 {
            origin.x = visible.maxX - 4 - size.width
        }
        if origin.y < visible.minY + 4 {
            origin.y = visible.minY + 4
        }
        if origin.y + size.height > visible.maxY - 4 {
            origin.y = visible.maxY - 4 - size.height
        }
        if CGRect(origin: origin, size: size).intersects(selection) {
            origin.x = min(origin.x, selection.minX - gap - size.width)
        }
        let next = NSRect(origin: origin, size: size)
        adjustingFrame = true
        if next != frame {
            setFrame(next, display: true)
        }
        adjustingFrame = false
        minimumZoom = zoom
        (contentView as? PinContentView)?.apply(zoom: zoom, origin: .zero, imagePointSize: imagePointSize)
        if hasShadow {
            invalidateShadow()
        }
    }

    func park(beside selection: CGRect) {
        let size = frame.size
        let screen = self.screen ?? NSScreen.screens.first { $0.frame.intersects(selection) }
        let visible = screen?.visibleFrame ?? frame
        let gap: CGFloat = 12
        var candidate = NSRect(
            x: selection.maxX + gap,
            y: selection.maxY - size.height,
            width: size.width,
            height: size.height
        )
        if candidate.maxX > visible.maxX - 4 {
            candidate.origin.x = selection.minX - gap - size.width
        }
        if candidate.minX < visible.minX + 4 || candidate.intersects(selection) {
            candidate.origin.x = min(max(selection.minX, visible.minX + 4), max(visible.minX + 4, visible.maxX - size.width - 4))
            candidate.origin.y = selection.minY - gap - size.height
        }
        adjustingFrame = true
        setFrame(PinPanel.clamped(candidate, into: visible), display: true)
        adjustingFrame = false
    }

    func windowDidMove(_ notification: Notification) {
        guard !adjustingFrame else { return }
        let clamped = PinPanel.clamped(frame, into: nil)
        guard clamped != frame else { return }
        adjustingFrame = true
        setFrame(clamped, display: true)
        adjustingFrame = false
    }

    private func zoom(by factor: CGFloat, around screenPoint: CGPoint) {
        let nextZoom = min(maximumZoom, max(minimumZoom, zoom * factor))
        guard abs(nextZoom - zoom) > 0.001, let view = contentView as? PinContentView else { return }
        let viewPoint = view.convert(convertPoint(fromScreen: screenPoint), from: nil)
        let imagePoint = view.imagePoint(at: viewPoint)
        let desired = NSSize(width: imagePointSize.width * nextZoom, height: imagePointSize.height * nextZoom)
        let visible = (screen?.visibleFrame ?? frame).insetBy(dx: 6, dy: 6)
        zoom = nextZoom

        if desired.width <= visible.width && desired.height <= visible.height {
            var nextFrame = NSRect(
                x: screenPoint.x - imagePoint.x * nextZoom,
                y: screenPoint.y - imagePoint.y * nextZoom,
                width: max(1, desired.width),
                height: max(1, desired.height)
            )
            nextFrame = PinPanel.clamped(nextFrame, into: visible)
            adjustingFrame = true
            setFrame(nextFrame, display: true)
            adjustingFrame = false
            view.apply(zoom: nextZoom, origin: .zero, imagePointSize: imagePointSize)
            invalidateShadow()
            return
        }

        let newSize = NSSize(
            width: min(visible.width, max(1, desired.width)),
            height: min(visible.height, max(1, desired.height))
        )
        var nextFrame = NSRect(
            x: screenPoint.x - newSize.width / 2,
            y: screenPoint.y - newSize.height / 2,
            width: newSize.width,
            height: newSize.height
        )
        if nextFrame.minX < visible.minX { nextFrame.origin.x = visible.minX }
        if nextFrame.minY < visible.minY { nextFrame.origin.y = visible.minY }
        if nextFrame.maxX > visible.maxX { nextFrame.origin.x = visible.maxX - nextFrame.width }
        if nextFrame.maxY > visible.maxY { nextFrame.origin.y = visible.maxY - nextFrame.height }
        adjustingFrame = true
        setFrame(nextFrame, display: true)
        adjustingFrame = false
        let anchored = view.convert(convertPoint(fromScreen: screenPoint), from: nil)
        view.apply(
            zoom: nextZoom,
            origin: NSPoint(
                x: anchored.x - imagePoint.x * nextZoom,
                y: anchored.y - imagePoint.y * nextZoom
            ),
            imagePointSize: imagePointSize
        )
        view.clampImageOrigin()
        invalidateShadow()
    }

    private static func clamped(_ frame: NSRect, into preferred: CGRect?) -> NSRect {
        let screens = NSScreen.screens
        let screen = screens.first(where: { $0.visibleFrame.intersects(frame) })
            ?? screens.first(where: { preferred?.intersects($0.visibleFrame) ?? false })
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return frame }
        var next = frame
        if next.maxX < visible.minX + 80 { next.origin.x = visible.minX + 80 - next.width }
        if next.minX > visible.maxX - 80 { next.origin.x = visible.maxX - 80 }
        if next.maxY < visible.minY + 40 { next.origin.y = visible.minY + 40 - next.height }
        if next.minY > visible.maxY - 40 { next.origin.y = visible.maxY - 40 }
        return next
    }
}

private final class PinContentView: NSView {
    var onClose: (() -> Void)?
    var onCopied: (() -> Void)?
    var onZoom: ((CGFloat, CGPoint) -> Void)?
    private var image: NSImage
    private var zoom: CGFloat = 1
    private var imagePointSize: NSSize = .zero
    private var imageOrigin: CGPoint = .zero
    private var panning = false
    private var panStart = CGPoint.zero
    private var originAtPan = CGPoint.zero
    private let closeButton = CloseButton()

    init(image: NSImage) {
        self.image = image
        self.imagePointSize = image.size
        super.init(frame: .zero)
        clipsToBounds = true
        closeButton.isHidden = true
        closeButton.onClick = { [weak self] in self?.onClose?() }
        addSubview(closeButton)
    }

    func update(image: NSImage) {
        self.image = image
        needsDisplay = true
    }

    func apply(zoom: CGFloat, origin: CGPoint, imagePointSize: NSSize) {
        self.zoom = zoom
        self.imagePointSize = imagePointSize
        imageOrigin = origin
        needsDisplay = true
    }

    func imagePoint(at viewPoint: CGPoint) -> CGPoint {
        let scale = max(zoom, 0.01)
        return CGPoint(
            x: (viewPoint.x - imageOrigin.x) / scale,
            y: (viewPoint.y - imageOrigin.y) / scale
        )
    }

    func clampImageOrigin() {
        let scaledW = imagePointSize.width * zoom
        let scaledH = imagePointSize.height * zoom
        if scaledW <= bounds.width + 0.5 {
            imageOrigin.x = (bounds.width - scaledW) / 2
        } else {
            imageOrigin.x = min(0, max(bounds.width - scaledW, imageOrigin.x))
        }
        if scaledH <= bounds.height + 0.5 {
            imageOrigin.y = (bounds.height - scaledH) / 2
        } else {
            imageOrigin.y = min(0, max(bounds.height - scaledH, imageOrigin.y))
        }
        needsDisplay = true
    }

    private var overflows: Bool {
        imagePointSize.width * zoom > bounds.width + 1 || imagePointSize.height * zoom > bounds.height + 1
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var isOpaque: Bool { false }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.option) || !overflows {
            window?.performDrag(with: event)
            return
        }
        panning = true
        panStart = convert(event.locationInWindow, from: nil)
        originAtPan = imageOrigin
    }

    override func mouseDragged(with event: NSEvent) {
        guard panning else { return }
        let point = convert(event.locationInWindow, from: nil)
        imageOrigin = NSPoint(x: originAtPan.x + point.x - panStart.x, y: originAtPan.y + point.y - panStart.y)
        clampImageOrigin()
    }

    override func mouseUp(with event: NSEvent) {
        panning = false
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = NSRect(
            x: imageOrigin.x,
            y: imageOrigin.y,
            width: max(1, imagePointSize.width * zoom),
            height: max(1, imagePointSize.height * zoom)
        )
        image.draw(
            in: rect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: zoom >= 1 ? NSImageInterpolation.none : NSImageInterpolation.high]
        )
        NSColor.black.withAlphaComponent(0.45).setStroke()
        let outer = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        outer.lineWidth = 1
        outer.stroke()
        NSColor.white.withAlphaComponent(0.7).setStroke()
        let inner = NSBezierPath(rect: bounds.insetBy(dx: 1.5, dy: 1.5))
        inner.lineWidth = 1
        inner.stroke()
    }

    override func layout() {
        super.layout()
        let size: CGFloat = 28
        closeButton.frame = NSRect(x: bounds.width - size - 8, y: bounds.height - size - 8, width: size, height: size)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        closeButton.isHidden = false
        window?.makeFirstResponder(self)
        window?.makeKey()
    }

    override func mouseExited(with event: NSEvent) {
        closeButton.isHidden = true
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY
        guard abs(delta) > 0.01, let window else { return }
        let factor = exp(delta * (event.hasPreciseScrollingDeltas ? 0.0028 : 0.02))
        let screenPoint = window.convertToScreen(NSRect(origin: event.locationInWindow, size: .zero)).origin
        onZoom?(factor, screenPoint)
    }

    override func magnify(with event: NSEvent) {
        guard let window else { return }
        let screenPoint = window.convertToScreen(NSRect(origin: event.locationInWindow, size: .zero)).origin
        onZoom?(1 + event.magnification, screenPoint)
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let copy = NSMenuItem(title: "拷贝图像到剪贴板", action: #selector(copyFromMenu), keyEquivalent: "c")
        copy.keyEquivalentModifierMask = .command
        copy.target = self
        let close = NSMenuItem(title: "关闭这个钉图", action: #selector(closeFromMenu), keyEquivalent: "")
        close.target = self
        menu.addItem(copy)
        menu.addItem(close)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isCopyShortcut(event) {
            copyImage()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if isCopyShortcut(event) {
            copyImage()
            return
        }
        super.keyDown(with: event)
    }

    @objc private func copyFromMenu() {
        copyImage()
    }

    @objc private func closeFromMenu() {
        onClose?()
    }

    private func isCopyShortcut(_ event: NSEvent) -> Bool {
        event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers?.lowercased() == "c"
    }

    /// Puts the full pinned image on the general pasteboard. No file is written.
    private func copyImage() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard let tiff = image.tiffRepresentation else { return }
        var payload: [NSPasteboard.PasteboardType: Data] = [.tiff: tiff]
        if let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            payload[.png] = png
        }
        pasteboard.declareTypes(Array(payload.keys), owner: nil)
        for (type, data) in payload {
            pasteboard.setData(data, forType: type)
        }
        onCopied?()
    }
}

private final class CloseButton: NSView {
    var onClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("关闭钉图")
        toolTip = "关闭"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
        NSColor.black.withAlphaComponent(0.72).setFill()
        circle.fill()
        NSColor.white.withAlphaComponent(0.9).setStroke()
        circle.lineWidth = 1
        circle.stroke()

        let mark = NSBezierPath()
        let inset: CGFloat = 9
        mark.move(to: NSPoint(x: inset, y: inset))
        mark.line(to: NSPoint(x: bounds.width - inset, y: bounds.height - inset))
        mark.move(to: NSPoint(x: bounds.width - inset, y: inset))
        mark.line(to: NSPoint(x: inset, y: bounds.height - inset))
        NSColor.white.setStroke()
        mark.lineWidth = 1.5
        mark.lineCapStyle = .round
        mark.stroke()
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if bounds.contains(point) {
            onClick?()
        }
    }
}
