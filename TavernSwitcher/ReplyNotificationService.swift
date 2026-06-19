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

    func generationStarted(id: String) {
        guard activeGenerationId != id else { return }
        activeGenerationId = id
        BackgroundKeepAliveService.shared.start(reason: "generation")
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "SillyTavernReply") {
            self.endBackgroundTask()
        }
    }

    func generationFinished(id: String, outcome: ReplyOutcome) {
        guard !notifiedGenerationIds.contains(id) else { return }
        notifiedGenerationIds.insert(id)
        if notifiedGenerationIds.count > 30 {
            notifiedGenerationIds.removeAll(keepingCapacity: true)
            notifiedGenerationIds.insert(id)
        }
        if activeGenerationId == id {
            activeGenerationId = nil
        }

        playSingleAlert(for: outcome)

        let content = UNMutableNotificationContent()
        content.title = outcome.title
        content.body = outcome.notificationBody
        // 声音和震动由 App 自己播放，通知保持静音，避免同一次结束提醒两遍。
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: "reply-\(id)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            BackgroundKeepAliveService.shared.stop(reason: "generation")
            self.endBackgroundTask()
        }
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
