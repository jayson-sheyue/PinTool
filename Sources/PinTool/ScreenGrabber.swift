import AppKit
import CoreVideo
import PinToolCore
import ScreenCaptureKit

struct GrabbedImage {
    var image: CGImage
    var scale: CGFloat
}

enum GrabError: LocalizedError {
    case noDisplay
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noDisplay:
            return "没有找到这块区域所在的显示器。"
        case .failed(let message):
            return message
        }
    }
}

struct CaptureTarget {
    var filter: SCContentFilter
    var configuration: SCStreamConfiguration
    var scale: CGFloat
}

enum ScreenGrabber {
    @MainActor
    static func prepare(rect: CGRect) async throws -> CaptureTarget {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY)) })
            ?? NSScreen.screens.first(where: { $0.frame.intersects(rect) }) else {
            throw GrabError.noDisplay
        }

        let content = try await SCShareableContent.current
        guard let display = content.displays.first(where: { framesMatch($0.frame, screen.frame) }) else {
            throw GrabError.noDisplay
        }
        guard let local = DisplayCoordinates.clampedSourceRect(selection: rect, displayFrame: display.frame) else {
            throw GrabError.failed("选区不在屏幕内。")
        }

        let pid = getpid()
        let mine = content.windows.filter { $0.owningApplication?.processID == pid }
        let filter = SCContentFilter(display: display, excludingWindows: mine)
        let scale = screen.backingScaleFactor
        let config = SCStreamConfiguration()
        config.width = max(1, Int((local.width * scale).rounded()))
        config.height = max(1, Int((local.height * scale).rounded()))
        config.sourceRect = local
        config.showsCursor = false
        config.showMouseClicks = false
        config.capturesAudio = false
        config.scalesToFit = false
        config.preservesAspectRatio = false
        config.pixelFormat = kCVPixelFormatType_32BGRA
        return CaptureTarget(filter: filter, configuration: config, scale: scale)
    }

    @MainActor
    static func grab(rect: CGRect) async throws -> GrabbedImage {
        let target = try await prepare(rect: rect)
        let image = try await capture(filter: target.filter, config: target.configuration)
        guard image.width > 0, image.height > 0 else {
            throw GrabError.failed("截到的画面是空的。")
        }
        return GrabbedImage(image: image, scale: target.scale)
    }

    private static func capture(filter: SCContentFilter, config: SCStreamConfiguration) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { image, error in
                if let image {
                    continuation.resume(returning: image)
                } else {
                    let message = error?.localizedDescription ?? "没有返回图像"
                    continuation.resume(throwing: GrabError.failed("截图失败：\(message)"))
                }
            }
        }
    }

    private static func framesMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) < 2
            && abs(lhs.origin.y - rhs.origin.y) < 2
            && abs(lhs.width - rhs.width) < 2
            && abs(lhs.height - rhs.height) < 2
    }
}
