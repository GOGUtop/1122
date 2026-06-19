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

    var notificationBody: String {
        switch self {
        case .complete: return "角色已经完成本次回复，点击返回酒馆查看。"
        case .truncated: return "回复达到长度限制，建议重 Roll 或继续生成。"
        case .empty: return "没有生成有效正文，建议重 Roll。"
        }
    }
}
