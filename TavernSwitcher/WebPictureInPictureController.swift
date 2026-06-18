import AVFoundation
import AVKit
import UIKit
import WebKit

@MainActor
final class WebPictureInPictureController: NSObject {
    private weak var webView: WKWebView?
    private let sourceView = UIView(frame: CGRect(x: 1, y: 1, width: 2, height: 2))
    private let previewController = WebPiPPreviewController()
    private var controller: AVPictureInPictureController?
    private var delegateBox: PiPControllerDelegate?
    private var timer: Timer?
    private var snapshotInFlight = false
    private var lastGoodImage: UIImage?

    func attach(to webView: WKWebView) {
        guard self.webView !== webView else { return }
        self.webView = webView

        sourceView.backgroundColor = .black
        sourceView.alpha = 0.02
        sourceView.isUserInteractionEnabled = false
        if sourceView.superview == nil {
            webView.addSubview(sourceView)
        }

        previewController.preferredContentSize = CGSize(width: 390, height: 760)
        previewController.updatePlaceholder()

        let delegate = PiPControllerDelegate()
        delegate.onStop = { [weak self] in
            Task { @MainActor in self?.stopUpdates() }
        }
        delegate.onFailed = { [weak self] _ in
            Task { @MainActor in self?.stopUpdates() }
        }

        if #available(iOS 15.0, *) {
            let contentSource = AVPictureInPictureController.ContentSource(
                activeVideoCallSourceView: sourceView,
                contentViewController: previewController
            )
            let controller = AVPictureInPictureController(contentSource: contentSource)
            controller.delegate = delegate
            controller.canStartPictureInPictureAutomaticallyFromInline = true
            self.controller = controller
            self.delegateBox = delegate
        }

        updateFrame(force: true)
    }

    @discardableResult
    func start() -> Bool {
        guard AVPictureInPictureController.isPictureInPictureSupported(), let controller else { return false }
        guard !controller.isPictureInPictureActive else { return true }
        guard let webView else { return false }

        if sourceView.superview == nil {
            webView.addSubview(sourceView)
        }
        sourceView.frame = CGRect(x: 1, y: 1, width: 2, height: 2)
        sourceView.alpha = 0.02
        sourceView.isHidden = false

        configureAudioSession()
        BackgroundKeepAliveService.shared.start(reason: "pip")
        startUpdates()
        updateFrame(force: true)
        startWhenReady(controller, retries: 30)
        return true
    }

    @discardableResult
    func toggle() -> Bool {
        guard let controller else { return false }
        if controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
            stopUpdates()
            return true
        }
        return start()
    }

    private func startWhenReady(_ controller: AVPictureInPictureController, retries: Int) {
        if controller.isPictureInPicturePossible {
            controller.startPictureInPicture()
        } else if retries > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self, weak controller] in
                guard let self, let controller else { return }
                self.updateFrame(force: true)
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
        timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateFrame(force: false) }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func stopUpdates() {
        timer?.invalidate()
        timer = nil
        BackgroundKeepAliveService.shared.stop(reason: "pip")
    }

    private func updateFrame(force: Bool) {
        guard !snapshotInFlight, let webView, webView.bounds.width > 2 else {
            if let lastGoodImage { previewController.update(image: lastGoodImage) }
            return
        }

        snapshotInFlight = true
        let config = WKSnapshotConfiguration()
        config.rect = webView.bounds
        config.afterScreenUpdates = false
        webView.takeSnapshot(with: config) { [weak self] image, _ in
            Task { @MainActor in
                guard let self else { return }
                self.snapshotInFlight = false
                if let image, !image.isNearlyBlank {
                    self.lastGoodImage = image
                    self.previewController.update(image: image)
                } else if let lastGoodImage = self.lastGoodImage {
                    self.previewController.update(image: lastGoodImage)
                }
            }
        }
    }
}

private final class WebPiPPreviewController: AVPictureInPictureVideoCallViewController {
    private let imageView = UIImageView()
    private let label = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageView)

        label.text = "云洞画中画准备中…"
        label.textColor = .white
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    func updatePlaceholder() {
        loadViewIfNeeded()
        label.isHidden = false
    }

    func update(image: UIImage) {
        loadViewIfNeeded()
        label.isHidden = true
        imageView.image = image
    }
}

private final class PiPControllerDelegate: NSObject, AVPictureInPictureControllerDelegate {
    var onStop: (() -> Void)?
    var onFailed: ((Error) -> Void)?

    func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        onStop?()
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        onFailed?(error)
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }
}

private extension UIImage {
    var isNearlyBlank: Bool {
        guard let cgImage else { return true }
        let width = 1
        let height = 1
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        let sum = Int(pixel[0]) + Int(pixel[1]) + Int(pixel[2])
        return sum < 16 || sum > 748
    }
}
