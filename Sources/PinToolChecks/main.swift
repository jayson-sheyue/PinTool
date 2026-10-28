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
    let page = PageFixture(contentRows: 800, footerRows: 0, width: 72)
    var assembler = ScrollAssembler(firstViewport: page.viewport(offset: 0, height: 160))
    expectEqual(assembler.add(next: page.viewport(offset: 60, height: 160)), .appended(shift: 60), "fast but overlapping frame")
    expectEqual(assembler.add(next: page.viewport(offset: 180, height: 160)), .appended(shift: 120), "faster jump still aligned")
    expectEqual(assembler.pixelHeight, 340)
    guard let rendered = assembler.rendered() else {
        expect(false, "missing fast render")
        return
    }
    expectEqual(contentID(rendered, x: 3, y: 0), 1)
    expectEqual(contentID(rendered, x: 3, y: 159), 160)
    expectEqual(contentID(rendered, x: 3, y: 160), 161)
    expectEqual(contentID(rendered, x: 3, y: 219), 220)
    expectEqual(contentID(rendered, x: 3, y: 220), 221)
    expectEqual(contentID(rendered, x: 3, y: 339), 340)
    expectEqual(assembler.add(next: page.viewport(offset: 360, height: 160)), .unreliable, "jump past the overlap is not guessed")
    expectEqual(assembler.pixelHeight, 340)
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
    // Debug builds on a shared CI runner vary by tens of milliseconds.
    // This only catches a real slowdown, not a 30 fps release budget.
    expect(elapsed < 0.5, "large stitch too slow: \(elapsed)s")
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

    let far = repeating(width: 60, height: 90, period: 8, phase: 36)
    let farEstimate = Stitcher.estimateUpwardShift(previous: previous, next: far)
    expect(!farEstimate.accepted, "a long periodic jump should still be rejected, got \(farEstimate)")
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
checkRepeatedOptions()
checkFastOptions()
checkSparseShift()
checkListRows()

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
    // The high byte has to show up in the blue channel too. Otherwise a 256-row
    // jump keeps the same red and blue and looks like the true alignment.
    let high = id >> 8
    return (
        b: UInt8((x * 13 + id + high * 40) & 255),
        g: UInt8(high & 255),
        r: UInt8(id & 255),
        a: 255
    )
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

private func checkRepeatedOptions() {
    let page = OptionPage(lineHeight: 28, lines: 40, width: 360)
    let height = 196
    var assembler = ScrollAssembler(firstViewport: page.viewport(offsetLines: 0, height: height))
    expectEqual(assembler.add(next: page.viewport(offsetLines: 1, height: height)), .appended(shift: 28), "one similar option row")
    expectEqual(assembler.add(next: page.viewport(offsetLines: 3, height: height)), .appended(shift: 56), "two similar option rows")
    guard let rendered = assembler.rendered() else {
        expect(false, "missing option render")
        return
    }
    expectEqual(rendered.height, height + 28 + 56)
    var seen: [Int: Int] = [:]
    for line in 0..<(rendered.height / 28) {
        let id = optionID(rendered, line: line, lineHeight: 28)
        seen[id, default: 0] += 1
    }
    let duplicated = seen.filter { $0.value > 1 }.map(\.key).sorted()
    expect(duplicated.isEmpty, "option lines overlapped: \(duplicated)")
    expectEqual(seen[0], 1, "first option kept once")
    expectEqual(seen[3 + (height / 28) - 1], 1, "last scrolled option kept once")
}

private func checkFastOptions() {
    let page = OptionPage(lineHeight: 28, lines: 40, width: 360)
    let height = 196
    var assembler = ScrollAssembler(firstViewport: page.viewport(offsetLines: 0, height: height))
    expectEqual(assembler.add(next: page.viewport(offsetLines: 5, height: height)), .appended(shift: 140), "five similar option rows")
    guard let rendered = assembler.rendered() else {
        expect(false, "missing fast option render")
        return
    }
    expectEqual(rendered.height, height + 140)
    var seen: [Int: Int] = [:]
    for line in 0..<(rendered.height / 28) {
        let id = optionID(rendered, line: line, lineHeight: 28)
        seen[id, default: 0] += 1
    }
    let duplicated = seen.filter { $0.value > 1 }.map(\.key).sorted()
    expect(duplicated.isEmpty, "fast option lines overlapped: \(duplicated)")
    expectEqual(seen[0], 1, "first option kept once")
    expectEqual(seen[5 + (height / 28) - 1], 1, "last fast option kept once")
    expectEqual(assembler.add(next: page.viewport(offsetLines: 11, height: height)), .unreliable, "option jump past the overlap is not guessed")
    expectEqual(assembler.pixelHeight, height + 140)
}

