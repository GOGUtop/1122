import AVFoundation
import AVKit
import CoreImage
import UIKit
import WebKit

@MainActor
final class WebPictureInPictureController: NSObject {
    private weak var webView: WKWebView?
    private let displayLayer = AVSampleBufferDisplayLayer()
    private var controller: AVPictureInPictureController?
    private var playbackDelegate: PiPPlaybackDelegate?
    private var timer: Timer?
    private var snapshotInFlight = false
    private var lastGoodImage: UIImage?
    private var frameIndex: Int64 = 0

    func attach(to webView: WKWebView) {
        guard self.webView !== webView else { return }
        self.webView = webView

        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = UIColor.black.cgColor

        let playbackDelegate = PiPPlaybackDelegate()
        playbackDelegate.onStop = { [weak self] in
            Task { @MainActor in self?.stopUpdates() }
        }
        let source = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: displayLayer,
            playbackDelegate: playbackDelegate
        )
        let controller = AVPictureInPictureController(contentSource: source)
        controller.delegate = playbackDelegate
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.requiresLinearPlayback = true
        controller.requiresLinearPlayback = true

        self.playbackDelegate = playbackDelegate
        self.controller = controller
        updateFrame()
    }

    func toggle() {
        guard let controller else { return }
        if controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
            stopUpdates()
            return
        }

        configureAudioSession()
        startUpdates()
        updateFrame()
        startWhenReady(controller, retries: 12)
    }

    private func startWhenReady(_ controller: AVPictureInPictureController, retries: Int) {
        if controller.isPictureInPicturePossible {
            controller.startPictureInPicture()
        } else if retries > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.startWhenReady(controller, retries: retries - 1)
            }
        }
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    private func startUpdates() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateFrame() }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func stopUpdates() {
        timer?.invalidate()
        timer = nil
    }

    private func updateFrame() {
        if UIApplication.shared.applicationState != .active {
            if let lastGoodImage { enqueue(lastGoodImage) }
            return
        }
        guard !snapshotInFlight, let webView, webView.bounds.width > 1 else {
            if let lastGoodImage { enqueue(lastGoodImage) }
            return
        }
        snapshotInFlight = true

        let configuration = WKSnapshotConfiguration()
        configuration.rect = webView.bounds
        configuration.afterScreenUpdates = false
        webView.takeSnapshot(with: configuration) { [weak self] image, _ in
            Task { @MainActor in
                guard let self else { return }
                self.snapshotInFlight = false
                if let image, !self.isMostlyBlack(image) {
                    self.lastGoodImage = image
                    self.enqueue(image)
                } else if let lastGoodImage = self.lastGoodImage {
                    self.enqueue(lastGoodImage)
                }
            }
        }
    }

    private func isMostlyBlack(_ image: UIImage) -> Bool {
        guard let ciImage = CIImage(image: image),
              let filter = CIFilter(name: "CIAreaAverage") else { return false }
        let extent = ciImage.extent
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: extent), forKey: kCIInputExtentKey)
        guard let output = filter.outputImage else { return false }

        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: NSNull()]).render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )
        return Int(pixel[0]) + Int(pixel[1]) + Int(pixel[2]) < 18
    }

    private func enqueue(_ image: UIImage) {
        guard let sampleBuffer = makeSampleBuffer(from: image) else { return }
        if displayLayer.status == .failed {
            displayLayer.flush()
        }
        displayLayer.enqueue(sampleBuffer)
    }

    private func makeSampleBuffer(from image: UIImage) -> CMSampleBuffer? {
        guard let cgImage = image.cgImage else { return nil }
        let width = 540
        let height = max(320, Int(CGFloat(width) * image.size.height / max(image.size.width, 1)))

        var pixelBuffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        guard CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        ) == kCVReturnSuccess,
        let pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue |
                CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let target = AVMakeRect(
            aspectRatio: CGSize(width: cgImage.width, height: cgImage.height),
            insideRect: CGRect(x: 0, y: 0, width: width, height: height)
        )
        context.draw(cgImage, in: target)

        var formatDescription: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        ) == noErr,
        let formatDescription else { return nil }

        frameIndex += 1
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 2),
            presentationTimeStamp: CMTime(value: frameIndex, timescale: 2),
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        ) == noErr else { return nil }
        if let sampleBuffer {
            CMSetAttachment(
                sampleBuffer,
                key: kCMSampleAttachmentKey_DisplayImmediately,
                value: kCFBooleanTrue,
                attachmentMode: kCMAttachmentMode_ShouldPropagate
            )
        }
        return sampleBuffer
    }
}

private final class PiPPlaybackDelegate: NSObject,
    AVPictureInPictureSampleBufferPlaybackDelegate,
    AVPictureInPictureControllerDelegate {

    var onStop: (() -> Void)?

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        setPlaying playing: Bool
    ) {}

    func pictureInPictureControllerTimeRangeForPlayback(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> CMTimeRange {
        CMTimeRange(start: .zero, duration: .positiveInfinity)
    }

    func pictureInPictureControllerIsPlaybackPaused(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> Bool {
        false
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) {}

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }

    func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        onStop?()
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        onStop?()
    }
}
