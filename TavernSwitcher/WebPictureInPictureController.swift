import AVFoundation
import AVKit
import UIKit
import WebKit

@MainActor
final class WebPictureInPictureController: NSObject, AVPictureInPictureControllerDelegate {
    private weak var webView: WKWebView?
    private var controller: AVPictureInPictureController?
    private var contentController: WebPiPContentViewController?
    private var timer: Timer?
    private var snapshotInFlight = false

    var isActive: Bool {
        controller?.isPictureInPictureActive == true
    }

    func attach(to webView: WKWebView) {
        guard self.webView !== webView else { return }
        self.webView = webView

        let contentController = WebPiPContentViewController()
        contentController.preferredContentSize = CGSize(width: 390, height: 620)

        let source = AVPictureInPictureController.ContentSource(
            activeVideoCallSourceView: webView,
            contentViewController: contentController
        )
        let controller = AVPictureInPictureController(contentSource: source)
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = true

        self.contentController = contentController
        self.controller = controller
        updateSnapshot()
    }

    func toggle() {
        guard let controller else { return }
        if controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
            return
        }

        configureAudioSession()
        updateSnapshot()
        controller.startPictureInPicture()
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    private func startUpdates() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateSnapshot()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func stopUpdates() {
        timer?.invalidate()
        timer = nil
    }

    private func updateSnapshot() {
        guard !snapshotInFlight, let webView, webView.bounds.width > 1 else { return }
        snapshotInFlight = true

        let configuration = WKSnapshotConfiguration()
        configuration.rect = webView.bounds
        configuration.afterScreenUpdates = false
        webView.takeSnapshot(with: configuration) { [weak self] image, _ in
            Task { @MainActor in
                guard let self else { return }
                self.snapshotInFlight = false
                if let image {
                    self.contentController?.display(image)
                }
            }
        }
    }

    func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        startUpdates()
    }

    func pictureInPictureControllerWillStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        stopUpdates()
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        stopUpdates()
    }
}

@MainActor
private final class WebPiPContentViewController: AVPictureInPictureVideoCallViewController {
    private let imageView = UIImageView()
    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .black
        view.addSubview(imageView)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.text = "云洞酒馆"
        statusLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        statusLabel.textColor = .white
        statusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        statusLabel.textAlignment = .center
        statusLabel.layer.cornerRadius = 10
        statusLabel.clipsToBounds = true
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            statusLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 78),
            statusLabel.heightAnchor.constraint(equalToConstant: 22)
        ])
    }

    func display(_ image: UIImage) {
        imageView.image = image
    }
}
