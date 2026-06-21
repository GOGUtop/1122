import UIKit
import UserNotifications

@MainActor
final class ReplyNotificationService {
    static let shared = ReplyNotificationService()

    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var activeGenerationId: String?
    private var notifiedGenerationIds = Set<String>()
    private var mirroredBannerIds = Set<String>()
    private var lastFinishAt: Date?
    private var lastMappedBannerAt: Date?
    private let duplicateSuppressionWindow: TimeInterval = 8

    func generationStarted(id: String) {
        // 系统提醒不再由三路检测直接触发；这里只负责维持后台活跃和生成周期锁。
        if activeGenerationId != nil { return }
        if let lastFinishAt, Date().timeIntervalSince(lastFinishAt) < 1.2 { return }
        activeGenerationId = id
        BackgroundKeepAliveService.shared.start(reason: "generation")
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "SillyTavernReply") {
            self.endBackgroundTask()
        }
    }

    func generationFinished(id: String, outcome: ReplyOutcome) {
        // 这里仍不弹横幅、不放声音、不震动，避免原生事件/服务端/轮询三路重复。
        // 真正的系统横幅只允许由画中画状态条映射一次。
        guard activeGenerationId == id else { return }
        guard !notifiedGenerationIds.contains(id) else { return }
        if let lastFinishAt, Date().timeIntervalSince(lastFinishAt) < duplicateSuppressionWindow {
            activeGenerationId = nil
            return
        }
        notifiedGenerationIds.insert(id)
        trimCachesIfNeeded()
        activeGenerationId = nil
        lastFinishAt = Date()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            BackgroundKeepAliveService.shared.stop(reason: "generation")
            self.endBackgroundTask()
        }
    }

    func mirrorPiPBannerToSystem(id: String, outcome: ReplyOutcome) {
        guard UserDefaults.standard.object(forKey: "mirrorPiPAlertToBanner") as? Bool ?? true else { return }
        guard !mirroredBannerIds.contains(id) else { return }
        if let lastMappedBannerAt, Date().timeIntervalSince(lastMappedBannerAt) < 3.0 {
            return
        }

        mirroredBannerIds.insert(id)
        trimCachesIfNeeded()
        lastMappedBannerAt = Date()

        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional || settings.authorizationStatus == .ephemeral else {
                center.requestAuthorization(options: [.alert, .badge]) { _, _ in }
                return
            }

            let content = UNMutableNotificationContent()
            content.title = outcome.bannerTitle
            content.body = outcome.bannerBody
            content.categoryIdentifier = "TAVERN_REPLY_RESULT"
            content.threadIdentifier = "TAVERN_REPLY_RESULT"
            content.interruptionLevel = .active
            content.sound = nil

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.25, repeats: false)
            let request = UNNotificationRequest(
                identifier: "pip-result-\(id)",
                content: content,
                trigger: trigger
            )
            center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
            center.add(request)
        }
    }

    func sendBannerTest() {
        let id = "test-\(UUID().uuidString)"
        mirrorPiPBannerToSystem(id: id, outcome: .complete)
    }

    func requestAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .badge]) { _, _ in }
        }
    }

    private func trimCachesIfNeeded() {
        if notifiedGenerationIds.count > 60 {
            notifiedGenerationIds.removeAll(keepingCapacity: true)
        }
        if mirroredBannerIds.count > 60 {
            mirroredBannerIds.removeAll(keepingCapacity: true)
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}
