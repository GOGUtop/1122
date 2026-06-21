import Foundation

enum ReplyOutcome: String, Codable, CaseIterable, Identifiable {
    case complete
    case truncated
    case empty

    var id: String { rawValue }

    var title: String {
        switch self {
        case .complete: return "已完成回复"
        case .truncated: return "回复已截断"
        case .empty: return "本次已空回"
        }
    }

    var notificationBody: String { bannerBody }

    var bannerTitle: String {
        switch self {
        case .complete: return "已完成回复"
        case .truncated: return "回复已截断"
        case .empty: return "本次已空回"
        }
    }

    var bannerBody: String {
        switch self {
        case .complete: return "画中画检测到 AI 已完成本次回复。"
        case .truncated: return "建议重 Roll 或继续生成。"
        case .empty: return "建议重 Roll。"
        }
    }
}
