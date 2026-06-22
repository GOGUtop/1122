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
    private var lastFinishSignature = ""
    private var lastFinishAt: Date?

    func attach(to webView: WKWebView) {
        guard self.webView !== webView else { return }
        self.webView = webView
        sourceView.backgroundColor = .black
        sourceView.alpha = 0.02
        sourceView.isUserInteractionEnabled = false
        if sourceView.superview == nil {
            webView.addSubview(sourceView)
        }

        previewController.preferredContentSize = CGSize(width: 360, height: 640)
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
        lastFinishSignature = ""
        lastFinishAt = nil
        previewController.start(character: character)
    }

    func updateReply(text: String, character: String?) {
        previewController.update(text: text, character: character)
    }

    func generationFinished(text: String, outcome: ReplyOutcome, generationId: String? = nil) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = String(normalized.suffix(120))
        let signature = "\(outcome.rawValue)-\(normalized.count)-\(suffix)"
        if signature == lastFinishSignature,
           let lastFinishAt,
           Date().timeIntervalSince(lastFinishAt) < 8 {
            return
        }
        lastFinishSignature = signature
        lastFinishAt = Date()
        previewController.finish(text: text, outcome: outcome)

        if controller?.isPictureInPictureActive == true {
            let bannerId = generationId ?? "signature-\(signature.hashValue)"
            ReplyNotificationService.shared.mirrorPiPBannerToSystem(id: bannerId, outcome: outcome)
        }
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
    private let headerBar = UIView()
    private let characterLabel = UILabel()
    private let statusPill = UILabel()
    private let activity = UIActivityIndicatorView(style: .medium)
    private let connectionDot = UIView()
    private let chatSurface = UIView()
    private let assistantBubble = UIView()
    private let avatarLabel = UILabel()
    private let roleLabel = UILabel()
    private let textView = UITextView()
    private let inputBar = UIView()
    private let inputLabel = UILabel()
    private let finishBanner = UIView()
    private let finishTitleLabel = UILabel()
    private let finishBodyLabel = UILabel()
    private var fullText = ""

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.018, green: 0.026, blue: 0.045, alpha: 1)
        view.layer.cornerCurve = .continuous

        headerBar.backgroundColor = UIColor.white.withAlphaComponent(0.075)
        headerBar.layer.cornerRadius = 19
        headerBar.layer.cornerCurve = .continuous
        headerBar.layer.borderWidth = 1
        headerBar.layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor

        connectionDot.backgroundColor = .systemOrange
        connectionDot.layer.cornerRadius = 4

        characterLabel.font = .systemFont(ofSize: 13, weight: .heavy)
        characterLabel.textColor = UIColor(red: 1, green: 0.89, blue: 0.55, alpha: 1)
        characterLabel.text = "云洞酒馆"
        characterLabel.lineBreakMode = .byTruncatingTail

        statusPill.font = .systemFont(ofSize: 10, weight: .heavy)
        statusPill.textColor = .white
        statusPill.textAlignment = .center
        statusPill.text = "待机"
        statusPill.backgroundColor = UIColor.white.withAlphaComponent(0.10)
        statusPill.layer.cornerRadius = 10
        statusPill.clipsToBounds = true

        chatSurface.backgroundColor = UIColor.white.withAlphaComponent(0.045)
        chatSurface.layer.cornerRadius = 22
        chatSurface.layer.cornerCurve = .continuous
        chatSurface.layer.borderWidth = 1
        chatSurface.layer.borderColor = UIColor.white.withAlphaComponent(0.09).cgColor

        assistantBubble.backgroundColor = UIColor(red: 0.10, green: 0.13, blue: 0.20, alpha: 0.92)
        assistantBubble.layer.cornerRadius = 18
        assistantBubble.layer.cornerCurve = .continuous
        assistantBubble.layer.borderWidth = 1
        assistantBubble.layer.borderColor = UIColor.white.withAlphaComponent(0.10).cgColor

        avatarLabel.text = "AI"
        avatarLabel.font = .systemFont(ofSize: 10, weight: .black)
        avatarLabel.textColor = .white
        avatarLabel.textAlignment = .center
        avatarLabel.backgroundColor = UIColor(red: 0.26, green: 0.48, blue: 0.94, alpha: 0.85)
        avatarLabel.layer.cornerRadius = 12
        avatarLabel.clipsToBounds = true

        roleLabel.font = .systemFont(ofSize: 11, weight: .heavy)
        roleLabel.textColor = UIColor.white.withAlphaComponent(0.82)
        roleLabel.text = "正在等待回复"
        roleLabel.lineBreakMode = .byTruncatingTail

        textView.backgroundColor = .clear
        textView.textColor = .white
        textView.font = .systemFont(ofSize: 12, weight: .regular)
        textView.isEditable = false
        textView.isSelectable = false
        textView.showsVerticalScrollIndicator = false
        textView.textContainerInset = UIEdgeInsets(top: 7, left: 7, bottom: 9, right: 7)
        textView.textContainer.lineFragmentPadding = 0

        inputBar.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        inputBar.layer.cornerRadius = 15
        inputBar.layer.cornerCurve = .continuous
        inputBar.layer.borderWidth = 1
        inputBar.layer.borderColor = UIColor.white.withAlphaComponent(0.09).cgColor

        inputLabel.font = .systemFont(ofSize: 10.5, weight: .semibold)
        inputLabel.textColor = UIColor.white.withAlphaComponent(0.58)
        inputLabel.text = "缩小版酒馆镜像 · 等待生成"

        finishBanner.layer.cornerRadius = 17
        finishBanner.layer.cornerCurve = .continuous
        finishBanner.layer.borderWidth = 1
        finishBanner.layer.borderColor = UIColor.white.withAlphaComponent(0.20).cgColor
        finishBanner.alpha = 0

        finishTitleLabel.font = .systemFont(ofSize: 15, weight: .heavy)
        finishTitleLabel.textColor = .white
        finishTitleLabel.textAlignment = .center
        finishTitleLabel.numberOfLines = 1

        finishBodyLabel.font = .systemFont(ofSize: 10.5, weight: .semibold)
        finishBodyLabel.textColor = UIColor.white.withAlphaComponent(0.90)
        finishBodyLabel.textAlignment = .center
        finishBodyLabel.numberOfLines = 2

        [headerBar, chatSurface, inputBar, finishBanner].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        [connectionDot, characterLabel, statusPill, activity].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            headerBar.addSubview($0)
        }
        assistantBubble.translatesAutoresizingMaskIntoConstraints = false
        chatSurface.addSubview(assistantBubble)
        [avatarLabel, roleLabel, textView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            assistantBubble.addSubview($0)
        }
        inputLabel.translatesAutoresizingMaskIntoConstraints = false
        inputBar.addSubview(inputLabel)
        [finishTitleLabel, finishBodyLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            finishBanner.addSubview($0)
        }

        NSLayoutConstraint.activate([
            headerBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            headerBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            headerBar.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            headerBar.heightAnchor.constraint(equalToConstant: 42),

            connectionDot.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor, constant: 12),
            connectionDot.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            connectionDot.widthAnchor.constraint(equalToConstant: 8),
            connectionDot.heightAnchor.constraint(equalToConstant: 8),
            characterLabel.leadingAnchor.constraint(equalTo: connectionDot.trailingAnchor, constant: 8),
            characterLabel.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            activity.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor, constant: -10),
            activity.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            statusPill.trailingAnchor.constraint(equalTo: activity.leadingAnchor, constant: -8),
            statusPill.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            statusPill.widthAnchor.constraint(greaterThanOrEqualToConstant: 46),
            statusPill.heightAnchor.constraint(equalToConstant: 21),
            characterLabel.trailingAnchor.constraint(lessThanOrEqualTo: statusPill.leadingAnchor, constant: -8),

            inputBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            inputBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            inputBar.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            inputBar.heightAnchor.constraint(equalToConstant: 31),
            inputLabel.leadingAnchor.constraint(equalTo: inputBar.leadingAnchor, constant: 12),
            inputLabel.trailingAnchor.constraint(equalTo: inputBar.trailingAnchor, constant: -12),
            inputLabel.centerYAnchor.constraint(equalTo: inputBar.centerYAnchor),

            chatSurface.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            chatSurface.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            chatSurface.topAnchor.constraint(equalTo: headerBar.bottomAnchor, constant: 7),
            chatSurface.bottomAnchor.constraint(equalTo: inputBar.topAnchor, constant: -7),

            assistantBubble.leadingAnchor.constraint(equalTo: chatSurface.leadingAnchor, constant: 8),
            assistantBubble.trailingAnchor.constraint(equalTo: chatSurface.trailingAnchor, constant: -8),
            assistantBubble.topAnchor.constraint(equalTo: chatSurface.topAnchor, constant: 8),
            assistantBubble.bottomAnchor.constraint(equalTo: chatSurface.bottomAnchor, constant: -8),

            avatarLabel.leadingAnchor.constraint(equalTo: assistantBubble.leadingAnchor, constant: 10),
            avatarLabel.topAnchor.constraint(equalTo: assistantBubble.topAnchor, constant: 10),
            avatarLabel.widthAnchor.constraint(equalToConstant: 24),
            avatarLabel.heightAnchor.constraint(equalToConstant: 24),
            roleLabel.leadingAnchor.constraint(equalTo: avatarLabel.trailingAnchor, constant: 8),
            roleLabel.trailingAnchor.constraint(equalTo: assistantBubble.trailingAnchor, constant: -10),
            roleLabel.centerYAnchor.constraint(equalTo: avatarLabel.centerYAnchor),

            textView.leadingAnchor.constraint(equalTo: assistantBubble.leadingAnchor, constant: 10),
            textView.trailingAnchor.constraint(equalTo: assistantBubble.trailingAnchor, constant: -10),
            textView.topAnchor.constraint(equalTo: avatarLabel.bottomAnchor, constant: 6),
            textView.bottomAnchor.constraint(equalTo: assistantBubble.bottomAnchor, constant: -9),

            finishBanner.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            finishBanner.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            finishBanner.topAnchor.constraint(equalTo: chatSurface.topAnchor, constant: 13),
            finishBanner.heightAnchor.constraint(greaterThanOrEqualToConstant: 72),
            finishTitleLabel.leadingAnchor.constraint(equalTo: finishBanner.leadingAnchor, constant: 12),
            finishTitleLabel.trailingAnchor.constraint(equalTo: finishBanner.trailingAnchor, constant: -12),
            finishTitleLabel.topAnchor.constraint(equalTo: finishBanner.topAnchor, constant: 11),
            finishBodyLabel.leadingAnchor.constraint(equalTo: finishBanner.leadingAnchor, constant: 12),
            finishBodyLabel.trailingAnchor.constraint(equalTo: finishBanner.trailingAnchor, constant: -12),
            finishBodyLabel.topAnchor.constraint(equalTo: finishTitleLabel.bottomAnchor, constant: 4),
            finishBodyLabel.bottomAnchor.constraint(equalTo: finishBanner.bottomAnchor, constant: -11)
        ])
    }

    func showWaiting() {
        loadViewIfNeeded()
        hideFinishBanner(animated: false)
        statusPill.text = "待机"
        roleLabel.text = "正在等待回复"
        inputLabel.text = "缩小版酒馆镜像 · 等待生成"
        textView.text = "开始生成后，这里会以缩小版酒馆样式实时显示 AI 正在输出的内容。"
    }

    func start(character: String?) {
        loadViewIfNeeded()
        hideFinishBanner(animated: true)
        fullText = ""
        characterLabel.text = character?.isEmpty == false ? character : "云洞酒馆"
        roleLabel.text = character?.isEmpty == false ? "AI · \(character ?? "")" : "AI 正在回复"
        statusPill.text = "生成中"
        inputLabel.text = "AI 正在输入…"
        textView.text = "正在连接生成流…"
        activity.startAnimating()
    }

    func update(text: String, character: String?) {
        loadViewIfNeeded()
        hideFinishBanner(animated: true)
        if let character, !character.isEmpty {
            characterLabel.text = character
            roleLabel.text = "AI · \(character)"
        }
        fullText = text
        statusPill.text = "生成中"
        inputLabel.text = "AI 正在输入…"
        textView.text = compact(text.isEmpty ? "正在生成…" : text)
        activity.startAnimating()
        scrollToBottom()
    }

    func finish(text: String, outcome: ReplyOutcome) {
        loadViewIfNeeded()
        fullText = text
        statusPill.text = outcome.title
        inputLabel.text = outcome.inputHint
        textView.text = compact(text.isEmpty ? outcome.notificationBody : text)
        activity.stopAnimating()
        showFinishBanner(outcome)
        scrollToBottom()
    }

    func updateConnection(_ text: String, connected: Bool) {
        loadViewIfNeeded()
        connectionDot.backgroundColor = connected ? .systemGreen : .systemOrange
        if !connected {
            statusPill.text = "连接中"
            if fullText.isEmpty {
                textView.text = text
                inputLabel.text = "实时桥接正在重连…"
            }
        } else if fullText.isEmpty && !activity.isAnimating {
            statusPill.text = "已连接"
            inputLabel.text = "缩小版酒馆镜像 · 等待生成"
        }
    }

    private func showFinishBanner(_ outcome: ReplyOutcome) {
        finishBanner.layer.removeAllAnimations()
        finishTitleLabel.text = outcome.pipTitle
        finishBodyLabel.text = outcome.pipBody
        finishBanner.backgroundColor = outcome.pipColor
        finishBanner.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
        finishBanner.alpha = 0
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut]) {
            self.finishBanner.alpha = 1
            self.finishBanner.transform = .identity
        } completion: { _ in
            UIView.animateKeyframes(withDuration: 1.1, delay: 0, options: [.repeat, .autoreverse]) {
                UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 1) {
                    self.finishBanner.alpha = 0.66
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.2) { [weak self] in
                guard let self else { return }
                self.finishBanner.layer.removeAllAnimations()
                UIView.animate(withDuration: 0.18) {
                    self.finishBanner.alpha = 1
                }
            }
        }
    }

    private func hideFinishBanner(animated: Bool) {
        finishBanner.layer.removeAllAnimations()
        let changes = { self.finishBanner.alpha = 0 }
        if animated {
            UIView.animate(withDuration: 0.16, animations: changes)
        } else {
            changes()
        }
    }

    private func compact(_ text: String) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > 2400 else { return cleaned }
        return "…\n" + String(cleaned.suffix(2400))
    }

    private func scrollToBottom() {
        guard !textView.text.isEmpty else { return }
        textView.scrollRangeToVisible(NSRange(location: max(0, textView.text.utf16.count - 1), length: 1))
    }
}

private extension ReplyOutcome {
    var pipTitle: String {
        switch self {
        case .complete: return "✅ 已完成回复"
        case .truncated: return "⚠️ 回复已截断"
        case .empty: return "⚠️ 本次已空回"
        }
    }

    var pipBody: String {
        switch self {
        case .complete: return "回到 App 可点：快速重Roll / 新建记录"
        case .truncated: return "建议回到 App 点：快速重Roll"
        case .empty: return "建议回到 App 点：快速重Roll"
        }
    }

    var inputHint: String {
        switch self {
        case .complete: return "已完成 · 可返回酒馆查看"
        case .truncated: return "已截断 · 建议快速重Roll"
        case .empty: return "已空回 · 建议快速重Roll"
        }
    }

    var pipColor: UIColor {
        switch self {
        case .complete:
            return UIColor.systemGreen.withAlphaComponent(0.92)
        case .truncated:
            return UIColor.systemOrange.withAlphaComponent(0.94)
        case .empty:
            return UIColor.systemRed.withAlphaComponent(0.94)
        }
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
