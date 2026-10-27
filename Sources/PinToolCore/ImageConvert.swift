import CoreGraphics
import CoreVideo
import Foundation

public enum ImageConvert {
    private static var bitmapInfo: UInt32 {
        CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
    }

    /// Reads a CGImage into a top-row-first BGRA buffer.
    public static func buffer(from image: CGImage) -> PixelBuffer? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drew = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let context = CGContext(
                    data: base,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: bitmapInfo
                  ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else { return nil }
        return PixelBuffer(width: width, height: height, bytes: bytes)
    }

    /// Copies a BGRA pixel buffer. The source is only valid for the duration of the call.
    public static func buffer(from pixelBuffer: CVPixelBuffer) -> PixelBuffer? {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA,
              !CVPixelBufferIsPlanar(pixelBuffer) else { return nil }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0 else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { raw in
            guard let destination = raw.baseAddress else { return }
            if rowBytes == width * 4 {
                destination.copyMemory(from: base, byteCount: width * height * 4)
            } else {
                for y in 0..<height {
                    destination.advanced(by: y * width * 4).copyMemory(
                        from: base.advanced(by: y * rowBytes),
                        byteCount: width * 4
                    )
                }
            }
        }
        return PixelBuffer(width: width, height: height, bytes: bytes)
    }

    public static func cgImage(from buffer: PixelBuffer) -> CGImage? {
        let data = Data(buffer.bytes) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(
            width: buffer.width,
            height: buffer.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: buffer.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}
