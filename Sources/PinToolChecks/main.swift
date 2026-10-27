import CoreGraphics
import Foundation
import PinToolCore

private var failures = 0

private func expect(_ condition: Bool, _ message: String, file: StaticString = #fileID, line: UInt = #line) {
    if !condition {
        failures += 1
        print("FAIL \(file):\(line) \(message)")
    }
}

private func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: StaticString = #fileID, line: UInt = #line) {
    if actual != expected {
        failures += 1
        print("FAIL \(file):\(line) \(message) actual=\(actual) expected=\(expected)")
    }
}

private func checkCoordinates() {
    let primary = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let selection = CGRect(x: 100, y: 200, width: 300, height: 50)
    expectEqual(
        DisplayCoordinates.sourceRect(selection: selection, displayFrame: primary),
        CGRect(x: 100, y: 550, width: 300, height: 50)
    )

    let secondary = CGRect(x: 1000, y: -200, width: 800, height: 600)
    let onSecondary = CGRect(x: 1100, y: -100, width: 40, height: 20)
    expectEqual(
        DisplayCoordinates.sourceRect(selection: onSecondary, displayFrame: secondary),
        CGRect(x: 100, y: 480, width: 40, height: 20)
    )

    let display = CGRect(x: 0, y: 0, width: 200, height: 100)
    let hanging = CGRect(x: 150, y: -20, width: 100, height: 40)
    expectEqual(
        DisplayCoordinates.clampedSourceRect(selection: hanging, displayFrame: display),
        CGRect(x: 150, y: 80, width: 50, height: 20)
    )
}

private func checkRoundTrip() {
    let original = makeBuffer(width: 3, height: 2) { x, y in
        (b: UInt8(x * 20), g: UInt8(y * 30), r: UInt8(40 + x + y), a: 255)
    }
    guard let image = ImageConvert.cgImage(from: original), let back = ImageConvert.buffer(from: image) else {
        expect(false, "image round trip produced nil")
        return
    }
    expectEqual(back, original, "round trip")
}

private func checkStitch() {
    let page = PageFixture(contentRows: 200, footerRows: 0, width: 72)
    var assembler = ScrollAssembler(firstViewport: page.viewport(offset: 0, height: 120))
    expectEqual(assembler.add(next: page.viewport(offset: 40, height: 120)), .appended(shift: 40))
    expectEqual(assembler.add(next: page.viewport(offset: 80, height: 120)), .appended(shift: 40))
    guard let rendered = assembler.rendered() else {
        expect(false, "missing rendered page")
        return
    }
    expectEqual(rendered.height, 200)
    expectEqual(contentID(rendered, x: 3, y: 0), 1)
    expectEqual(contentID(rendered, x: 3, y: 80), 81)
    expectEqual(contentID(rendered, x: 3, y: 199), 200)
}

private func checkFastScroll() {
    let page = PageFixture(contentRows: 500, footerRows: 0, width: 72)
    var assembler = ScrollAssembler(firstViewport: page.viewport(offset: 0, height: 160))
    expectEqual(assembler.add(next: page.viewport(offset: 60, height: 160)), .appended(shift: 60), "fast but overlapping frame")
    expectEqual(assembler.add(next: page.viewport(offset: 172, height: 160)), .unreliable, "jump past one frame is not guessed")
    expectEqual(assembler.pixelHeight, 220)
}

private func checkOddShift() {
    let page = PageFixture(contentRows: 400, footerRows: 0, width: 400)
    var assembler = ScrollAssembler(firstViewport: page.viewport(offset: 0, height: 180))
    expectEqual(assembler.add(next: page.viewport(offset: 17, height: 180)), .appended(shift: 17), "odd shift")
    expectEqual(assembler.pixelHeight, 197)
}

private func checkSteadyScroll() {
    let page = PageFixture(contentRows: 900, footerRows: 0, width: 64)
    var assembler = ScrollAssembler(firstViewport: page.viewport(offset: 0, height: 160))
    for step in 1...12 {
        expectEqual(
            assembler.add(next: page.viewport(offset: step * 50, height: 160)),
            .appended(shift: 50),
            "steady \(step)"
        )
    }
    expectEqual(assembler.pixelHeight, 160 + 12 * 50)
}