private func checkListRows() {
    let page = ListPage()
    let height = page.rowHeight * 4
    var assembler = ScrollAssembler(firstViewport: page.viewport(firstRow: 0, height: height))
    for step in 1...6 {
        expectEqual(
            assembler.add(next: page.viewport(firstRow: step, height: height)),
            .appended(shift: page.rowHeight),
            "list row \(step)"
        )
    }
    guard let rendered = assembler.rendered() else {
        expect(false, "missing list render")
        return
    }
    expectEqual(rendered.height, page.rowHeight * 10)
    var seen: [Int: Int] = [:]
    for row in 0..<10 {
        let id = listRowID(rendered, row: row, rowHeight: page.rowHeight)
        seen[id, default: 0] += 1
    }
    let duplicated = seen.filter { $0.value > 1 }.map(\.key).sorted()
    expect(duplicated.isEmpty, "list rows overlapped: \(duplicated)")
    expectEqual(seen[0], 1, "first list row kept once")
    expectEqual(seen[9], 1, "last list row kept once")

    var fast = ScrollAssembler(firstViewport: page.viewport(firstRow: 0, height: height))
    expectEqual(
        fast.add(next: page.viewport(firstRow: 3, height: height)),
        .appended(shift: page.rowHeight * 3),
        "list jump of three similar rows"
    )
}

private struct ListPage {
    var rowHeight = 52
    var count = 20
    var width = 340

    func viewport(firstRow: Int, height: Int) -> PixelBuffer {
        makeBuffer(width: width, height: height) { x, y in
            let source = y + firstRow * rowHeight
            let row = source / rowHeight
            let local = source % rowHeight
            if row >= count { return (b: 255, g: 255, r: 255, a: 255) }
            if local == 0 { return (b: 210, g: 210, r: 210, a: 255) }
            let text = local >= 16 && local < 32
            if !text { return (b: 255, g: 255, r: 255, a: 255) }
            if x >= width - 24 {
                let on = local >= 20 && local <= 27 && x > width - 16 && x < width - 6
                return on ? (b: 30, g: 30, r: 30, a: 255) : (b: 255, g: 255, r: 255, a: 255)
            }
            if x >= 18 && x < 26 {
                let on = ((row >> (x - 18)) & 1) == 1
                return on ? (b: 20, g: 20, r: 20, a: 255) : (b: 250, g: 250, r: 250, a: 255)
            }
            if x < 120 {
                let on = (x + local) % 4 == 0
                return on ? (b: 25, g: 25, r: 25, a: 255) : (b: 255, g: 255, r: 255, a: 255)
            }
            let on = (x * 3 + row * 19 + local) % 5 == 0
            return on ? (b: 20, g: 20, r: 20, a: 255) : (b: 255, g: 255, r: 255, a: 255)
        }
    }
}

private func listRowID(_ buffer: PixelBuffer, row: Int, rowHeight: Int) -> Int {
    var id = 0
    let y = row * rowHeight + 24
    for bit in 0..<8 {
        let pixel = buffer.bgra(x: 18 + bit, y: y)
        if pixel.r < 128 { id |= 1 << bit }
    }
    return id
}

private func checkSparseShift() {
    func frame(offset: Int) -> PixelBuffer {
        makeBuffer(width: 180, height: 160) { x, y in
            let source = y + offset
            if source % 40 < 28 { return (b: 255, g: 255, r: 255, a: 255) }
            return contentPixel(id: source + 1, x: x)
        }
    }
    let estimate = Stitcher.estimateUpwardShift(previous: frame(offset: 0), next: frame(offset: 23))
    expect(estimate.accepted && estimate.upwardShift == 23, "sparse text \(estimate)")
}

private struct OptionPage {
    var lineHeight: Int
    var lines: Int
    var width: Int

    func viewport(offsetLines: Int, height: Int) -> PixelBuffer {
        makeBuffer(width: width, height: height) { x, y in
            let absolute = offsetLines * lineHeight + y
            let line = absolute / lineHeight
            let row = absolute % lineHeight
            if line >= lines { return (b: 255, g: 255, r: 255, a: 255) }
            if row < 8 || row >= 20 { return (b: 255, g: 255, r: 255, a: 255) }
            if x < 18 { return (b: 40, g: 40, r: 40, a: 255) }
            if x >= width - 6 {
                return (b: UInt8(line & 255), g: UInt8((line >> 8) & 255), r: 9, a: 255)
            }
            let ink = (x * 3 + row + line * 11) % 7 == 0
            return ink ? (b: 70, g: 70, r: 70, a: 255) : (b: 248, g: 248, r: 248, a: 255)
        }
    }
}

private func optionID(_ buffer: PixelBuffer, line: Int, lineHeight: Int) -> Int {
    let pixel = buffer.bgra(x: buffer.width - 3, y: line * lineHeight + 10)
    return Int(pixel.b) | (Int(pixel.g) << 8)
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
