import AudioToolbox
import AVFoundation
import UIKit
import UserNotifications

@MainActor
final class ReplyNotificationService {
    static let shared = ReplyNotificationService()

    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var activeGenerationId: String?
    private var notifiedGenerationIds = Set<String>()
    private var alertPlayer: AVAudioPlayer?
    private var lastAlertAt: Date?
    private let duplicateSuppressionWindow: TimeInterval = 6

    func generationStarted(id: String) {
        // 同一时间只允许存在一轮生成。原生事件、服务端和轮询都会复用它。
        if activeGenerationId != nil { return }
        // 某些 SillyTavern 事件会在结束后立刻补发伪 start，禁止它开启新一轮提醒。
        if let lastAlertAt,
           Date().timeIntervalSince(lastAlertAt) < duplicateSuppressionWindow {
            return
        }
        activeGenerationId = id
        BackgroundKeepAliveService.shared.start(reason: "generation")
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "SillyTavernReply") {
            self.endBackgroundTask()
        }
    }

    func generationFinished(id: String, outcome: ReplyOutcome) {
        // 没有真正开始过生成，或本轮已经由另一检测通道提醒过时，全部忽略。
        guard activeGenerationId == id else { return }
        guard !notifiedGenerationIds.contains(id) else { return }
        if let lastAlertAt,
           Date().timeIntervalSince(lastAlertAt) < duplicateSuppressionWindow {
            activeGenerationId = nil
            return
        }
        notifiedGenerationIds.insert(id)
        if notifiedGenerationIds.count > 30 {
            notifiedGenerationIds.removeAll(keepingCapacity: true)
            notifiedGenerationIds.insert(id)
        }
        activeGenerationId = nil
        lastAlertAt = Date()

        playSingleAlert(for: outcome)

        let content = UNMutableNotificationContent()
        content.title = outcome.title
        content.subtitle = "云洞酒馆"
        content.body = outcome.notificationBody
        content.categoryIdentifier = "TAVERN_REPLY_RESULT"
        content.threadIdentifier = "tavern-reply-results"
        content.interruptionLevel = .timeSensitive
        content.relevanceScore = 1
        content.userInfo = ["outcome": outcome.rawValue]
        // 声音和震动由 App 自己播放，通知保持静音，避免同一次结束提醒两遍。
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: "reply-\(id)",
            content: content,
            // 给 iOS 一点时间完成前后台/PiP 状态切换，更容易按顶部横幅展示。
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.2, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            BackgroundKeepAliveService.shared.stop(reason: "generation")
            self.endBackgroundTask()
        }
    }

    func sendBannerTest() {
        let content = UNMutableNotificationContent()
        content.title = "顶部横幅测试"
        content.subtitle = "云洞酒馆"
        content.body = "如果你看到这条从屏幕顶部弹出，说明横幅通知已经开启。"
        content.categoryIdentifier = "TAVERN_REPLY_RESULT"
        content.interruptionLevel = .timeSensitive
        content.sound = nil
        let request = UNNotificationRequest(
            identifier: "banner-test-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.2, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func playSingleAlert(for outcome: ReplyOutcome) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers, .duckOthers])
        try? session.setActive(true)

        if let url = NotificationSoundSettings.shared.soundURL(for: outcome),
           let player = try? AVAudioPlayer(contentsOf: url) {
            alertPlayer = player
            player.volume = 1
            player.prepareToPlay()
            player.play()
        } else {
            AudioServicesPlaySystemSound(1007)
        }

        // 只震动这一次；静音通知本身不会再触发第二次震动。
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}