private func checkLargeFrame() {
    let page = PageFixture(contentRows: 1200, footerRows: 0, width: 900)
    let first = page.viewport(offset: 0, height: 700)
    let next = page.viewport(offset: 80, height: 700)
    let start = Date()
    let estimate = Stitcher.estimateUpwardShift(previous: first, next: next)
    let elapsed = Date().timeIntervalSince(start)
    expect(estimate.accepted && estimate.upwardShift == 80, "large stitch elapsed=\(elapsed) \(estimate)")
    expect(elapsed < 0.2, "large stitch too slow: \(elapsed)s")
}

private func checkNoMovement() {
    let page = PageFixture(contentRows: 200, footerRows: 0, width: 72)
    let first = page.viewport(offset: 0, height: 120)
    var assembler = ScrollAssembler(firstViewport: first)
    expectEqual(assembler.add(next: first), .noMovement)
    expectEqual(assembler.pixelHeight, 120)
}

private func checkFlatAndRepeating() {
    let flat = solid(width: 60, height: 80, b: 240, g: 240, r: 240)
    let flatEstimate = Stitcher.estimateUpwardShift(previous: flat, next: flat)
    expect(flatEstimate.accepted, "flat image should be accepted as no movement")
    expectEqual(flatEstimate.upwardShift, 0)

    let previous = repeating(width: 60, height: 90, period: 8, phase: 0)
    let next = repeating(width: 60, height: 90, period: 8, phase: 4)
    let repeatingEstimate = Stitcher.estimateUpwardShift(previous: previous, next: next)
    expect(!repeatingEstimate.accepted, "periodic pattern should be rejected, got \(repeatingEstimate)")
}

private func checkUnrelated() {
    let page = PageFixture(contentRows: 180, footerRows: 0, width: 64)
    var assembler = ScrollAssembler(firstViewport: page.viewport(offset: 0, height: 100))
    let noise = makeBuffer(width: 64, height: 100) { x, y in
        (b: UInt8((x * 13 + y * 7) & 255), g: UInt8((y * 3) & 255), r: UInt8((x * 9) & 255), a: 255)
    }
    expectEqual(assembler.add(next: noise), .unreliable)
    expectEqual(assembler.pixelHeight, 100)
}

private func checkFooter() {
    let page = PageFixture(contentRows: 220, footerRows: 16, width: 80)
    var assembler = ScrollAssembler(firstViewport: page.viewport(offset: 0, height: 120))
    expectEqual(assembler.add(next: page.viewport(offset: 40, height: 120)), .appended(shift: 40), "first footer join")
    expectEqual(assembler.add(next: page.viewport(offset: 80, height: 120)), .appended(shift: 40), "second footer join")
    guard let rendered = assembler.rendered() else {
        expect(false, "missing footer render")
        return
    }
    expectEqual(contentID(rendered, x: 4, y: 0), 1)
    expectEqual(contentID(rendered, x: 4, y: 103), 104)
    expectEqual(contentID(rendered, x: 4, y: 143), 144)
    expect(isFooter(rendered, x: 4, y: rendered.height - 1), "bottom row should be footer")
    expect(isFooter(rendered, x: 6, y: rendered.height - 16), "footer should be 16 rows")
    expect(!isFooter(rendered, x: 4, y: rendered.height - 17), "content above footer")
    expectEqual(footerCount(rendered), 16)
}

private func checkBlankBottom() {
    let previous = makeBuffer(width: 70, height: 100) { x, y in
        if y >= 80 { return (b: 255, g: 255, r: 255, a: 255) }
        return contentPixel(id: y + 1, x: x)
    }
    let next = makeBuffer(width: 70, height: 100) { x, y in
        if y >= 80 { return (b: 255, g: 255, r: 255, a: 255) }
        return contentPixel(id: y + 1 + 30, x: x)
    }
    let estimate = Stitcher.estimateUpwardShift(previous: previous, next: next)
    expect(estimate.accepted, "blank bottom estimate \(estimate)")
    expectEqual(estimate.upwardShift, 30)
    expectEqual(estimate.stickyFooterRows, 0)
}

