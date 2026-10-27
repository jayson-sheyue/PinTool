import CoreGraphics

public enum DisplayCoordinates {
    /// `selection` and `displayFrame` use Cocoa screen coordinates: origin at the bottom-left of the primary display, the same space as `NSScreen.frame` and `SCDisplay.frame`.
    /// ScreenCaptureKit `sourceRect` is display-local with its origin at the top-left of that display and y growing downward. Measured on macOS 15.7: a rect 80 points below the top of the display is `sourceRect.y == 80`.
    public static func sourceRect(selection: CGRect, displayFrame: CGRect) -> CGRect {
        let localX = selection.origin.x - displayFrame.origin.x
        let localYFromBottom = selection.origin.y - displayFrame.origin.y
        let yFromTop = displayFrame.height - localYFromBottom - selection.height
        return CGRect(x: localX, y: yFromTop, width: selection.width, height: selection.height)
    }

    public static func clampedSourceRect(selection: CGRect, displayFrame: CGRect) -> CGRect? {
        let local = sourceRect(selection: selection, displayFrame: displayFrame)
        let bounds = CGRect(x: 0, y: 0, width: displayFrame.width, height: displayFrame.height)
        let clamped = local.intersection(bounds)
        guard !clamped.isNull, !clamped.isEmpty, clamped.width >= 1, clamped.height >= 1 else { return nil }
        return clamped
    }
}
