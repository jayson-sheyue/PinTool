import AppKit
import Foundation
import SwiftUI

/// Draws the same pin.fill used in the menu bar, sitting on warm paper.
/// The sheet is the macOS app-icon rounded rectangle, with transparent corners,
/// so the logo matches Finder even where the system mask is not applied.
let canvas = 1024
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = root.appendingPathComponent("PinTool.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let master = renderMaster(side: canvas)
let sizes = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]
for (side, name) in sizes {
    let image = side == canvas ? master : scale(master, to: side)
    try pngData(image).write(to: iconset.appendingPathComponent(name))
}
try pngData(master).write(to: root.appendingPathComponent("preview-icon.png"))
try pngData(scale(master, to: 128)).write(to: root.appendingPathComponent("preview-128.png"))
try pngData(scale(master, to: 32)).write(to: root.appendingPathComponent("preview-32.png"))
requireRoundedCorners(master)

private func renderMaster(side: Int) -> NSImage {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let context = CGContext(
        data: nil,
        width: side,
        height: side,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fputs("could not create icon context\n", stderr)
        exit(1)
    }
    let rect = CGRect(x: 0, y: 0, width: side, height: side)
    context.clear(rect)
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.interpolationQuality = .high
    let previous = NSGraphicsContext.current
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    context.saveGState()
    context.addPath(iconShape(in: rect))
    context.clip()
    drawPaper(in: rect)
    drawPin(in: rect)
    context.restoreGState()
    NSGraphicsContext.current = previous
    guard let rendered = context.makeImage() else {
        fputs("could not render icon\n", stderr)
        exit(1)
    }
    return NSImage(cgImage: rendered, size: NSSize(width: side, height: side))
}

/// Continuous rounded rectangle used by macOS app icons since Big Sur.
/// Corner radius is 22.37% of the side, the proportion in Apple's icon grid.
private func iconShape(in rect: CGRect) -> CGPath {
    let radius = min(rect.width, rect.height) * 0.2237
    return RoundedRectangle(cornerRadius: radius, style: .continuous)
        .path(in: rect)
        .cgPath
}

private func drawPaper(in rect: NSRect) {
    let colors = [
        NSColor(srgbRed: 0.975, green: 0.965, blue: 0.945, alpha: 1).cgColor,
        NSColor(srgbRed: 0.90, green: 0.875, blue: 0.835, alpha: 1).cgColor,
    ]
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: [0, 1])!
    let context = NSGraphicsContext.current!.cgContext
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: rect.midX, y: rect.maxY),
        end: CGPoint(x: rect.midX, y: rect.minY),
        options: []
    )
}

private func drawPin(in rect: NSRect) {
    guard let symbol = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 800, weight: .regular)),
          let cropped = opaqueImage(from: symbol)
    else { return }
    cropped.isTemplate = true
    let scale = min(rect.width * 0.58 / cropped.size.width, rect.height * 0.70 / cropped.size.height)
    let width = cropped.size.width * scale
    let height = cropped.size.height * scale
    let dest = NSRect(
        x: rect.midX - width / 2,
        y: rect.midY - height / 2,
        width: width,
        height: height
    )

    let shadow = NSShadow()
    shadow.shadowColor = NSColor(srgbRed: 0.20, green: 0.15, blue: 0.10, alpha: 0.22)
    shadow.shadowOffset = NSSize(width: 0, height: -rect.height * 0.012)
    shadow.shadowBlurRadius = rect.width * 0.018
    shadow.set()
    NSColor(srgbRed: 0.14, green: 0.13, blue: 0.12, alpha: 1).set()
    cropped.draw(in: dest, from: .zero, operation: .sourceOver, fraction: 1)

    shadow.shadowColor = NSColor.clear
    shadow.set()
    cropped.draw(in: dest, from: .zero, operation: .sourceOver, fraction: 1)
}

/// Drops the symbol's built-in padding so the pin can fill the icon.
private func opaqueImage(from symbol: NSImage) -> NSImage? {
    let rendered = NSImage(size: symbol.size, flipped: false) { _ in
        symbol.draw(in: NSRect(origin: .zero, size: symbol.size))
        return true
    }
    guard let tiff = rendered.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let cgImage = rep.cgImage else { return nil }
    let width = cgImage.width
    let height = cgImage.height
    guard let data = cgImage.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return nil }
    let rowBytes = cgImage.bytesPerRow
    let bytesPerPixel = max(1, cgImage.bitsPerPixel / 8)
    var minX = width
    var minY = height
    var maxX = 0
    var maxY = 0
    for y in 0..<height {
        let row = bytes.advanced(by: y * rowBytes)
        for x in 0..<width {
            let alpha: UInt8
            if bytesPerPixel >= 4 {
                alpha = row[x * bytesPerPixel + (cgImage.alphaInfo == .premultipliedFirst || cgImage.alphaInfo == .first || cgImage.alphaInfo == .noneSkipFirst ? 0 : 3)]
            } else {
                alpha = 255
            }
            if alpha > 16 {
                if x < minX { minX = x }
                if y < minY { minY = y }
                if x > maxX { maxX = x }
                if y > maxY { maxY = y }
            }
        }
    }
    guard maxX > minX, maxY > minY else { return nil }
    let crop = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    guard let part = cgImage.cropping(to: crop) else { return nil }
    return NSImage(cgImage: part, size: NSSize(width: crop.width, height: crop.height))
}

private func scale(_ image: NSImage, to side: Int) -> NSImage {
    var proposed = NSRect(origin: .zero, size: image.size)
    guard let source = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else { return image }
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let context = CGContext(
        data: nil,
        width: side,
        height: side,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return image }
    context.interpolationQuality = .high
    context.clear(CGRect(x: 0, y: 0, width: side, height: side))
    context.draw(source, in: CGRect(x: 0, y: 0, width: side, height: side))
    guard let scaled = context.makeImage() else { return image }
    return NSImage(cgImage: scaled, size: NSSize(width: side, height: side))
}

private func requireRoundedCorners(_ image: NSImage) {
    var proposed = NSRect(origin: .zero, size: image.size)
    guard let cg = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil),
          let data = cg.dataProvider?.data,
          let bytes = CFDataGetBytePtr(data) else {
        fputs("could not read icon pixels\n", stderr)
        exit(1)
    }
    let width = cg.width
    let height = cg.height
    let rowBytes = cg.bytesPerRow
    let bytesPerPixel = max(1, cg.bitsPerPixel / 8)
    func alpha(_ x: Int, _ y: Int) -> UInt8 {
        let offset = y * rowBytes + x * bytesPerPixel
        if bytesPerPixel >= 4 {
            let alphaIndex = cg.alphaInfo == .premultipliedFirst || cg.alphaInfo == .first || cg.alphaInfo == .noneSkipFirst ? 0 : 3
            return bytes[offset + alphaIndex]
        }
        return 255
    }
    let corner = width / 20
    let samples = [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1), (corner, corner)]
    for (x, y) in samples where alpha(x, y) > 8 {
        fputs("icon corners are still square\n", stderr)
        exit(1)
    }
    if alpha(width / 2, 2) < 200 || alpha(2, height / 2) < 200 {
        fputs("rounded icon no longer reaches the middle of each edge\n", stderr)
        exit(1)
    }
}

private func pngData(_ image: NSImage) -> Data {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        fputs("could not encode icon\n", stderr)
        exit(1)
    }
    return png
}