private func checkHeader() {
    let previous = headed(width: 76, height: 120, header: 20, contentOffset: 0)
    let next = headed(width: 76, height: 120, header: 20, contentOffset: 30)
    let estimate = Stitcher.estimateUpwardShift(previous: previous, next: next)
    expect(estimate.accepted, "header estimate \(estimate)")
    expectEqual(estimate.upwardShift, 30)
}

checkCoordinates()
checkRoundTrip()
checkStitch()
checkFastScroll()
checkOddShift()
checkSteadyScroll()
checkLargeFrame()
checkNoMovement()
checkFlatAndRepeating()
checkUnrelated()
checkFooter()
checkBlankBottom()
checkHeader()

if failures == 0 {
    print("PinTool checks passed")
} else {
    print("\(failures) check(s) failed")
    exit(1)
}

private struct PageFixture {
    var contentRows: Int
    var footerRows: Int
    var width: Int

    func viewport(offset: Int, height: Int) -> PixelBuffer {
        let contentVisible = height - footerRows
        return makeBuffer(width: width, height: height) { x, y in
            if y >= contentVisible { return footerPixel(x: x) }
            let id = offset + y + 1
            if id > contentRows { return (b: 255, g: 255, r: 255, a: 255) }
            return contentPixel(id: id, x: x)
        }
    }
}

private func contentPixel(id: Int, x: Int) -> (b: UInt8, g: UInt8, r: UInt8, a: UInt8) {
    (b: UInt8((x * 13 + id) & 255), g: UInt8((id >> 8) & 255), r: UInt8(id & 255), a: 255)
}

private func footerPixel(x: Int) -> (b: UInt8, g: UInt8, r: UInt8, a: UInt8) {
    (b: UInt8((x * 17 + 9) & 255), g: 30, r: 20, a: 255)
}

private func contentID(_ buffer: PixelBuffer, x: Int, y: Int) -> Int {
    let pixel = buffer.bgra(x: x, y: y)
    return Int(pixel.r) | (Int(pixel.g) << 8)
}

private func isFooter(_ buffer: PixelBuffer, x: Int, y: Int) -> Bool {
    let pixel = buffer.bgra(x: x, y: y)
    return pixel.r == 20 && pixel.g == 30
}

private func footerCount(_ buffer: PixelBuffer) -> Int {
    var count = 0
    var y = buffer.height - 1
    while y >= 0, isFooter(buffer, x: 0, y: y) {
        count += 1
        y -= 1
    }
    return count
}

private func solid(width: Int, height: Int, b: UInt8, g: UInt8, r: UInt8) -> PixelBuffer {
    makeBuffer(width: width, height: height) { _, _ in (b: b, g: g, r: r, a: 255) }
}

private func repeating(width: Int, height: Int, period: Int, phase: Int) -> PixelBuffer {
    makeBuffer(width: width, height: height) { x, y in
        let band = (y + phase) % period
        return (b: UInt8(band * 20), g: UInt8(40 + x), r: UInt8(band * 10 + 5), a: 255)
    }
}

private func headed(width: Int, height: Int, header: Int, contentOffset: Int) -> PixelBuffer {
    makeBuffer(width: width, height: height) { x, y in
        if y < header {
            return (b: UInt8((x * 11 + y * 3) & 255), g: 8, r: 8, a: 255)
        }
        return contentPixel(id: contentOffset + (y - header) + 1, x: x)
    }
}

private func makeBuffer(
    width: Int,
    height: Int,
    pixel: (Int, Int) -> (b: UInt8, g: UInt8, r: UInt8, a: UInt8)
) -> PixelBuffer {
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let sample = pixel(x, y)
            let i = (y * width + x) * 4
            bytes[i] = sample.b
            bytes[i + 1] = sample.g
            bytes[i + 2] = sample.r
            bytes[i + 3] = sample.a
        }
    }
    return PixelBuffer(width: width, height: height, bytes: bytes)!
}
