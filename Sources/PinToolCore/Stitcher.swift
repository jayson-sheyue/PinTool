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

        // One frame should only move a modest slice. A taller template keeps repeating
        // rows from locking onto the wrong copy, which is what produced the ghosting.
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

    /// Largest share of the viewport a single frame is allowed to move.
    private static let maxShiftFraction = 0.42

    private static func matchScroll(previous: PixelBuffer, next: PixelBuffer) -> (shift: Int, error: Double)? {
        let factor = max(1, previous.width / 160)
        let previousGray = gray(from: previous, factor: factor)
        let nextGray = gray(from: next, factor: factor)
        guard previousGray.width == nextGray.width, previousGray.height == nextGray.height, previousGray.height >= 16 else {
            return nil
        }
        let templateH = max(8, previousGray.height / 5)
        let templateY = min(previousGray.height - templateH - 1, max(8, Int((Double(previousGray.height) * maxShiftFraction).rounded())))
        guard templateY + templateH < previousGray.height else { return nil }
        let pixels = templateH * previousGray.width
        guard pixels > 0 else { return nil }

        var bestShift = 0
        var bestSum = Int.max
        var secondSum = Int.max
        for shift in 0...templateY {
            let sum = sad(previous: previousGray, next: nextGray, y: templateY, rows: templateH, shift: shift)
            if sum < bestSum {
                if abs(shift - bestShift) > 6 {
                    secondSum = bestSum
                }
                bestSum = sum
                bestShift = shift
            } else if abs(shift - bestShift) > 6, sum < secondSum {
                secondSum = sum
            }
        }

        let mean = Double(bestSum) / Double(pixels)
        guard mean < 30 else { return nil }
        let secondMean = secondSum == Int.max ? Double.greatestFiniteMagnitude : Double(secondSum) / Double(pixels)
        let unique = secondMean >= mean + 6 || secondMean > mean * 1.45 + 2
        guard unique else { return nil }

        let rough = bestShift * factor
        let band = min(24, max(12, previous.height / 6))
        let span = max(12, factor * 2)
        let low = max(0, rough - span)
        let high = min(Int((Double(previous.height) * maxShiftFraction).rounded()), rough + span)
        guard low <= high else { return nil }
        var scored: [(shift: Int, error: Double)] = []
        for shift in low...high {
            let y = min(previous.height - band - 1, max(shift, Int((Double(previous.height) * 0.5).rounded())))
            guard y >= shift else { continue }
            let error = previous.bandMeanAbsoluteError(
                y: y,
                band: band,
                against: next,
                otherY: y - shift,
                sampleStep: 2
            )
            scored.append((shift, error))
        }
        guard let bestError = scored.map(\.error).min(), bestError < 36 else { return nil }
        let plateau = scored.filter { $0.error <= bestError + 1.25 }.map(\.shift).sorted()
        guard let refined = plateau.isEmpty ? nil : plateau[plateau.count / 2] else { return nil }
        return (refined, bestError)
    }

    private struct GrayImage {
        var width: Int
        var height: Int
        var samples: [Int]
    }

    private static func gray(from buffer: PixelBuffer, factor: Int) -> GrayImage {
        let width = max(1, buffer.width / factor)
        let height = max(1, buffer.height / factor)
        var samples = [Int](repeating: 0, count: width * height)
        buffer.bytes.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            let rowBytes = buffer.width * 4
            for y in 0..<height {
                let row = base.advanced(by: y * factor * rowBytes)
                for x in 0..<width {
                    let pixel = row.advanced(by: x * factor * 4)
                    samples[y * width + x] = (Int(pixel[0]) + Int(pixel[1]) + Int(pixel[2])) / 3
                }
            }
        }
        return GrayImage(width: width, height: height, samples: samples)
    }

    private static func sad(previous: GrayImage, next: GrayImage, y: Int, rows: Int, shift: Int) -> Int {
        let otherY = y - shift
        guard otherY >= 0, y + rows <= previous.height, otherY + rows <= next.height else { return Int.max }
        var sum = 0
        for row in 0..<rows {
            let left = (y + row) * previous.width
            let right = (otherY + row) * next.width
            for x in 0..<previous.width {
                sum += abs(previous.samples[left + x] - next.samples[right + x])
            }
        }
        return sum
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
