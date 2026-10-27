import Foundation

/// Top row first, pixels packed as BGRA.
public struct PixelBuffer: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let bytes: [UInt8]

    public init?(width: Int, height: Int, bytes: [UInt8]) {
        guard width > 0, height > 0, bytes.count == width * height * 4 else { return nil }
        self.width = width
        self.height = height
        self.bytes = bytes
    }

    public func bgra(x: Int, y: Int) -> (b: UInt8, g: UInt8, r: UInt8, a: UInt8) {
        let i = (y * width + x) * 4
        return (bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3])
    }

    public func appending(rows: Range<Int>, from source: PixelBuffer) -> PixelBuffer? {
        guard source.width == width, rows.lowerBound >= 0, rows.upperBound <= source.height, !rows.isEmpty else {
            return nil
        }
        var copy = bytes
        let start = rows.lowerBound * width * 4
        let end = rows.upperBound * width * 4
        copy.append(contentsOf: source.bytes[start..<end])
        return PixelBuffer(width: width, height: height + rows.count, bytes: copy)
    }

    func sampledMeanAbsoluteError(against other: PixelBuffer) -> Double {
        guard width == other.width, height == other.height, height > 0 else { return .greatestFiniteMagnitude }
        var sum = 0
        var count = 0
        var y = 0
        while y < height {
            var x = 0
            while x < width {
                sum += sampleDelta(x: x, y: y, other: other, otherY: y)
                count += 3
                x += 4
            }
            y += 2
        }
        guard count > 0 else { return .greatestFiniteMagnitude }
        return Double(sum) / Double(count)
    }

    func bandStddev(y: Int, band: Int) -> Double {
        meanRowStddev(startY: y, rows: band)
    }

    func meanRowStddev(startY: Int, rows: Int) -> Double {
        guard rows > 0, startY >= 0, startY + rows <= height else { return 0 }
        var total = 0.0
        for y in startY..<(startY + rows) {
            total += rowStddev(y: y)
        }
        return total / Double(rows)
    }

    func rowMeanAbsoluteError(y: Int, against other: PixelBuffer, otherY: Int) -> Double {
        guard y >= 0, y < height, otherY >= 0, otherY < other.height, width == other.width else {
            return .greatestFiniteMagnitude
        }
        var sum = 0
        var count = 0
        var x = 0
        while x < width {
            sum += sampleDelta(x: x, y: y, other: other, otherY: otherY)
            count += 3
            x += 2
        }
        guard count > 0 else { return .greatestFiniteMagnitude }
        return Double(sum) / Double(count)
    }

    func bandMeanAbsoluteError(y: Int, band: Int, against other: PixelBuffer, otherY: Int, sampleStep: Int = 0) -> Double {
        guard y >= 0, otherY >= 0, y + band <= height, otherY + band <= other.height, width == other.width, width > 0 else {
            return .greatestFiniteMagnitude
        }
        let step = sampleStep > 0 ? sampleStep : max(2, width / 36)
        return bytes.withUnsafeBytes { raw in
            other.bytes.withUnsafeBytes { otherRaw in
                guard let lhs = raw.bindMemory(to: UInt8.self).baseAddress,
                      let rhs = otherRaw.bindMemory(to: UInt8.self).baseAddress else {
                    return Double.greatestFiniteMagnitude
                }
                var sum = 0
                var count = 0
                let rowBytes = width * 4
                for row in 0..<band {
                    let leftRow = lhs.advanced(by: (y + row) * rowBytes)
                    let rightRow = rhs.advanced(by: (otherY + row) * rowBytes)
                    var x = 0
                    while x < width {
                        let i = x * 4
                        sum += abs(Int(leftRow[i]) - Int(rightRow[i]))
                        sum += abs(Int(leftRow[i + 1]) - Int(rightRow[i + 1]))
                        sum += abs(Int(leftRow[i + 2]) - Int(rightRow[i + 2]))
                        count += 3
                        if count > 240 {
                            let running = Double(sum) / Double(count)
                            if running > 48 { return running }
                        }
                        x += step
                    }
                }
                guard count > 0 else { return Double.greatestFiniteMagnitude }
                return Double(sum) / Double(count)
            }
        }
    }

    private func sampleDelta(x: Int, y: Int, other: PixelBuffer, otherY: Int) -> Int {
        let i = (y * width + x) * 4
        let j = (otherY * other.width + x) * 4
        return abs(Int(bytes[i]) - Int(other.bytes[j]))
            + abs(Int(bytes[i + 1]) - Int(other.bytes[j + 1]))
            + abs(Int(bytes[i + 2]) - Int(other.bytes[j + 2]))
    }

    private func rowStddev(y: Int) -> Double {
        var sum = 0.0
        var sumSq = 0.0
        var n = 0.0
        var x = 0
        while x < width {
            let i = (y * width + x) * 4
            let gray = (Double(bytes[i]) + Double(bytes[i + 1]) + Double(bytes[i + 2])) / 3
            sum += gray
            sumSq += gray * gray
            n += 1
            x += 2
        }
        guard n > 0 else { return 0 }
        let mean = sum / n
        return (max(0, sumSq / n - mean * mean)).squareRoot()
    }
}
