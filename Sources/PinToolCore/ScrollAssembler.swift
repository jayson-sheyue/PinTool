import Foundation

public enum ScrollStep: Equatable, Sendable {
    case appended(shift: Int)
    case noMovement
    case unreliable
}

public struct ScrollAssembler: Sendable {
    private var body: GrowingImage
    private var footer: PixelBuffer?
    private var previous: PixelBuffer

    public init(firstViewport: PixelBuffer) {
        body = GrowingImage(firstViewport)
        previous = firstViewport
    }

    public var pixelHeight: Int {
        body.height + (footer?.height ?? 0)
    }

    public func rendered() -> PixelBuffer? {
        body.rendered(footer: footer)
    }

    public mutating func add(next: PixelBuffer) -> ScrollStep {
        guard next.width == previous.width, next.height == previous.height else { return .unreliable }
        let estimate = Stitcher.estimateUpwardShift(previous: previous, next: next)
        guard estimate.accepted else { return .unreliable }
        guard estimate.upwardShift >= 2 else { return .noMovement }

        var working = body
        var workingFooter = footer
        if workingFooter == nil, estimate.stickyFooterRows >= 8 {
            guard let split = working.removeBottom(rows: estimate.stickyFooterRows) else { return .unreliable }
            workingFooter = split
        }

        let footerHeight = workingFooter?.height ?? 0
        let start = next.height - estimate.upwardShift - footerHeight
        let end = next.height - footerHeight
        guard start >= 0, end <= next.height, start < end else { return .unreliable }
        guard working.append(rows: start..<end, from: next) else { return .unreliable }

        body = working
        footer = workingFooter
        previous = next
        return .appended(shift: estimate.upwardShift)
    }

    /// Drops the gap after a run of frames that could not be aligned, so the next frames
    /// are compared with the live page instead of a stale one.
    public mutating func rebase(to next: PixelBuffer) {
        guard next.width == previous.width, next.height == previous.height else { return }
        previous = next
    }
}

private struct GrowingImage: Sendable {
    private(set) var width: Int
    private(set) var height: Int
    private var bytes: [UInt8]

    init(_ buffer: PixelBuffer) {
        width = buffer.width
        height = buffer.height
        bytes = buffer.bytes
        bytes.reserveCapacity(width * 4 * 24_000)
    }

    mutating func removeBottom(rows: Int) -> PixelBuffer? {
        guard rows > 0, rows < height else { return nil }
        let keep = (height - rows) * width * 4
        let bottom = Array(bytes[keep...])
        bytes.removeSubrange(keep...)
        height -= rows
        return PixelBuffer(width: width, height: rows, bytes: bottom)
    }

    mutating func append(rows: Range<Int>, from source: PixelBuffer) -> Bool {
        guard source.width == width, rows.lowerBound >= 0, rows.upperBound <= source.height, !rows.isEmpty else {
            return false
        }
        let start = rows.lowerBound * width * 4
        let end = rows.upperBound * width * 4
        bytes.append(contentsOf: source.bytes[start..<end])
        height += rows.count
        return true
    }

    func rendered(footer: PixelBuffer?) -> PixelBuffer? {
        var copy = bytes
        var renderedHeight = height
        if let footer {
            guard footer.width == width else { return nil }
            copy.append(contentsOf: footer.bytes)
            renderedHeight += footer.height
        }
        return PixelBuffer(width: width, height: renderedHeight, bytes: copy)
    }
}
