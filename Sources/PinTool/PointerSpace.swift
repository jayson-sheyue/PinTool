import AppKit
import CoreGraphics

enum PointerSpace {
    /// Cocoa points use a bottom-left origin. CGEvent points use a top-left origin on the primary display.
    static func cgPoint(fromCocoa point: CGPoint) -> CGPoint {
        let height = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.main?.frame.height
            ?? 0
        return CGPoint(x: point.x, y: height - point.y)
    }

    static func warp(toCocoa point: CGPoint) {
        let cg = cgPoint(fromCocoa: point)
        CGWarpMouseCursorPosition(cg)
        CGAssociateMouseAndMouseCursorPosition(1)
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: cg,
            mouseButton: .left
        ) else { return }
        event.post(tap: .cghidEventTap)
    }

    /// `sign` -1 scrolls toward content below the fold. The opposite sign is only used when the first attempt does not move the page.
    static func scroll(pixels: Int, sign: Int32, atCocoa point: CGPoint, shouldStop: () -> Bool) async {
        let cg = cgPoint(fromCocoa: point)
        let source = CGEventSource(stateID: .hidSystemState)
        var left = max(0, pixels)
        while left > 0 {
            if shouldStop() { return }
            let step = min(80, left)
            guard let event = CGEvent(
                scrollWheelEvent2Source: source,
                units: .pixel,
                wheelCount: 1,
                wheel1: sign * Int32(step),
                wheel2: 0,
                wheel3: 0
            ) else { return }
            event.location = cg
            event.post(tap: .cghidEventTap)
            left -= step
            if left > 0 {
                try? await Task.sleep(nanoseconds: 4_000_000)
            }
        }
    }
}
