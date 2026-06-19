import UIKit
import UserNotifications

@MainActor
final class ReplyNotificationService {
    static let shared = ReplyNotificationService()

    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var activeGenerationId: String?
    private var notifiedGenerationIds = Set<String>()

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

        let content = UNMutableNotificationContent()
        content.title = outcome.title
        content.body = outcome.notificationBody
        content.sound = NotificationSoundSettings.shared.notificationSound(for: outcome)

        let request = UNNotificationRequest(
            identifier: "reply-\(id)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
        BackgroundKeepAliveService.shared.stop(reason: "generation")
        endBackgroundTask()
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}
