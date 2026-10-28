import Foundation

public struct ShiftEstimate: Equatable, Sendable {
    public var upwardShift: Int
    public var stickyFooterRows: Int
    public var accepted: Bool
    public var meanAbsoluteError: Double
}

public enum Stitcher {
    public static func estimateUpwardShift(previous: PixelBuffer, next: PixelBuffer) -> ShiftEstimate {
        let rejected = ShiftEstimate(
            upwardShift: 0,
            stickyFooterRows: 0,
            accepted: false,
            meanAbsoluteError: .greatestFiniteMagnitude
        )
        guard previous.width == next.width, previous.height == next.height else { return rejected }
        let height = previous.height
        guard previous.width >= 8, height >= 48 else { return rejected }

        if previous.sampledMeanAbsoluteError(against: next) < 4 {
            return ShiftEstimate(upwardShift: 0, stickyFooterRows: 0, accepted: true, meanAbsoluteError: 0)
        }

        // A frame may move most of the viewport. It is accepted only when the
        // remaining text rows agree on one distance, so a line is not pasted twice.
        guard let match = matchScroll(previous: previous, next: next) else { return rejected }
        if match.shift < 2 {
            return ShiftEstimate(upwardShift: 0, stickyFooterRows: 0, accepted: true, meanAbsoluteError: match.error)
        }
        return ShiftEstimate(
            upwardShift: match.shift,
            stickyFooterRows: stickyFooterRows(previous: previous, next: next),
            accepted: true,
            meanAbsoluteError: match.error
        )
    }

    /// Largest share of the viewport one frame may move. The rest has to match.
    private static let maxShiftFraction = 0.85

    private static func matchScroll(previous: PixelBuffer, next: PixelBuffer) -> (shift: Int, error: Double)? {
        let footer = stickyFooterRows(previous: previous, next: next)
        let maxShift = min(previous.height - 24, Int((Double(previous.height) * maxShiftFraction).rounded()))
        guard maxShift >= 2 else { return nil }
        guard let scores = alignmentScores(previous: previous, next: next, maxShift: maxShift, footer: footer) else {
            return nil
        }

        var bestShift = 0
        var best = Double.greatestFiniteMagnitude
        for shift in 0...maxShift where scores[shift] < best {
            best = scores[shift]
            bestShift = shift
        }
        guard best < 18 else { return nil }

        // A blank overlap matches every distance. That plateau must not be stitched.
        var plateauLow = bestShift
        while plateauLow > 0, scores[plateauLow - 1] <= best + 1.25 {
            plateauLow -= 1
        }
        var plateauHigh = bestShift
        while plateauHigh < maxShift, scores[plateauHigh + 1] <= best + 1.25 {
            plateauHigh += 1
        }
        if plateauHigh - plateauLow > 6 { return nil }

        // List rows share arrows and padding, so another row can score almost as
        // well. A rival this close is not stitched; a clearly worse one is ignored.
        let close = best + 2.5
        var inside = false
        var groups = 0
        for shift in 0...maxShift {
            let now = scores[shift] <= close
            if now, !inside { groups += 1 }
            inside = now
        }
        guard groups == 1 else { return nil }
        return (bestShift, best)
    }

