import AudioToolbox
import UIKit
import UserNotifications

@MainActor
final class ReplyNotificationService {
    static let shared = ReplyNotificationService()

    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    func generationStarted() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "SillyTavernReply") {
            self.endBackgroundTask()
        }
    }

    func generationFinished() {
        AudioServicesPlaySystemSound(1007)
        let content = UNMutableNotificationContent()
        content.title = "SillyTavern 回复完成"
        content.body = "角色已经完成本次回复，点此返回酒馆查看。"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "reply-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
        endBackgroundTask()
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}
