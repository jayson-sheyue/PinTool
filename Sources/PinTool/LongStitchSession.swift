import CoreMedia
import Foundation
import PinToolCore
import ScreenCaptureKit

/// Keeps a live capture of the baseline rectangle and stitches each new frame.
final class LongStitchSession: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    var onPreview: ((CGImage) -> Void)?
    var onCapped: (() -> Void)?
    var onLost: (() -> Void)?

    private let sampleQueue = DispatchQueue(label: "local.pintool.frames", qos: .userInteractive)
    private let workQueue = DispatchQueue(label: "local.pintool.stitch", qos: .userInteractive)
    private var stream: SCStream?
    private var target: CaptureTarget?
    private var assembler: ScrollAssembler?
    private var lastPreview = 0.0
    private var stopped = false
    private var capped = false
    private var restarts = 0
    private var previewBusy = false
    private var previewWaiting = false

    func start(_ target: CaptureTarget) async throws {
        self.target = target
        try await openStream(target)
    }

    /// Stops new frames and returns the stitched image, including frames not yet shown.
    func end() async -> CGImage? {
        let workQueue = workQueue
        let image: CGImage? = await withCheckedContinuation { continuation in
            workQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: nil)
                    return
                }
                self.stopped = true
                continuation.resume(returning: self.currentImage())
            }
        }
        let active = stream
        stream = nil
        if let active {
            try? await active.stopCapture()
        }
        return image
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, !stopped, stream === self.stream else { return }
        if let status = Self.status(of: sampleBuffer) {
            switch status {
            case .blank, .suspended, .stopped:
                return
            default:
                break
            }
        }
        guard let pixel = CMSampleBufferGetImageBuffer(sampleBuffer),
              let frame = ImageConvert.buffer(from: pixel) else { return }
        workQueue.async { [weak self] in
            self?.ingest(frame)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        workQueue.async { [weak self] in
            guard let self, !self.stopped, stream === self.stream else { return }
            self.restarts += 1
            guard self.restarts <= 2, let target = self.target else {
                DispatchQueue.main.async { [weak self] in
                    self?.onLost?()
                }
                return
            }
            Task { @MainActor [weak self] in
                try? await self?.openStream(target)
            }
        }
    }

    private func openStream(_ target: CaptureTarget) async throws {
        guard !stopped else { return }
        let config = target.configuration
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 8
        let stream = SCStream(filter: target.filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        self.stream = stream
        try await stream.startCapture()
    }

    private func ingest(_ frame: PixelBuffer) {
        guard !stopped, !capped else { return }
        if assembler == nil {
            assembler = ScrollAssembler(firstViewport: frame)
            publish(force: true)
            return
        }
        guard var assembler else { return }
        let step = assembler.add(next: frame)
        switch step {
        case .appended:
            self.assembler = assembler
            publish(force: false)
            if assembler.pixelHeight >= 20_000 {
                capped = true
                DispatchQueue.main.async { [weak self] in
                    self?.onCapped?()
                }
            }
        case .noMovement, .unreliable:
            // Keep the last frame that joined cleanly. Replacing it would drop the
            // rows scrolled in between, or glue the next frame on at the wrong place.
            self.assembler = assembler
        }
    }

    private func publish(force: Bool) {
        let now = CFAbsoluteTimeGetCurrent()
        if !force, now - lastPreview < 0.033 { return }
        if previewBusy {
            previewWaiting = true
            return
        }
        guard let rendered = assembler?.rendered() else { return }
        lastPreview = now
        previewBusy = true
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let image = ImageConvert.cgImage(from: rendered)
            DispatchQueue.main.async {
                if let image {
                    self?.onPreview?(image)
                }
                self?.workQueue.async { [weak self] in
                    guard let self else { return }
                    self.previewBusy = false
                    if self.previewWaiting, !self.stopped {
                        self.previewWaiting = false
                        self.publish(force: true)
                    }
                }
            }
        }
    }

    private func currentImage() -> CGImage? {
        guard let rendered = assembler?.rendered() else { return nil }
        return ImageConvert.cgImage(from: rendered)
    }

    private static func status(of sampleBuffer: CMSampleBuffer) -> SCFrameStatus? {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int else { return nil }
        return SCFrameStatus(rawValue: raw)
    }
}
