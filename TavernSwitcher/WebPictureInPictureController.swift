import AVFoundation
import AVKit
import UIKit
import WebKit

@MainActor
final class WebPictureInPictureController: NSObject {
    private weak var webView: WKWebView?
    private let sourceView = UIView(frame: CGRect(x: 1, y: 1, width: 2, height: 2))
    private let previewController = LiveReplyPiPViewController()
    private var controller: AVPictureInPictureController?
    private var delegateBox: PiPControllerDelegate?

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
        previewController.showWaiting()

        let delegate = PiPControllerDelegate()
        delegate.onStop = {
            Task { @MainActor in
                BackgroundKeepAliveService.shared.stop(reason: "pip")
            }
        }
        delegate.onFailed = { _ in
            Task { @MainActor in
                BackgroundKeepAliveService.shared.stop(reason: "pip")
            }
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
            delegateBox = delegate
        }
    }

    func generationStarted(character: String?) {
        previewController.start(character: character)
    }

    func updateReply(text: String, character: String?) {
        previewController.update(text: text, character: character)
    }

    func generationFinished(text: String, outcome: ReplyOutcome) {
        previewController.finish(text: text, outcome: outcome)
    }

    func updateBridgeStatus(_ text: String, connected: Bool) {
        previewController.updateConnection(text, connected: connected)
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
        startWhenReady(controller, retries: 30)
        return true
    }

    @discardableResult
    func toggle() -> Bool {
        guard let controller else { return false }
        if controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
            BackgroundKeepAliveService.shared.stop(reason: "pip")
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
                self.startWhenReady(controller, retries: retries - 1)
            }
        }
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
        try? session.setActive(true)
    }
}

private final class LiveReplyPiPViewController: AVPictureInPictureVideoCallViewController {
    private let characterLabel = UILabel()
    private let statusLabel = UILabel()
    private let textView = UITextView()
    private let activity = UIActivityIndicatorView(style: .medium)
    private let connectionDot = UIView()
    private var fullText = ""

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.025, green: 0.04, blue: 0.07, alpha: 1)

        characterLabel.font = .systemFont(ofSize: 15, weight: .bold)
        characterLabel.textColor = UIColor(red: 1, green: 0.89, blue: 0.55, alpha: 1)
        characterLabel.text = "云洞酒馆"

        statusLabel.font = .systemFont(ofSize: 11, weight: .medium)
        statusLabel.textColor = .secondaryLabel
        statusLabel.text = "等待生成"

        connectionDot.backgroundColor = .systemOrange
        connectionDot.layer.cornerRadius = 4

        textView.backgroundColor = .clear
        textView.textColor = .white
        textView.font = .systemFont(ofSize: 15)
        textView.isEditable = false
        textView.isSelectable = false
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 18, right: 12)

        let header = UIStackView(arrangedSubviews: [connectionDot, characterLabel, UIView(), activity])
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 9

        [header, statusLabel, textView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        NSLayoutConstraint.activate([
            connectionDot.widthAnchor.constraint(equalToConstant: 8),
            connectionDot.heightAnchor.constraint(equalToConstant: 8),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            header.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            statusLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 17),
            statusLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            statusLabel.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 3),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 7),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -7),
            textView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 5),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -5)
        ])
    }

    func showWaiting() {
        loadViewIfNeeded()
        statusLabel.text = "等待 AI 回复"
        textView.text = "开始生成后，这里会实时显示正在输出的内容。"
    }

    func start(character: String?) {
        loadViewIfNeeded()
        fullText = ""
        characterLabel.text = character?.isEmpty == false ? character : "云洞酒馆"
        statusLabel.text = "AI 正在回复…"
        textView.text = "正在连接生成流…"
        activity.startAnimating()
    }

    func update(text: String, character: String?) {
        loadViewIfNeeded()
        if let character, !character.isEmpty {
            characterLabel.text = character
        }
        fullText = text
        statusLabel.text = "AI 正在回复…"
        textView.text = text.isEmpty ? "正在生成…" : text
        activity.startAnimating()
        scrollToBottom()
    }

    func finish(text: String, outcome: ReplyOutcome) {
        loadViewIfNeeded()
        fullText = text
        statusLabel.text = outcome.title
        textView.text = text.isEmpty ? outcome.notificationBody : text
        activity.stopAnimating()
        scrollToBottom()
    }

    func updateConnection(_ text: String, connected: Bool) {
        loadViewIfNeeded()
        connectionDot.backgroundColor = connected ? .systemGreen : .systemOrange
        if fullText.isEmpty && !activity.isAnimating {
            statusLabel.text = text
        }
    }

    private func scrollToBottom() {
        guard !textView.text.isEmpty else { return }
        textView.scrollRangeToVisible(NSRange(location: max(0, textView.text.utf16.count - 1), length: 1))
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
