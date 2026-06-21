import UIKit

@MainActor
final class ReplyNotificationService {
    static let shared = ReplyNotificationService()

    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var activeGenerationId: String?
    private var notifiedGenerationIds = Set<String>()
    private var lastFinishAt: Date?
    private let duplicateSuppressionWindow: TimeInterval = 8

    func generationStarted(id: String) {
        // 现在采用“画中画内提示”模式：这里仅负责维持后台活跃和生成周期锁。
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
        // 不再弹系统横幅、不再播放声音、不再震动，避免三路检测造成重复提醒。
        // 这里只保留去重和后台任务释放；真正提醒交给画中画内部状态条。
        guard activeGenerationId == id else { return }
        guard !notifiedGenerationIds.contains(id) else { return }
        if let lastFinishAt, Date().timeIntervalSince(lastFinishAt) < duplicateSuppressionWindow {
            activeGenerationId = nil
            return
        }
        notifiedGenerationIds.insert(id)
        if notifiedGenerationIds.count > 40 {
            notifiedGenerationIds.removeAll(keepingCapacity: true)
            notifiedGenerationIds.insert(id)
        }
        activeGenerationId = nil
        lastFinishAt = Date()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            BackgroundKeepAliveService.shared.stop(reason: "generation")
            self.endBackgroundTask()
        }
    }

    func sendBannerTest() {
        // v2.5 起系统横幅提醒已关闭。
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}