    /// Error of every shift, measured on columns that actually change down the page.
    /// Padding and a repeated arrow then cannot outvote the words.
    private static func alignmentScores(
        previous: PixelBuffer,
        next: PixelBuffer,
        maxShift: Int,
        footer: Int
    ) -> [Double]? {
        let limit = previous.height - footer
        guard limit > 24 else { return nil }
        let columns = distinctiveColumns(in: previous, yLimit: limit)
        guard columns.count >= 8 else { return nil }
        let content = contentRows(in: previous, above: limit)
        guard content.count >= 8 else { return nil }
        let previousSamples = samples(previous, columns: columns)
        let nextSamples = samples(next, columns: columns)
        let columnCount = columns.count

        var scores = [Double](repeating: .greatestFiniteMagnitude, count: maxShift + 1)
        previousSamples.withUnsafeBufferPointer { previousBuffer in
            nextSamples.withUnsafeBufferPointer { nextBuffer in
                guard let previousBase = previousBuffer.baseAddress,
                      let nextBase = nextBuffer.baseAddress else { return }
                var index = 0
                for shift in 0...maxShift {
                    while index < content.count, content[index] < shift {
                        index += 1
                    }
                    let available = content.count - index
                    guard available >= 8 else { continue }
                    let step = max(1, available / 48)
                    var sum = 0
                    var rows = 0
                    var cursor = index
                    while cursor < content.count {
                        let y = content[cursor]
                        let otherY = y - shift
                        let left = previousBase.advanced(by: y * columnCount)
                        let right = nextBase.advanced(by: otherY * columnCount)
                        for column in 0..<columnCount {
                            sum += abs(Int(left[column]) - Int(right[column]))
                        }
                        rows += 1
                        cursor += step
                    }
                    if rows >= 8 {
                        scores[shift] = Double(sum) / Double(rows * columnCount)
                    }
                }
            }
        }
        return scores
    }

    /// Columns whose pixels change down the page. Flat padding matches at every scroll.
    private static func distinctiveColumns(in buffer: PixelBuffer, yLimit: Int) -> [Int] {
        var chosen: [Int] = []
        var x = 0
        while x < buffer.width {
            if columnSpread(buffer, x: x, yLimit: yLimit) >= 18 {
                chosen.append(x)
            }
            x += 2
        }
        if chosen.count >= 8 {
            guard chosen.count > 72 else { return chosen }
            let step = Double(chosen.count) / 72.0
            return (0..<72).map { chosen[min(chosen.count - 1, Int(Double($0) * step))] }
        }
        var fallback: [Int] = []
        let step = max(2, buffer.width / 12)
        var fallbackX = step / 2
        while fallbackX < buffer.width {
            fallback.append(fallbackX)
            fallbackX += step
        }
        return fallback
    }

    private static func columnSpread(_ buffer: PixelBuffer, x: Int, yLimit: Int) -> Int {
        var low = 255
        var high = 0
        var y = 0
        while y < yLimit {
            let gray = grayValue(buffer, x: x, y: y)
            if gray < low { low = gray }
            if gray > high { high = gray }
            y += 2
        }
        return high - low
    }

    private static func samples(_ buffer: PixelBuffer, columns: [Int]) -> [UInt8] {
        var values = [UInt8](repeating: 0, count: buffer.height * columns.count)
        for y in 0..<buffer.height {
            let row = y * columns.count
            for (index, x) in columns.enumerated() {
                values[row + index] = UInt8(grayValue(buffer, x: x, y: y))
            }
        }
        return values
    }

    private static func grayValue(_ buffer: PixelBuffer, x: Int, y: Int) -> Int {
        let pixel = buffer.bgra(x: x, y: y)
        return (Int(pixel.b) + Int(pixel.g) + Int(pixel.r)) / 3
    }

    /// Rows that contain edges. Blank gaps match every distance and used to pull the join off the text.
    private static func contentRows(in buffer: PixelBuffer, above limit: Int) -> [Int] {
        var rows: [Int] = []
        var y = 0
        while y < limit {
            if buffer.meanRowStddev(startY: y, rows: 1) >= 8 {
                rows.append(y)
            }
            y += 1
        }
        return rows
    }

    /// Rows at the bottom that stayed put and are visually busy enough to be a bar, not blank page.
    private static func stickyFooterRows(previous: PixelBuffer, next: PixelBuffer) -> Int {
        let height = previous.height
        let maxRun = height / 3
        var run = 0
        while run < maxRun {
            let y = height - 1 - run
            if previous.rowMeanAbsoluteError(y: y, against: next, otherY: y) > 12 {
                break
            }
            run += 1
        }
        guard run >= 8 else { return 0 }
        guard previous.meanRowStddev(startY: height - run, rows: run) >= 8 else { return 0 }
        return run
    }
}
